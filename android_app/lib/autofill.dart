/// Autofill in other apps (the phone side of MyVaultAutofillService.kt).
///
/// * When another app's login box asks MyVault to fill, Android opens MyVault's
///   unlock screen in a separate activity; [autofillRequest] is then set, and
///   after unlocking the user picks an account in [AutofillPickPage].
/// * Logins Android captured ("Save to MyVault?") wait in a Keystore-encrypted
///   inbox; [importCaptures] adds them to the vault after unlocking.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kinds.dart';
import 'l10n.dart';
import 'theme.dart';
import 'vault.dart';

const _fill = MethodChannel(
  'myvault/autofill',
); // only in the autofill activity
const _setup = MethodChannel(
  'myvault/autofill_setup',
); // only in the main activity

class AutofillRequest {
  final String target, label;
  final bool web, hasUser;
  AutofillRequest(this.target, this.label, this.web, this.hasUser);
}

/// Set when this run of the app was opened to fill another app's login.
AutofillRequest? autofillRequest;

Future<void> loadAutofillRequest() async {
  try {
    final m = await _fill.invokeMapMethod<String, dynamic>('request');
    if (m != null && '${m['target']}'.isNotEmpty) {
      autofillRequest = AutofillRequest(
        '${m['target']}',
        '${m['label']}',
        m['web'] == true,
        m['hasUser'] == true,
      );
    }
  } on MissingPluginException {
    autofillRequest = null; // normal launch
  }
}

String _host(String v) {
  var s = v.trim().toLowerCase();
  if (!s.contains('://')) s = 'https://$s';
  var h = Uri.tryParse(s)?.host ?? '';
  if (h.startsWith('www.')) h = h.substring(4);
  return h;
}

/// Same rule as webmatch.hosts_match: equal, or one is a subdomain of the other.
bool hostsMatch(String a, String b) {
  final x = _host(a), y = _host(b);
  if (x.isEmpty || y.isEmpty) return false;
  return x == y || x.endsWith('.$y') || y.endsWith('.$x');
}

bool entryMatches(Entry e, AutofillRequest r) =>
    e.kind == 'login' &&
    (r.web ? hostsMatch(r.target, e.website) : e.app == r.target);

// ---- captured logins ---------------------------------------------------------
Future<Map<String, dynamic>> autofillStatus() async {
  try {
    return (await _setup.invokeMapMethod<String, dynamic>('status')) ?? {};
  } on MissingPluginException {
    return {};
  }
}

Future<void> openAutofillSettings() => _setup.invokeMethod('open');

/// Adds logins captured while the vault was locked. Returns how many changed.
Future<int> importCaptures(Vault v) async {
  List<dynamic> items;
  try {
    items = await _setup.invokeListMethod<dynamic>('takeInbox') ?? [];
  } on MissingPluginException {
    return 0;
  }
  var changed = 0;
  for (final raw in items) {
    final c = jsonDecode('$raw') as Map<String, dynamic>;
    final web = c['web'] == true;
    final target = '${c['target']}';
    final login = '${c['username'] ?? ''}'.trim();
    final pw = '${c['password'] ?? ''}';
    if (pw.isEmpty) continue;
    final req = AutofillRequest(target, '${c['label']}', web, true);
    Entry? existing;
    for (final e in v.activeEntries()) {
      if (entryMatches(e, req) &&
          (login.isEmpty || e.username == login || e.email == login)) {
        existing = e;
        break;
      }
    }
    if (existing != null) {
      if (existing.password == pw) continue;
      existing.password = pw;
      v.update(existing);
    } else {
      final isEmail = login.contains('@');
      v.add(
        Entry(
          title: '${c['label']}'.isEmpty ? target : '${c['label']}',
          website: web ? target : '',
          app: web ? '' : target,
          username: isEmail ? '' : login,
          email: isEmail ? login : '',
          password: pw,
        ),
      );
    }
    changed++;
  }
  return changed;
}

