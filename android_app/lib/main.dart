import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart' show InvalidCipherTextException;

import 'crypto.dart';
import 'generator.dart';
import 'kinds.dart';
import 'paper.dart' as paper;
import 'sync.dart' as qrsync;
import 'theme.dart';
import 'update_ui.dart';
import 'vault.dart';
import 'version.dart';

void main() => runApp(const MyVaultApp());

const _autoLockBackground = Duration(seconds: 30);
const _autoLockIdle = Duration(minutes: 5);
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

  static void open(Vault v) {
    vault = v;
    touch();
  }

  static void touch() {
    _idle?.cancel();
    if (vault != null) {
      _idle = Timer(
        _autoLockIdle,
        () => lock('Locked after 5 minutes without use.'),
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
        DateTime.now().difference(p) > _autoLockBackground) {
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
  ..showSnackBar(SnackBar(content: Text(msg)));

Future<void> _copy(BuildContext c, String value, String what) async {
  if (value.isEmpty) return _snack(c, '$what is empty.');
  await _Clip.copy(value);
  if (c.mounted) {
    _snack(c, '$what copied. It clears from the clipboard in 30 s.');
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
    child: MaterialApp(
      title: 'MyVault',
      navigatorKey: _nav,
      theme: buildTheme(Envelope.light, Brightness.light),
      darkTheme: buildTheme(Envelope.dark, Brightness.dark),
      debugShowCheckedModeBanner: false,
      home: const UnlockPage(),
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
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        color: e.ink,
        height: 1.5,
      ),
    );
    return Semantics(
      label: open ? null : 'Hidden value',
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
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: i < lv ? col : e.rule,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        const SizedBox(width: 8),
        Text(
          s.isEmpty ? '' : 'Strength: $s',
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
      return setState(() => _error = 'Enter your master password.');
    }
    if (!_exists) {
      if (pw.length < 8) {
        return setState(
          () => _error =
              'Use at least 8 characters. A short sentence works well.',
        );
      }
      if (pw != _pw2.text) {
        return setState(() => _error = "The two passwords don't match.");
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
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
    } on WrongPasswordException {
      setState(() {
        _busy = false;
        _error = "That isn't the master password. Try again.";
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
                          'MyVault',
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
                          ? 'Your vault is sealed. Enter your master password to open it.'
                          : "Choose the one password that opens your vault. It's the only one you'll need to remember.",
                      style: TextStyle(color: e.ink2, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _pw1,
                      obscureText: true,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: _exists
                            ? 'Master password'
                            : 'Choose a master password',
                      ),
                      onChanged: _exists ? null : (_) => setState(() {}),
                      onSubmitted: (_) => _exists ? _submit() : null,
                    ),
                    if (!_exists) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _pw2,
                        obscureText: true,
                        decoration: const InputDecoration(
                          hintText: 'Type it again',
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
                          "There's no reset. If this password is forgotten, nobody can open the vault, not even you. "
                          'Write it down and keep it somewhere safe.',
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
                      Text(_error, style: TextStyle(color: e.red)),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        _busy
                            ? (_exists ? 'Opening…' : 'Creating…')
                            : (_exists ? 'Unlock' : 'Create my vault'),
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
    });
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
              const Text(
                'What are you adding?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (final k in kindDefs.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Glyph(k.value.icon, size: 40),
                  title: Text(
                    k.value.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(k.value.desc),
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
      case 'updates':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const UpdatesPage()));
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
        title: const Row(
          children: [
            EnvelopeMark(width: 24),
            SizedBox(width: 10),
            Text('MyVault'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _sync,
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Sync with PC',
          ),
          IconButton(
            onPressed: Session.lock,
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Lock',
          ),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'gen', child: Text('Password generator')),
              PopupMenuItem(value: 'paper', child: Text('Restore from paper')),
              PopupMenuItem(
                value: 'master',
                child: Text('Change master password'),
              ),
              PopupMenuItem(value: 'updates', child: Text('Updates')),
              PopupMenuItem(value: 'lock', child: Text('Lock now')),
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
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: 'Search',
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final f in [
                        ('all', 'All'),
                        for (final k in kindDefs.entries)
                          (k.key, k.value.plural),
                      ])
                        if (f.$1 == 'all' || counts[f.$1]! > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
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
                        subtitle: sub.isEmpty
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
        label: const Text('New'),
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
                  empty ? 'Your vault is empty' : 'Nothing matches “$query”',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  empty
                      ? 'Start with the account you use most. Logins, API keys, SSH keys and notes are all encrypted on this phone.'
                      : 'Try a shorter word, or check the type filter.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: e.ink2, height: 1.4),
                ),
                if (empty) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                    label: const Text('Add your first entry'),
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
                Text(f.label, style: TextStyle(fontSize: 12.5, color: e.ink2)),
                const SizedBox(height: 4),
                f.secret
                    ? SecretValue(value, key: key, multi: f.multi)
                    : SelectableText(
                        value,
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
            tooltip: 'Copy ${f.label.toLowerCase()}',
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
    final rows = [
      ...k.fields,
      ...k.more,
    ].map((f) => (f, f.read(x))).where((r) => r.$2.isNotEmpty).toList();
    final custom = x.custom.entries.toList();
    final sub = [
      k.label,
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
      return '${d.day} ${m[d.month - 1]} ${d.year}';
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
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
          if (custom.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(
              'Extra fields',
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
                'Nothing stored here yet. Tap Edit to add details.',
                style: TextStyle(color: e.ink2),
              ),
            ),
          const SizedBox(height: 20),
          Text(
            'Last changed ${date(x.updatedAt)} · Created ${date(x.createdAt)}',
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
      tooltip: open ? 'Hide' : 'Show',
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
  late final List<List<TextEditingController>> _custom = [
    for (final c in _e.custom.entries)
      [
        TextEditingController(text: c.key),
        TextEditingController(text: c.value),
      ],
  ];

  void _save() {
    _e.title = _title.text.trim();
    for (final f in [..._k.fields, ..._k.more]) {
      f.write(_e, _c[f.key]!.text);
    }
    if (_e.kind != 'note') _e.notes = _notes.text;
    _e.custom = {
      for (final r in _custom)
        if (r[0].text.trim().isNotEmpty) r[0].text.trim(): r[1].text,
    };
    if (_e.displayName() == '(untitled)') {
      return _snack(context, 'Give it a name first.');
    }
    final v = Session.vault!;
    widget.isNew ? v.add(_e) : v.update(_e);
    Navigator.of(context).pop(false);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete for good?'),
        content: Text(
          '“${_e.displayName()}” will be removed from this phone, and from your PC at the next sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Delete', style: TextStyle(color: Envelope.of(c).red)),
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

  Widget _field(FieldDef f) {
    final c = _c[f.key]!;
    final hidden = f.secret && !_shown.contains(f.key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: c,
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
              labelText: f.label,
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
                          tooltip: hidden ? 'Show' : 'Hide',
                          onPressed: () => setState(
                            () => hidden
                                ? _shown.add(f.key)
                                : _shown.remove(f.key),
                          ),
                        ),
                        if (f.gen)
                          IconButton(
                            icon: const Icon(Icons.casino_outlined, size: 20),
                            tooltip: 'Generate',
                            onPressed: _generate,
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New ${_k.label.toLowerCase()}' : 'Edit'),
        actions: [
          if (!widget.isNew)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        children: [
          TextField(
            controller: _title,
            autofocus: widget.isNew,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 14),
          for (final f in _k.fields) _field(f),
          if (_k.more.isNotEmpty)
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: _k.more.any((f) => f.read(_e).isNotEmpty),
                title: Text(
                  'Profile details',
                  style: TextStyle(
                    color: e.ink2,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'App, phone, region, age, gender',
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
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                'Extra fields',
                style: TextStyle(color: e.ink2, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add field'),
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
                      decoration: const InputDecoration(hintText: 'Label'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _custom[i][1],
                      decoration: const InputDecoration(hintText: 'Value'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove field',
                    onPressed: () => setState(() => _custom.removeAt(i)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
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
        title: Text(label),
        subtitle: Text(sub),
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
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
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
                        'Turn on at least one kind of character.',
                        style: TextStyle(color: e.ink2),
                      )
                    : pwText(context, _pw, size: 19),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'New password',
                onPressed: _regen,
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: 'Copy',
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
            const Text('Length'),
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
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        _sw('Uppercase letters', 'A–Z', _p.useUpper, (v) => _p.useUpper = v),
        _sw('Lowercase letters', 'a–z', _p.useLower, (v) => _p.useLower = v),
        _sw('Numbers', '0–9', _p.useDigits, (v) => _p.useDigits = v),
        _sw('Symbols', '! @ # \$ …', _p.useSymbols, (v) => _p.useSymbols = v),
        _sw(
          'Avoid look-alikes',
          'No l, 1, O, 0, I',
          _p.avoidAmbiguous,
          (v) => _p.avoidAmbiguous = v,
        ),
        if (widget.onUse != null) ...[
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _pw.isEmpty ? null : () => widget.onUse!(_pw),
            child: const Text('Use this password'),
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
    appBar: AppBar(title: const Text('Password generator')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          "Random, from this phone's secure random source. Nothing is saved unless you copy it.",
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
  String _status = 'Looking for a code…';

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
                "MyVault can't use the camera (${err.errorCode.name}). Allow camera access for MyVault in "
                'Android settings › Apps › MyVault › Permissions, then try again.',
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
          ? 'Synced. ${r.changed} ${r.changed == 1 ? 'entry' : 'entries'} updated on this phone. Your PC has the rest.${_versionNote(r)}'
          : r.error;
    });
    final got = r.received;
    if (got != null && mounted) {
      await offerInstall(
        context,
        got,
        from:
            'Your PC has MyVault ${got.version} and passed the update to this phone.',
      );
    }
  }

  String _versionNote(qrsync.SyncResult r) {
    final pc = r.peerVersion;
    if (pc.isEmpty) {
      return ' Your PC runs an older MyVault (before 0.5). Update it with the new installer; '
          'after that, updates pass between your devices when you sync.';
    }
    if (r.received != null) return '';
    if (r.sent.isNotEmpty) {
      return ' Your PC had MyVault $pc, so this phone passed it the ${r.sent} update. Install it from the card in the PC app.';
    }
    if (isNewerVersion(pc, appVersion)) {
      return ' Your PC has MyVault $pc (this phone has $appVersion).'
          '${r.updateError.isEmpty ? ' Update this phone from Updates in the menu.' : ' The update couldn\'t be passed over: ${r.updateError}'}';
    }
    if (isNewerVersion(appVersion, pc)) {
      return ' Your PC runs MyVault $pc (this phone has $appVersion). Update the PC when you can.';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    if (_state == 'scan') {
      return Scaffold(
        appBar: AppBar(title: const Text('Scan the code on your PC')),
        body: ScannerView(
          hint:
              'On your PC, open MyVault → Sync with phone → Show sync code. '
              'Hold the phone 15–30 cm from the screen.',
          recognizes: (raw) => raw.startsWith('myvault://sync'),
          wrongCode:
              "That QR code isn't a MyVault sync code. Point at the code in MyVault's Sync with phone screen.",
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
      appBar: AppBar(title: const Text('Sync with PC')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Your phone and PC swap changes directly over your WiFi. No cloud is involved.',
            style: TextStyle(color: e.ink2, height: 1.4),
          ),
          const SizedBox(height: 16),
          Text(
            '1. On the PC, open MyVault and choose Sync with phone.\n2. Choose Show sync code.\n3. Tap Scan below and point the camera at it.',
            style: TextStyle(height: 1.6, color: e.ink),
          ),
          const SizedBox(height: 18),
          if (_state == 'busy') ...[
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 10),
            const Text('Syncing with your PC…'),
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
              child: Text(_msg),
            ),
          if (_state != 'busy')
            FilledButton.icon(
              onPressed: () => setState(() => _state = 'scan'),
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(_state == 'intro' ? 'Scan sync code' : 'Scan again'),
            ),
          const SizedBox(height: 24),
          fact(
            Icons.verified_user_outlined,
            'The code is the key. ',
            'It holds a one-time random key that only travels through the camera, so nobody else on the WiFi can read the sync.',
          ),
          fact(
            Icons.wifi,
            'Same WiFi only. ',
            'The PC stops listening after one sync, or after 2 minutes.',
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
      return setState(() => _msg = "That code isn't from a MyVault backup.");
    }
    _seen.add(clean);
    try {
      var key = _keys[block.saltKey];
      if (key == null) {
        setState(() {
          _busy = true;
          _msg = 'Checking the backup password… (slow on purpose)';
        });
        key = await paper.deriveBackupKey(_pw.text, block.salt);
        _keys[block.saltKey] = key;
      }
      final entry = paper.decryptBlock(block, key);
      setState(() {
        _found[entry.id] = entry;
        _busy = false;
        _msg = 'Read ${_found.length}. Keep scanning, or tap Done.';
      });
    } on InvalidCipherTextException {
      _seen.remove(clean);
      _keys.remove(block.saltKey);
      setState(() {
        _busy = false;
        _scanning = false;
        _msg = "That backup password doesn't open this sheet.";
      });
    } catch (_) {
      setState(() {
        _busy = false;
        _msg = "Couldn't read that code. Try holding the phone steadier.";
      });
    }
  }

  void _finish() {
    final n = _found.length;
    final changed = Session.vault!.restoreIn(_found.values.toList());
    _snack(
      context,
      changed == 0
          ? 'Read $n ${n == 1 ? 'entry' : 'entries'}. All were already in your vault.'
          : 'Read $n ${n == 1 ? 'entry' : 'entries'}. $changed restored or updated.',
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    if (_scanning) {
      return Scaffold(
        appBar: AppBar(title: Text('Scanning: ${_found.length} read')),
        body: ScannerView(
          hint:
              'Point the camera at each code on the backup sheet, one at a time.',
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
                child: Text('Done: restore ${_found.length}'),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Restore from paper')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Bring back entries from a printed MyVault backup. Each code on the sheet is one encrypted entry; '
            'restored entries are merged into this vault, keeping the newer version of anything you already have.',
            style: TextStyle(color: e.ink2, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pw,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Backup password'),
          ),
          if (_msg.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_msg, style: TextStyle(color: e.red)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              if (_pw.text.isEmpty) {
                return setState(
                  () => _msg = 'Enter the backup password first.',
                );
              }
              setState(() {
                _scanning = true;
                _msg = '';
              });
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Start scanning'),
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
      return setState(() => _err = 'The current master password is wrong.');
    }
    if (_n1.text.length < 8) {
      return setState(() => _err = 'Use at least 8 characters.');
    }
    if (_n1.text != _n2.text) {
      return setState(() => _err = "The new passwords don't match.");
    }
    v.changePassword(_n1.text);
    _snack(context, 'Master password changed.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Change master password')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        TextField(
          controller: _cur,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Current master password',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _n1,
          obscureText: true,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'New master password'),
        ),
        const SizedBox(height: 8),
        StrengthBar(_n1.text),
        const SizedBox(height: 12),
        TextField(
          controller: _n2,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Type it again'),
        ),
        if (_err.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_err, style: TextStyle(color: Envelope.of(context).red)),
        ],
        const SizedBox(height: 18),
        FilledButton(onPressed: _go, child: const Text('Change password')),
        const SizedBox(height: 12),
        Text(
          'Your PC keeps its own master password. Sync still works if they differ.',
          style: TextStyle(color: Envelope.of(context).ink3, fontSize: 12.5),
        ),
      ],
    ),
  );
}
