import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart' show InvalidCipherTextException;

import 'crypto.dart';
import 'docs.dart' as docs;
import 'documents_ui.dart';
import 'generator.dart';
import 'kinds.dart';
import 'l10n.dart';
import 'l10n_ar.dart' show arabicMonths;
import 'paper.dart' as paper;
import 'autofill.dart';
import 'sync.dart' as qrsync;
import 'theme.dart';
import 'update.dart' as upd;
import 'update_ui.dart';
import 'vault.dart';
import 'version.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Session.loadLockPrefs();
  try {
    final pick = (await upd.loadPrefs())['language'];
    if (languageChoices.contains(pick)) language.value = pick as String;
  } catch (_) {
    // first run: follow the phone's language
  }
  await loadAutofillRequest();
  runApp(const MyVaultApp());
}

const _clipboardClear = Duration(seconds: 30);

/// Lets the screenshot capture (test/capture_test.dart) point at a temp vault.
@visibleForTesting
String? vaultPathOverride;

Future<String> vaultFilePath() async {
  if (vaultPathOverride != null) return vaultPathOverride!;
  final dir = await getApplicationDocumentsDirectory();
  return '${dir.path}/vault.dat';
}

final _nav = GlobalKey<NavigatorState>();

/// scrypt is slow on purpose; keep it off the UI thread. (Top-level so the
/// isolate closure captures only these arguments.)
Future<Vault> _openVault(String path, String pw, bool exists) =>
    Isolate.run(() => exists ? Vault.open(path, pw) : Vault.create(path, pw));

/// Holds the open vault and locks it when the app is backgrounded or idle.
class Session {
  static Vault? vault;
  static DateTime? _pausedAt;
  static Timer? _idle;

  /// Settings › Auto-lock (saved in the app's small prefs file).
  static int idleMinutes = 5;
  static int backgroundSeconds = 30;
  static const idleChoices = [1, 2, 5, 10, 15, 30, 60];
  static const backgroundChoices = [0, 30, 60, 300];

  static Future<void> loadLockPrefs() async {
    try {
      final p = await upd.loadPrefs();
      final i = p['lock_idle_min'], b = p['lock_bg_sec'];
      if (idleChoices.contains(i)) idleMinutes = i as int;
      if (backgroundChoices.contains(b)) backgroundSeconds = b as int;
    } catch (_) {
      // first run, or no storage yet: keep the defaults
    }
  }

  static Future<void> saveLockPrefs() async {
    final p = await upd.loadPrefs();
    p['lock_idle_min'] = idleMinutes;
    p['lock_bg_sec'] = backgroundSeconds;
    await upd.savePrefs(p);
    touch();
  }

  static void open(Vault v) {
    vault = v;
    v.onSave = () => pushReminders(v);
    pushReminders(v);
    try {
      docs.cleanup(v); // files nothing refers to any more
    } catch (_) {}
    touch();
  }

  static void touch() {
    _idle?.cancel();
    if (vault != null) {
      _idle = Timer(
        Duration(minutes: idleMinutes),
        () => lock(
          tr(
            'Locked after $idleMinutes minute${idleMinutes == 1 ? '' : 's'} without use.',
          ),
        ),
      );
    }
  }

  static void lock([String msg = '']) {
    vault = null;
    _idle?.cancel();
    _Clip.wipe();
    _nav.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => UnlockPage(message: msg)),
      (_) => false,
    );
  }

  static void paused() => _pausedAt = DateTime.now();
  static void resumed() {
    final p = _pausedAt;
    _pausedAt = null;
    if (vault != null &&
        p != null &&
        DateTime.now().difference(p) >= Duration(seconds: backgroundSeconds)) {
      lock();
    }
  }
}

/// Clipboard copies marked "sensitive" (hidden from Android's clipboard preview
/// and keyboards' clipboard history), wiped after 30 s. See MainActivity.kt.
class _Clip {
  static const _ch = MethodChannel('myvault/clipboard');
  static String? _last;

  static Future<void> copy(String text) async {
    _last = text;
    try {
      await _ch.invokeMethod('copySensitive', text);
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: text));
    }
    Timer(_clipboardClear, () {
      if (_last == text) wipe();
    });
  }

  static Future<void> wipe() async {
    if (_last == null) return;
    _last = null;
    try {
      await _ch.invokeMethod('clear');
    } on MissingPluginException {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }
}

void _snack(BuildContext c, String msg) => ScaffoldMessenger.of(c)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(tr(msg))));

Future<void> _copy(BuildContext c, String value, String what) async {
  if (value.isEmpty) return _snack(c, tr('$what is empty.'));
  await _Clip.copy(value);
  if (c.mounted) {
    _snack(c, tr('$what copied. It clears from the clipboard in 30 s.'));
  }
}

class MyVaultApp extends StatefulWidget {
  const MyVaultApp({super.key});
  @override
  State<MyVaultApp> createState() => _MyVaultAppState();
}

class _MyVaultAppState extends State<MyVaultApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) Session.paused();
    if (s == AppLifecycleState.resumed) Session.resumed();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => Session.touch(),
    // A language change rebuilds the whole app in the new language (and
    // direction); an open vault stays open.
    child: ValueListenableBuilder<String>(
      valueListenable: language,
      builder: (_, pick, _) => MaterialApp(
        key: ValueKey(pick),
        title: 'MyVault',
        navigatorKey: _nav,
        theme: buildTheme(Envelope.light, Brightness.light),
        darkTheme: buildTheme(Envelope.dark, Brightness.dark),
        debugShowCheckedModeBanner: false,
        locale: Locale(isArabic ? 'ar' : 'en'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Session.vault == null ? const UnlockPage() : const HomePage(),
      ),
    ),
  );
}

// =====================================================================
//  Small shared pieces
// =====================================================================
class Glyph extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool inverted;
  const Glyph(this.icon, {super.key, this.size = 34, this.inverted = false});
  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: inverted ? Colors.transparent : e.sheet,
        border: Border.all(color: e.rule2),
        borderRadius: BorderRadius.circular(size > 36 ? 8 : 6),
      ),
      child: Icon(icon, size: size * .5, color: e.ink2),
    );
  }
}