// ---- picking an account to fill ---------------------------------------------
class AutofillPickPage extends StatefulWidget {
  final Vault vault;
  const AutofillPickPage({super.key, required this.vault});
  @override
  State<AutofillPickPage> createState() => _AutofillPickPageState();
}

class _AutofillPickPageState extends State<AutofillPickPage> {
  final _q = TextEditingController();

  Future<void> _pick(Entry e) async {
    await _fill.invokeMethod('fill', {
      'username': e.username.isNotEmpty ? e.username : e.email,
      'password': e.password,
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = autofillRequest!;
    final env = Envelope.of(context);
    final logins = widget.vault
        .search(_q.text)
        .where((e) => e.kind == 'login')
        .toList();
    final matches = logins.where((e) => entryMatches(e, r)).toList();
    final others = logins.where((e) => !entryMatches(e, r)).toList();
    Widget tile(Entry e) => ListTile(
      leading: Glyph(Icons.key_outlined),
      title: Text(e.displayName()),
      subtitle: Text(
        subtitleOf(e),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _pick(e),
    );
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _fill.invokeMethod('cancel');
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Fill ${r.label}')),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _fill.invokeMethod('cancel'),
          ),
        ),
        body: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _q,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: tr('Search your logins'),
                ),
              ),
            ),
            if (matches.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: Text(
                  tr('Saved for ${r.label}'),
                  style: TextStyle(
                    color: env.ink2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final e in matches) tile(e),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                matches.isEmpty
                    ? tr('Nothing saved for ${r.label} yet. Pick a login:')
                    : tr('Other logins'),
                style: TextStyle(color: env.ink2, fontWeight: FontWeight.w600),
              ),
            ),
            for (final e in others) tile(e),
            if (logins.isEmpty)
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(tr('No logins match that search.')),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small square icon tile, matching the main list.
class Glyph extends StatelessWidget {
  final IconData icon;
  const Glyph(this.icon, {super.key});
  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: e.sheet,
        border: Border.all(color: e.rule2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 17, color: e.ink2),
    );
  }
}

// ---- setting it up -------------------------------------------------------------
class AutofillSetupPage extends StatefulWidget {
  const AutofillSetupPage({super.key});
  @override
  State<AutofillSetupPage> createState() => _AutofillSetupPageState();
}

class _AutofillSetupPageState extends State<AutofillSetupPage>
    with WidgetsBindingObserver {
  Map<String, dynamic> _s = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _load(); // back from Android settings
  }

  Future<void> _load() async {
    final s = await autofillStatus();
    if (mounted) setState(() => _s = s);
  }

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    final on = _s['enabled'] == true;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Autofill in other apps'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Icon(
                on ? Icons.check_circle : Icons.radio_button_unchecked,
                color: on ? e.ok : e.ink3,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  on
                      ? tr('MyVault is your autofill service.')
                      : tr('MyVault is not your autofill service yet.'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            tr(
              'With this on, MyVault can fill and save logins in other apps and in Chrome:\n\n'
              '• Tap a login box, then "Fill with MyVault". MyVault asks for your master '
              'password, then you pick the account.\n'
              '• When you sign in or sign up somewhere new, Android asks "Save to MyVault?". '
              'Saved logins are kept encrypted on this phone and added to your vault the next '
              'time you unlock.',
            ),
            style: TextStyle(color: e.ink2, height: 1.45),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _s['supported'] == false ? null : openAutofillSettings,
            icon: const Icon(Icons.settings_outlined),
            label: Text(tr(on ? 'Change autofill service' : 'Turn on')),
          ),
          const SizedBox(height: 10),
          Text(
            tr(
              'In Chrome, also open Chrome › Settings › Autofill services and choose '
              '"Autofill using another service".',
            ),
            style: TextStyle(color: e.ink3, fontSize: 12.5),
          ),
          if (_s['supported'] == false)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                tr(
                  "This phone's Android version doesn't support autofill services.",
                ),
                style: TextStyle(color: e.red),
              ),
            ),
        ],
      ),
    );
  }
}