class TintBox extends StatelessWidget {
  final double opacity;
  final bool crossed;
  const TintBox({super.key, this.opacity = .38, this.crossed = true});
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: TintPainter(
      Envelope.of(context).tint,
      opacity: opacity,
      crossed: crossed,
    ),
    size: Size.infinite,
  );
}

/// A concealed value: covered by the tint until revealed; reseals after 20 s.
class SecretValue extends StatefulWidget {
  final String value;
  final bool multi;
  const SecretValue(this.value, {super.key, this.multi = false});
  @override
  State<SecretValue> createState() => SecretValueState();
}

class SecretValueState extends State<SecretValue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wipe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  bool open = false;
  Timer? _reseal;

  void toggle() {
    setState(() => open = !open);
    _reseal?.cancel();
    if (open) {
      _wipe.forward(from: 0);
      _reseal = Timer(const Duration(seconds: 20), () {
        if (mounted && open) toggle();
      });
    } else {
      _wipe.value = 0;
    }
  }

  @override
  void dispose() {
    _reseal?.cancel();
    _wipe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    final text = Text(
      open ? widget.value : '',
      textDirection:
          TextDirection.ltr, // secrets read left to right, in Arabic too
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        color: e.ink,
        height: 1.5,
      ),
    );
    return Semantics(
      label: open ? null : tr('Hidden value'),
      // Concealed = dashed outline under the tint; revealed = solid ink outline.
      child: CustomPaint(
        foregroundPainter: _Outline(
          open ? e.ink3 : e.ink3.withValues(alpha: .7),
          dashed: !open,
        ),
        child: Container(
          constraints: BoxConstraints(
            minWidth: open ? 0 : 150,
            minHeight: widget.multi && !open ? 60 : 28,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Stack(
            children: [
              text,
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _wipe,
                  builder: (_, _) => ClipRect(
                    clipper: _WipeClip(
                      open ? Curves.easeOutCubic.transform(_wipe.value) : 0,
                    ),
                    child: CustomPaint(
                      painter: TintPainter(e.tint, opacity: .65),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Outline extends CustomPainter {
  final Color color;
  final bool dashed;
  _Outline(this.color, {required this.dashed});
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final r = RRect.fromRectAndRadius(
      Offset.zero & s,
      const Radius.circular(4),
    ).deflate(.5);
    if (!dashed) return canvas.drawRRect(r, p);
    for (final m in (Path()..addRRect(r)).computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 6) {
        canvas.drawPath(m.extractPath(d, d + 3), p);
      }
    }
  }

  @override
  bool shouldRepaint(_Outline o) => o.color != color || o.dashed != dashed;
}

class _WipeClip extends CustomClipper<Rect> {
  final double t;
  _WipeClip(this.t);
  @override
  Rect getClip(Size s) => Rect.fromLTRB(s.width * t, 0, s.width, s.height);
  @override
  bool shouldReclip(_WipeClip o) => o.t != t;
}

class StrengthBar extends StatelessWidget {
  final String password;
  const StrengthBar(this.password, {super.key});
  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    final s = strengthLabel(password);
    final lv =
        const {'Weak': 1, 'Okay': 2, 'Strong': 3, 'Very strong': 4}[s] ?? 0;
    final col = [e.rule, e.red, const Color(0xFFC08A2E), e.tint, e.ok][lv];
    return Row(
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            width: 30,
            height: 4,
            margin: const EdgeInsetsDirectional.only(end: 3),
            decoration: BoxDecoration(
              color: i < lv ? col : e.rule,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        const SizedBox(width: 8),
        Text(
          s.isEmpty ? '' : tr('Strength: $s'),
          style: TextStyle(fontSize: 12.5, color: e.ink2),
        ),
      ],
    );
  }
}

/// Digits in envelope blue: easier to read a password back character by character.
Widget pwText(BuildContext c, String pw, {double size = 18}) {
  final e = Envelope.of(c);
  return Text.rich(
    TextSpan(
      children: [
        for (final ch in pw.split(''))
          TextSpan(
            text: ch,
            style: TextStyle(
              color: RegExp(r'[0-9]').hasMatch(ch) ? e.tint : e.ink,
            ),
          ),
      ],
    ),
    style: TextStyle(
      fontFamily: 'monospace',
      fontSize: size,
      letterSpacing: .4,
    ),
    textDirection:
        TextDirection.ltr, // a password reads left to right, in Arabic too
  );
}

// =====================================================================
//  Unlock / create
// =====================================================================
class UnlockPage extends StatefulWidget {
  final String message;
  const UnlockPage({super.key, this.message = ''});
  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final _pw1 = TextEditingController();
  final _pw2 = TextEditingController();
  bool _exists = false, _loading = true, _busy = false;
  late String _error = widget.message;
  String _path = '';

  @override
  void initState() {
    super.initState();
    () async {
      _path = await vaultFilePath();
      _exists = File(_path).existsSync();
      if (mounted) setState(() => _loading = false);
    }();
  }

  Future<void> _submit() async {
    final pw = _pw1.text;
    if (pw.isEmpty) {
      return setState(() => _error = tr('Enter your master password.'));
    }
    if (!_exists) {
      if (pw.length < 8) {
        return setState(
          () => _error = tr(
            'Use at least 8 characters. A short sentence works well.',
          ),
        );
      }
      if (pw != _pw2.text) {
        return setState(() => _error = tr("The two passwords don't match."));
      }
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final vault = await _openVault(_path, pw, _exists);
      Session.open(vault);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => autofillRequest != null
              ? AutofillPickPage(vault: vault)
              : const HomePage(),
        ),
      );
    } on WrongPasswordException {
      setState(() {
        _busy = false;
        _error = tr("That isn't the master password. Try again.");
      });
    } on VaultFormatException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    if (_loading) return Scaffold(backgroundColor: e.paper);
    return Scaffold(
      backgroundColor: e.paper,
      body: Stack(
        children: [
          const Positioned.fill(child: TintBox(opacity: .32)),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                decoration: BoxDecoration(
                  color: e.sheet.withValues(alpha: .93),
                  border: Border.all(color: e.rule2),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const EnvelopeMark(width: 30),
                        const SizedBox(width: 10),
                        Text(
                          tr('MyVault'),
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -.5,
                            color: e.ink,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _exists
                          ? tr(
                              'Your vault is sealed. Enter your master password to open it.',
                            )
                          : tr(
                              "Choose the one password that opens your vault. It's the only one you'll need to remember.",
                            ),
                      style: TextStyle(color: e.ink2, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _pw1,
                      obscureText: true,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: tr(
                          _exists
                              ? 'Master password'
                              : 'Choose a master password',
                        ),
                      ),
                      onChanged: _exists ? null : (_) => setState(() {}),
                      onSubmitted: (_) => _exists ? _submit() : null,
                    ),
                    if (!_exists) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _pw2,
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: tr('Type it again'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      StrengthBar(_pw1.text),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: e.rule2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tr(
                            "There's no reset. If this password is forgotten, nobody can open the vault, not even you. "
                            'Write it down and keep it somewhere safe.',
                          ),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: e.ink2,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(tr(_error), style: TextStyle(color: e.red)),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        _busy
                            ? (_exists ? tr('Opening…') : tr('Creating…'))
                            : (_exists ? tr('Unlock') : tr('Create my vault')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
//  Home: search, filter, list
// =====================================================================
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _search = TextEditingController();
  String _filter = 'all';
  Vault get v => Session.vault!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) startupUpdateFlow(context);
      _importCaptures();
    });
  }

  Future<void> _importCaptures() async {
    final n = await importCaptures(v);
    if (n == 0 || !mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr('Saved $n login${n == 1 ? '' : 's'} from other apps.'),
        ),
      ),
    );
  }

  List<Entry> get _items => v
      .search(_search.text)
      .where((e) => _filter == 'all' || e.kind == _filter)
      .toList();

  Future<void> _open(Entry e) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => EntryViewPage(entry: e)));
    if (mounted) setState(() {});
  }

  Future<void> _new() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('What are you adding?'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (final k in kindDefs.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Glyph(k.value.icon, size: 40),
                  title: Text(
                    tr(k.value.label),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(tr(k.value.desc)),
                  onTap: () => Navigator.pop(c, k.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (kind == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EntryEditPage(entry: Entry(kind: kind), isNew: true),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _sync() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SyncPage()));
    if (mounted) setState(() {});
  }

  void _menu(String id) async {
    switch (id) {
      case 'gen':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const GeneratorPage()));
      case 'paper':
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const RestorePaperPage()));
        if (mounted) setState(() {});
      case 'master':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ChangeMasterPage()));
      case 'autolock':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AutoLockPage()));
      case 'autofill':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AutofillSetupPage()));
      case 'updates':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const UpdatesPage()));
      case 'language':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const LanguagePage()));
      case 'documents':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DocumentsSettingsPage()),
        );
      case 'about':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AboutPage()));
      case 'lock':
        Session.lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    final items = _items;
    final counts = {
      for (final k in kindDefs.keys)
        k: v.activeEntries().where((x) => x.kind == k).length,
    };
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            EnvelopeMark(width: 24),
            SizedBox(width: 10),
            Text(tr('MyVault')),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _sync,
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: tr('Sync with PC'),
          ),
          IconButton(
            onPressed: Session.lock,
            icon: const Icon(Icons.lock_outline),
            tooltip: tr('Lock'),
          ),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'gen',
                child: Text(tr('Password generator')),
              ),
              PopupMenuItem(
                value: 'paper',
                child: Text(tr('Restore from paper')),
              ),
              PopupMenuItem(
                value: 'master',
                child: Text(tr('Change master password')),
              ),
              PopupMenuItem(value: 'autolock', child: Text(tr('Auto-lock'))),
              PopupMenuItem(
                value: 'autofill',
                child: Text(tr('Autofill in other apps')),
              ),
              PopupMenuItem(value: 'updates', child: Text(tr('Updates'))),
              PopupMenuItem(value: 'documents', child: Text(tr('Documents'))),
              PopupMenuItem(value: 'language', child: Text(tr('Language'))),
              PopupMenuItem(value: 'about', child: Text(tr('About & privacy'))),
              PopupMenuItem(value: 'lock', child: Text(tr('Lock now'))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: e.panel,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: tr('Search'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final f in [
                        ('all', tr('All')),
                        for (final k in kindDefs.entries)
                          (k.key, tr(k.value.plural)),
                      ])
                        if (f.$1 == 'all' || counts[f.$1]! > 0)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: ChoiceChip(
                              label: Text(
                                '${f.$2}  ${f.$1 == 'all' ? v.activeEntries().length : counts[f.$1]}',
                              ),
                              selected: _filter == f.$1,
                              onSelected: (_) => setState(() => _filter = f.$1),
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          if (_search.text.isEmpty && _filter == 'all')
            ExpiringSoon(docs: v.activeEntries(), onOpen: _open),
          Expanded(
            child: items.isEmpty
                ? _Empty(
                    empty: v.activeEntries().isEmpty,
                    query: _search.text,
                    onAdd: _new,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(indent: 64),
                    itemBuilder: (_, i) {
                      final x = items[i];
                      final sub = subtitleOf(x);
                      return ListTile(
                        leading: Glyph(kindOf(x).icon),
                        title: Text(
                          x.displayName(),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: x.kind == 'document'
                            ? (docs.parseDay(x.fields['expires']) == null
                                  ? null
                                  : expiryText(context, x.fields['expires']!))
                            : sub.isEmpty
                            ? null
                            : Text(
                                sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: e.ink3),
                              ),
                        onTap: () => _open(x),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: Text(tr('New')),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final bool empty;
  final String query;
  final VoidCallback onAdd;
  const _Empty({required this.empty, required this.query, required this.onAdd});
  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    return Stack(
      children: [
        const Positioned.fill(
          child: Opacity(opacity: .5, child: TintBox(opacity: .25)),
        ),
        Center(
          child: Container(
            margin: const EdgeInsets.all(28),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: e.sheet,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: e.rule),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  empty
                      ? tr('Your vault is empty')
                      : tr('Nothing matches “$query”'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  empty
                      ? tr(
                          'Start with the account you use most. Logins, API keys, SSH keys and notes are all encrypted on this phone.',
                        )
                      : tr('Try a shorter word, or check the type filter.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: e.ink2, height: 1.4),
                ),
                if (empty) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                    label: Text(tr('Add your first entry')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =====================================================================
//  View an entry
// =====================================================================
class EntryViewPage extends StatefulWidget {
  final Entry entry;
  const EntryViewPage({super.key, required this.entry});
  @override
  State<EntryViewPage> createState() => _EntryViewPageState();
}

class _EntryViewPageState extends State<EntryViewPage> {
  Entry get x => widget.entry;

  Future<void> _edit() async {
    final deleted = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => EntryEditPage(entry: x)));
    if (!mounted) return;
    if (deleted == true) return Navigator.of(context).pop();
    setState(() {});
  }

  Widget _row(FieldDef f, String value) {
    final e = Envelope.of(context);
    final key = GlobalKey<SecretValueState>();
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: e.rule)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(f.label),
                  style: TextStyle(fontSize: 12.5, color: e.ink2),
                ),
                const SizedBox(height: 4),
                f.secret
                    ? SecretValue(value, key: key, multi: f.multi)
                    : SelectableText(
                        value,
                        textDirection: f.mono ? TextDirection.ltr : null,
                        style: TextStyle(
                          fontSize: 15,
                          fontFamily: f.mono || (f.multi && f.key != 'notes')
                              ? 'monospace'
                              : null,
                        ),
                      ),
              ],
            ),
          ),
          if (f.secret) _RevealButton(target: key),
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 20),
            tooltip: tr('Copy ${f.label.toLowerCase()}'),
            onPressed: () => _copy(context, value, f.label),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    final k = kindOf(x);
    final rows = [...k.fields, ...k.more]
        .map((f) => (f, f.read(x)))
        .where((r) => r.$2.isNotEmpty)
        .map((r) {
          final f = r.$1;
          if (f.options != null) return (f, tr(docs.typeLabel(r.$2)));
          return (f, f.date ? fmtDay(r.$2) : r.$2);
        })
        .toList();
    final custom = x.custom.entries.toList();
    final sub = [
      tr(k.label),
      x.kind == 'login' ? x.website : (x.fields['service'] ?? ''),
    ].where((s) => s.isNotEmpty).join(' · ');
    String date(double t) {
      final d = DateTime.fromMillisecondsSinceEpoch((t * 1000).round());
      const m = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${d.day} ${(isArabic ? arabicMonths : m)[d.month - 1]} ${d.year}';
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(tr('Edit')),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          Row(
            children: [
              Glyph(k.icon, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      x.displayName(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.3,
                      ),
                    ),
                    Text(sub, style: TextStyle(color: e.ink3, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(color: e.rule),
          for (final r in rows) _row(r.$1, r.$2),
          if (x.kind != 'note' && x.notes.isNotEmpty)
            _row(const FieldDef('notes', 'Notes', multi: true), x.notes),
          if (x.kind == 'document')
            DocumentSection(vault: Session.vault!, entry: x),
          if (custom.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(
              tr('Extra fields'),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: e.ink2,
                fontSize: 13,
              ),
            ),
            Divider(color: e.rule),
            for (final c in custom) _row(FieldDef(c.key, c.key), c.value),
          ],
          if (rows.isEmpty && x.notes.isEmpty && custom.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                tr('Nothing stored here yet. Tap Edit to add details.'),
                style: TextStyle(color: e.ink2),
              ),
            ),
          const SizedBox(height: 20),
          Text(
            tr(
              'Last changed ${date(x.updatedAt)} · Created ${date(x.createdAt)}',
            ),
            style: TextStyle(color: e.ink3, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _RevealButton extends StatefulWidget {
  final GlobalKey<SecretValueState> target;
  const _RevealButton({required this.target});
  @override
  State<_RevealButton> createState() => _RevealButtonState();
}

class _RevealButtonState extends State<_RevealButton> {
  @override
  Widget build(BuildContext context) {
    final open = widget.target.currentState?.open ?? false;
    return IconButton(
      icon: Icon(
        open ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 20,
      ),
      tooltip: tr(open ? 'Hide' : 'Show'),
      onPressed: () {
        widget.target.currentState?.toggle();
        setState(() {});
        Timer(const Duration(seconds: 21), () {
          if (mounted) setState(() {});
        });
      },
    );
  }
}

// =====================================================================
//  New / edit
// =====================================================================
class EntryEditPage extends StatefulWidget {
  final Entry entry;
  final bool isNew;
  const EntryEditPage({super.key, required this.entry, this.isNew = false});
  @override
  State<EntryEditPage> createState() => _EntryEditPageState();
}

class _EntryEditPageState extends State<EntryEditPage> {
  late final Entry _e = widget.entry;
  late final KindDef _k = kindOf(_e);
  late final _title = TextEditingController(text: _e.title);
  late final _notes = TextEditingController(text: _e.notes);
  late final Map<String, TextEditingController> _c = {
    for (final f in [..._k.fields, ..._k.more])
      f.key: TextEditingController(text: f.read(_e)),
  };
  final _shown = <String>{};
  // A saved password is never one stray tap from being replaced: it's
  // read-only, and "Change password" asks first (see _changePassword).
  late final String _savedPw = _e.password;
  late bool _pwLocked = _savedPw.isNotEmpty;
  final _pwFocus = FocusNode();
  late final List<List<TextEditingController>> _custom = [
    for (final c in _e.custom.entries)
      [
        TextEditingController(text: c.key),
        TextEditingController(text: c.value),
      ],
  ];

  final _doc = DocumentDraft();

  void _save() {
    _e.title = _title.text.trim();
    for (final f in [..._k.fields, ..._k.more]) {
      f.write(_e, _c[f.key]!.text);
    }
    if (_e.kind == 'document') {
      _doc.writeTo(_e);
      // The first reminder: Android needs the person's OK to show notifications.
      if (docs.remindDays(_e).isNotEmpty) askNotifications();
    }
    if (_e.kind != 'note') _e.notes = _notes.text;
    _e.custom = {
      for (final r in _custom)
        if (r[0].text.trim().isNotEmpty) r[0].text.trim(): r[1].text,
    };
    if (_e.displayName() == '(untitled)') {
      return _snack(context, tr('Give it a name first.'));
    }
    final v = Session.vault!;
    widget.isNew ? v.add(_e) : v.update(_e);
    Navigator.of(context).pop(false);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Delete for good?')),
        content: Text(
          tr(
            '“${_e.displayName()}” will be removed from this phone, and from your PC at the next sync.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Keep it')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              tr('Delete'),
              style: TextStyle(color: Envelope.of(c).red),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Session.vault!.deleteById(_e.id);
    Navigator.of(context).pop(true);
  }

  Future<void> _generate() async {
    final policy = PasswordPolicy.fromJson(_e.passwordPolicy);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => GeneratorSheet(policy: policy, pick: true),
    );
    if (result != null) {
      setState(() {
        _c['password']!.text = result;
        _shown.add('password');
        _e.passwordPolicy = policy.toJson();
      });
    }
  }

  Future<void> _changePassword() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Replace this password?')),
        content: Text(
          _savedPw.isNotEmpty
              ? tr(
                  'Once you save, the old one is gone for good. Change it on the website or app as well, or you could lock yourself out.',
                )
              : tr('The password in the box will be replaced.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(tr('Keep it')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'type'),
            child: Text(tr('Type a new one')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'generate'),
            child: Text(tr('Generate one')),
          ),
        ],
      ),
    );
    if (choice == 'type') {
      setState(() {
        _pwLocked = false;
        _c['password']!.clear();
      });
      _pwFocus.requestFocus();
    } else if (choice == 'generate') {
      await _generate();
    }
  }

  Widget _field(FieldDef f) {
    final c = _c[f.key]!;
    if (f.options != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: DropdownButtonFormField<String>(
          initialValue: f.options!.any((o) => o.$1 == c.text) ? c.text : '',
          decoration: InputDecoration(labelText: tr(f.label)),
          items: [
            for (final o in f.options!)
              DropdownMenuItem(value: o.$1, child: Text(tr(o.$2))),
          ],
          onChanged: (v) => setState(() => c.text = v ?? ''),
        ),
      );
    }
    if (f.date) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: InkWell(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: docs.parseDay(c.text) ?? now,
              firstDate: DateTime(1950),
              lastDate: DateTime(now.year + 30),
            );
            if (picked != null) setState(() => c.text = docs.isoDay(picked));
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: tr(f.label),
              suffixIcon: c.text.isEmpty
                  ? const Icon(Icons.calendar_today_outlined, size: 20)
                  : IconButton(
                      tooltip: tr('Clear'),
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => setState(() => c.clear()),
                    ),
            ),
            isEmpty: c.text.isEmpty,
            child: Text(c.text.isEmpty ? '' : fmtDay(c.text)),
          ),
        ),
      );
    }
    final filled = f.gen && c.text.isNotEmpty;
    final hidden = f.secret && !_shown.contains(f.key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: c,
            focusNode: f.gen ? _pwFocus : null,
            textDirection: f.secret || f.mono ? TextDirection.ltr : null,
            readOnly: f.gen && _pwLocked,
            obscureText: hidden && !f.multi,
            keyboardType: f.multi ? TextInputType.multiline : f.type,
            maxLines: f.multi ? (hidden ? 1 : 6) : 1,
            minLines: 1,
            autocorrect: false,
            enableSuggestions: !f.secret,
            onChanged: f.gen ? (_) => setState(() {}) : null,
            style: TextStyle(
              fontFamily: f.mono || f.secret ? 'monospace' : null,
            ),
            decoration: InputDecoration(
              labelText: tr(f.label),
              suffixIcon: !f.secret
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            hidden
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          tooltip: tr(hidden ? 'Show' : 'Hide'),
                          onPressed: () => setState(
                            () => hidden
                                ? _shown.add(f.key)
                                : _shown.remove(f.key),
                          ),
                        ),
                        // Direct paste: doesn't depend on Android's paste bubble.
                        if (!filled)
                          IconButton(
                            icon: const Icon(Icons.content_paste, size: 20),
                            tooltip: tr('Paste'),
                            onPressed: () async {
                              final clip = await Clipboard.getData(
                                'text/plain',
                              );
                              final text = clip?.text ?? '';
                              if (!mounted) return;
                              if (text.isEmpty) {
                                return _snack(
                                  context,
                                  tr(
                                    'The clipboard is empty. Copy the text again, then tap Paste.',
                                  ),
                                );
                              }
                              setState(() {
                                c.text = f.multi ? text : text.trim();
                                if (f.gen) _shown.add(f.key);
                              });
                            },
                          ),
                        if (f.gen && !filled)
                          IconButton(
                            icon: const Icon(Icons.casino_outlined, size: 20),
                            tooltip: tr('Generate'),
                            onPressed: _generate,
                          ),
                        if (filled)
                          IconButton(
                            icon: const Icon(Icons.autorenew, size: 20),
                            tooltip: tr('Change password'),
                            onPressed: _changePassword,
                          ),
                      ],
                    ),
            ),
          ),
          if (f.gen)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: StrengthBar(c.text),
            ),
          if (f.gen && _savedPw.isNotEmpty && c.text != _savedPw)
            TextButton.icon(
              onPressed: () => setState(() {
                c.text = _savedPw;
                _pwLocked = true;
              }),
              icon: const Icon(Icons.undo, size: 18),
              label: Text(tr('Keep the old password')),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr(widget.isNew ? 'New ${_k.label.toLowerCase()}' : 'Edit'),
        ),
        actions: [
          if (!widget.isNew)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              tooltip: tr('Delete'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        children: [
          TextField(
            controller: _title,
            autofocus: widget.isNew,
            decoration: InputDecoration(labelText: tr('Name')),
          ),
          const SizedBox(height: 14),
          for (final f in _k.fields) _field(f),
          if (_e.kind == 'document')
            DocumentEditor(
              vault: Session.vault!,
              entry: _e,
              isNew: widget.isNew,
              draft: _doc,
              isEmpty: (k) => (_c[k]?.text ?? '').isEmpty,
              fill: (k, v) {
                final c = _c[k];
                if (c == null || c.text.isNotEmpty) return false;
                setState(() => c.text = v);
                return true;
              },
            ),
          if (_k.more.isNotEmpty)
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: _k.more.any((f) => f.read(_e).isNotEmpty),
                title: Text(
                  tr('Profile details'),
                  style: TextStyle(
                    color: e.ink2,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  tr('App, phone, region, age, gender'),
                  style: TextStyle(color: e.ink3, fontSize: 12),
                ),
                children: [for (final f in _k.more) _field(f)],
              ),
            ),
          if (_e.kind != 'note') ...[
            const SizedBox(height: 4),
            TextField(
              controller: _notes,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(labelText: tr('Notes')),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                tr('Extra fields'),
                style: TextStyle(color: e.ink2, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr('Add field')),
                onPressed: () => setState(
                  () => _custom.add([
                    TextEditingController(),
                    TextEditingController(),
                  ]),
                ),
              ),
            ],
          ),
          for (int i = 0; i < _custom.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _custom[i][0],
                      decoration: InputDecoration(hintText: tr('Label')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _custom[i][1],
                      decoration: InputDecoration(hintText: tr('Value')),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: tr('Remove field'),
                    onPressed: () => setState(() => _custom.removeAt(i)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(tr('Save')),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
//  Generator
// =====================================================================
class GeneratorBody extends StatefulWidget {
  final PasswordPolicy policy;
  final void Function(String)? onUse;
  const GeneratorBody({super.key, required this.policy, this.onUse});
  @override
  State<GeneratorBody> createState() => _GeneratorBodyState();
}

class _GeneratorBodyState extends State<GeneratorBody> {
  late final PasswordPolicy _p = widget.policy;
  String _pw = '';

  @override
  void initState() {
    super.initState();
    if (_p.length < 6) _p.length = 20;
    _regen();
  }

  void _regen() {
    try {
      _pw = generatePassword(_p);
    } catch (_) {
      _pw = '';
    }
    setState(() {});
  }

  Widget _sw(String label, String sub, bool value, void Function(bool) set) =>
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(tr(label)),
        subtitle: Text(tr(sub)),
        value: value,
        onChanged: (v) {
          set(v);
          _regen();
        },
      );

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 6, 12),
          decoration: BoxDecoration(
            color: e.paper,
            border: Border.all(color: e.rule2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: _pw.isEmpty
                    ? Text(
                        tr('Turn on at least one kind of character.'),
                        style: TextStyle(color: e.ink2),
                      )
                    : pwText(context, _pw, size: 19),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: tr('New password'),
                onPressed: _regen,
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: tr('Copy'),
                onPressed: () => _copy(context, _pw, 'Password'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        StrengthBar(_pw),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(tr('Length')),
            Expanded(
              child: Slider(
                min: 6,
                max: 128,
                value: _p.length.clamp(6, 128).toDouble(),
                label: '${_p.length}',
                onChanged: (v) {
                  _p.length = v.round();
                  _regen();
                },
              ),
            ),
            SizedBox(
              width: 34,
              child: Text(
                '${_p.length}',
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        _sw(
          tr('Uppercase letters'),
          'A–Z',
          _p.useUpper,
          (v) => _p.useUpper = v,
        ),
        _sw(
          tr('Lowercase letters'),
          'a–z',
          _p.useLower,
          (v) => _p.useLower = v,
        ),
        _sw(tr('Numbers'), '0–9', _p.useDigits, (v) => _p.useDigits = v),
        _sw(
          tr('Symbols'),
          '! @ # \$ …',
          _p.useSymbols,
          (v) => _p.useSymbols = v,
        ),
        _sw(
          tr('Avoid look-alikes'),
          tr('No l, 1, O, 0, I'),
          _p.avoidAmbiguous,
          (v) => _p.avoidAmbiguous = v,
        ),
        if (widget.onUse != null) ...[
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _pw.isEmpty ? null : () => widget.onUse!(_pw),
            child: Text(tr('Use this password')),
          ),
        ],
      ],
    );
  }
}

class GeneratorSheet extends StatelessWidget {
  final PasswordPolicy policy;
  final bool pick;
  const GeneratorSheet({super.key, required this.policy, this.pick = false});
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GeneratorBody(
        policy: policy,
        onUse: pick ? (pw) => Navigator.pop(context, pw) : null,
      ),
    ),
  );
}

class GeneratorPage extends StatelessWidget {
  const GeneratorPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Password generator'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          tr(
            "Random, from this phone's secure random source. Nothing is saved unless you copy it.",
          ),
          style: TextStyle(color: Envelope.of(context).ink2),
        ),
        const SizedBox(height: 14),
        GeneratorBody(policy: PasswordPolicy(length: 20)),
      ],
    ),
  );
}

// =====================================================================
//  QR scanning (sync code, paper backup)
// =====================================================================
class ScannerView extends StatefulWidget {
  /// Return true to stop scanning.
  final bool Function(String raw) onCode;
  final String hint;
  final Widget? footer;

  /// When set, codes it rejects show [wrongCode] so you can tell "the camera
  /// read something else" apart from "nothing is being read".
  final bool Function(String raw)? recognizes;
  final String wrongCode;
  const ScannerView({
    super.key,
    required this.onCode,
    required this.hint,
    this.footer,
    this.recognizes,
    this.wrongCode = '',
  });
  @override
  State<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<ScannerView> {
  final _ctrl = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  String _status = tr('Looking for a code…');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _ctrl,
          onDetect: (cap) {
            if (_done) return;
            for (final b in cap.barcodes) {
              final raw = b.rawValue;
              if (raw == null) continue;
              if (widget.recognizes != null && !widget.recognizes!(raw)) {
                if (_status != widget.wrongCode) {
                  setState(() => _status = widget.wrongCode);
                }
                continue;
              }
              if (widget.onCode(raw)) {
                _done = true;
                _ctrl.stop();
                break;
              }
            }
          },
          errorBuilder: (_, err) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                tr(
                  "MyVault can't use the camera (${err.errorCode.name}). Allow camera access for MyVault in "
                  'Android settings › Apps › MyVault › Permissions, then try again.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: e.sheet,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: e.ink),
                ),
                if (widget.recognizes != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: e.ink2, fontSize: 13),
                  ),
                ],
                if (widget.footer != null) ...[
                  const SizedBox(height: 10),
                  widget.footer!,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class SyncPage extends StatefulWidget {
  const SyncPage({super.key});
  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  String _state = 'intro'; // intro | scan | busy | done | error
  String _msg = '';

  Future<void> _run(String raw) async {
    setState(() => _state = 'busy');
    final r = await qrsync.syncWithCode(raw, Session.vault!);
    if (!mounted) return;
    setState(() {
      _state = r.ok ? 'done' : 'error';
      _msg = r.ok
          ? tr(
              'Synced. ${r.changed} ${r.changed == 1 ? 'entry' : 'entries'} updated on this phone. Your PC has the rest.${_versionNote(r)}${_filesNote(r)}',
            )
          : r.error;
    });
    final got = r.received;
    if (got != null && mounted) {
      await offerInstall(
        context,
        got,
        from: tr(
          'Your PC has MyVault ${got.version} and passed the update to this phone.',
        ),
      );
    }
  }

  String _filesNote(qrsync.SyncResult r) => [
    if (r.filesReceived > 0)
      tr(' Document files received: ${r.filesReceived}.'),
    if (r.filesError.isNotEmpty)
      tr(" Document files couldn't be synced: ${r.filesError}"),
  ].join();

  String _versionNote(qrsync.SyncResult r) {
    final pc = r.peerVersion;
    if (pc.isEmpty) {
      return tr(
        ' Your PC runs an older MyVault (before 0.5). Update it with the new installer; '
        'after that, updates pass between your devices when you sync.',
      );
    }
    if (r.received != null) return '';
    if (r.sent.isNotEmpty) {
      return tr(
        ' Your PC had MyVault $pc, so this phone passed it the ${r.sent} update. Install it from the card in the PC app.',
      );
    }
    if (isNewerVersion(pc, appVersion)) {
      return tr(
        ' Your PC has MyVault $pc (this phone has $appVersion).'
        '${r.updateError.isEmpty ? ' Update this phone from Updates in the menu.' : ' The update couldn\'t be passed over: ${r.updateError}'}',
      );
    }
    if (isNewerVersion(appVersion, pc)) {
      return tr(
        ' Your PC runs MyVault $pc (this phone has $appVersion). Update the PC when you can.',
      );
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    if (_state == 'scan') {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Scan the code on your PC'))),
        body: ScannerView(
          hint: tr(
            'On your PC, open MyVault → Sync with phone → Show sync code. '
            'Hold the phone 15–30 cm from the screen.',
          ),
          recognizes: (raw) => raw.startsWith('myvault://sync'),
          wrongCode: tr(
            "That QR code isn't a MyVault sync code. Point at the code in MyVault's Sync with phone screen.",
          ),
          onCode: (raw) {
            _run(raw);
            return true;
          },
        ),
      );
    }
    Widget fact(IconData i, String b, String t) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(i, size: 18, color: e.tint),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: b,
                    style: TextStyle(fontWeight: FontWeight.w600, color: e.ink),
                  ),
                  TextSpan(
                    text: t,
                    style: TextStyle(color: e.ink2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(tr('Sync with PC'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            tr(
              'Your phone and PC swap changes directly over your WiFi. No cloud is involved.',
            ),
            style: TextStyle(color: e.ink2, height: 1.4),
          ),
          const SizedBox(height: 16),
          Text(
            tr(
              '1. On the PC, open MyVault and choose Sync with phone.\n2. Choose Show sync code.\n3. Tap Scan below and point the camera at it.',
            ),
            style: TextStyle(height: 1.6, color: e.ink),
          ),
          const SizedBox(height: 18),
          if (_state == 'busy') ...[
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 10),
            Text(tr('Syncing with your PC…')),
          ],
          if (_state == 'done' || _state == 'error')
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: _state == 'done'
                    ? e.tintWash
                    : e.red.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(tr(_msg)),
            ),
          if (_state != 'busy')
            FilledButton.icon(
              onPressed: () => setState(() => _state = 'scan'),
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(
                tr(_state == 'intro' ? 'Scan sync code' : 'Scan again'),
              ),
            ),
          const SizedBox(height: 24),
          fact(
            Icons.verified_user_outlined,
            tr('The code is the key. '),
            tr(
              'It holds a one-time random key that only travels through the camera, so nobody else on the WiFi can read the sync.',
            ),
          ),
          fact(
            Icons.wifi,
            tr('Same WiFi only. '),
            tr('The PC stops listening after one sync, or after 2 minutes.'),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
//  Restore from paper
// =====================================================================
class RestorePaperPage extends StatefulWidget {
  const RestorePaperPage({super.key});
  @override
  State<RestorePaperPage> createState() => _RestorePaperPageState();
}

class _RestorePaperPageState extends State<RestorePaperPage> {
  final _pw = TextEditingController();
  bool _scanning = false, _busy = false;
  String _msg = '';
  final _keys = <String, Uint8List>{};
  final _seen = <String>{};
  final _found = <String, Entry>{};

  Future<void> _take(String raw) async {
    final clean = raw.replaceAll(RegExp(r'\s'), '').toUpperCase();
    if (_seen.contains(clean)) return;
    final block = paper.PaperBlock.parse(clean);
    if (block == null) {
      return setState(
        () => _msg = tr("That code isn't from a MyVault backup."),
      );
    }
    _seen.add(clean);
    try {
      var key = _keys[block.saltKey];
      if (key == null) {
        setState(() {
          _busy = true;
          _msg = tr('Checking the backup password… (slow on purpose)');
        });
        key = await paper.deriveBackupKey(_pw.text, block.salt);
        _keys[block.saltKey] = key;
      }
      final entry = paper.decryptBlock(block, key);
      setState(() {
        _found[entry.id] = entry;
        _busy = false;
        _msg = tr('Read ${_found.length}. Keep scanning, or tap Done.');
      });
    } on InvalidCipherTextException {
      _seen.remove(clean);
      _keys.remove(block.saltKey);
      setState(() {
        _busy = false;
        _scanning = false;
        _msg = tr("That backup password doesn't open this sheet.");
      });
    } catch (_) {
      setState(() {
        _busy = false;
        _msg = tr("Couldn't read that code. Try holding the phone steadier.");
      });
    }
  }

  void _finish() {
    final n = _found.length;
    final changed = Session.vault!.restoreIn(_found.values.toList());
    _snack(
      context,
      changed == 0
          ? tr(
              'Read $n ${n == 1 ? 'entry' : 'entries'}. All were already in your vault.',
            )
          : tr(
              'Read $n ${n == 1 ? 'entry' : 'entries'}. $changed restored or updated.',
            ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    if (_scanning) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Scanning: ${_found.length} read'))),
        body: ScannerView(
          hint: tr(
            'Point the camera at each code on the backup sheet, one at a time.',
          ),
          onCode: (raw) {
            if (!_busy) _take(raw);
            return false;
          },
          footer: Column(
            children: [
              if (_msg.isNotEmpty)
                Text(
                  _msg,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: e.ink2, fontSize: 13),
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _found.isEmpty ? null : _finish,
                child: Text(tr('Done: restore ${_found.length}')),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr('Restore from paper'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            tr(
              'Bring back entries from a printed MyVault backup. Each code on the sheet is one encrypted entry; '
              'restored entries are merged into this vault, keeping the newer version of anything you already have.',
            ),
            style: TextStyle(color: e.ink2, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pw,
            obscureText: true,
            decoration: InputDecoration(labelText: tr('Backup password')),
          ),
          if (_msg.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(tr(_msg), style: TextStyle(color: e.red)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              if (_pw.text.isEmpty) {
                return setState(
                  () => _msg = tr('Enter the backup password first.'),
                );
              }
              setState(() {
                _scanning = true;
                _msg = '';
              });
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(tr('Start scanning')),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
//  Change master password
// =====================================================================
class ChangeMasterPage extends StatefulWidget {
  const ChangeMasterPage({super.key});
  @override
  State<ChangeMasterPage> createState() => _ChangeMasterPageState();
}

class _ChangeMasterPageState extends State<ChangeMasterPage> {
  final _cur = TextEditingController(),
      _n1 = TextEditingController(),
      _n2 = TextEditingController();
  String _err = '';

  void _go() {
    final v = Session.vault!;
    if (_cur.text != v.password) {
      return setState(() => _err = tr('The current master password is wrong.'));
    }
    if (_n1.text.length < 8) {
      return setState(() => _err = tr('Use at least 8 characters.'));
    }
    if (_n1.text != _n2.text) {
      return setState(() => _err = tr("The new passwords don't match."));
    }
    v.changePassword(_n1.text);
    _snack(context, tr('Master password changed.'));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Change master password'))),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        TextField(
          controller: _cur,
          obscureText: true,
          decoration: InputDecoration(labelText: tr('Current master password')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _n1,
          obscureText: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: tr('New master password')),
        ),
        const SizedBox(height: 8),
        StrengthBar(_n1.text),
        const SizedBox(height: 12),
        TextField(
          controller: _n2,
          obscureText: true,
          decoration: InputDecoration(labelText: tr('Type it again')),
        ),
        if (_err.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(tr(_err), style: TextStyle(color: Envelope.of(context).red)),
        ],
        const SizedBox(height: 18),
        FilledButton(onPressed: _go, child: Text(tr('Change password'))),
        const SizedBox(height: 12),
        Text(
          tr(
            'Your PC keeps its own master password. Sync still works if they differ.',
          ),
          style: TextStyle(color: Envelope.of(context).ink3, fontSize: 12.5),
        ),
      ],
    ),
  );
}

// =====================================================================
//  Settings › Auto-lock
// =====================================================================
class AutoLockPage extends StatefulWidget {
  const AutoLockPage({super.key});
  @override
  State<AutoLockPage> createState() => _AutoLockPageState();
}

class _AutoLockPageState extends State<AutoLockPage> {
  String _idle(int m) => m == 60 ? '1 hour' : '$m minute${m == 1 ? '' : 's'}';
  String _bg(int s) => s == 0
      ? tr('Immediately')
      : s < 60
      ? tr('After $s seconds')
      : tr('After ${s ~/ 60} minute${s == 60 ? '' : 's'}');

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    Widget head(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 4),
      child: Text(
        t,
        style: TextStyle(fontWeight: FontWeight.w600, color: e.ink2),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(tr('Auto-lock'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        children: [
          head(tr('Lock when I haven\'t used MyVault for')),
          RadioGroup<int>(
            groupValue: Session.idleMinutes,
            onChanged: (v) {
              setState(() => Session.idleMinutes = v!);
              Session.saveLockPrefs();
            },
            child: Column(
              children: [
                for (final m in Session.idleChoices)
                  RadioListTile<int>(
                    value: m,
                    title: Text(tr(_idle(m))),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
              ],
            ),
          ),
          head(tr('Lock after I switch to another app')),
          RadioGroup<int>(
            groupValue: Session.backgroundSeconds,
            onChanged: (v) {
              setState(() => Session.backgroundSeconds = v!);
              Session.saveLockPrefs();
            },
            child: Column(
              children: [
                for (final s in Session.backgroundChoices)
                  RadioListTile<int>(
                    value: s,
                    title: Text(tr(_bg(s))),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tr(
              'Shorter is safer. "Immediately" also locks when you briefly switch apps to copy something.',
            ),
            style: TextStyle(color: e.ink3, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
//  Language
// =====================================================================
class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

  Future<void> _pick(String v) async {
    try {
      final p = await upd.loadPrefs();
      p['language'] = v;
      await upd.savePrefs(p);
    } catch (_) {}
    language.value = v;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Language'))),
    body: RadioGroup<String>(
      groupValue: language.value,
      onChanged: (v) => v == null ? null : _pick(v),
      child: ListView(
        children: [
          // Each language is named in itself, so it can be found whichever one is showing.
          RadioListTile(value: 'auto', title: Text(tr('Same as this phone'))),
          RadioListTile(value: 'en', title: Text(tr('English'))),
          const RadioListTile(value: 'ar', title: Text('العربية')),
        ],
      ),
    ),
  );
}
