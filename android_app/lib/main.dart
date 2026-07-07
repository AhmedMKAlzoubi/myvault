import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'crypto.dart';
import 'generator.dart';
import 'vault.dart';

void main() => runApp(const MyVaultApp());

// ---- black & white theme ----
final _theme = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme.light(
    primary: Color(0xFF111111),
    onPrimary: Colors.white,
    surface: Colors.white,
    onSurface: Color(0xFF111111),
  ),
  scaffoldBackgroundColor: Colors.white,
  fontFamily: 'Roboto',
  inputDecorationTheme: const InputDecorationTheme(
    isDense: true,
    border: OutlineInputBorder(),
    labelStyle: TextStyle(color: Color(0xFF666666)),
  ),
);

Future<String> vaultFilePath() async {
  final dir = await getApplicationDocumentsDirectory();
  return '${dir.path}/vault.dat';
}

class MyVaultApp extends StatelessWidget {
  const MyVaultApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MyVault',
        theme: _theme,
        debugShowCheckedModeBanner: false,
        home: const UnlockPage(),
      );
}

// =====================================================================
//  Unlock / create
// =====================================================================
class UnlockPage extends StatefulWidget {
  const UnlockPage({super.key});
  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final _pw1 = TextEditingController();
  final _pw2 = TextEditingController();
  bool _exists = false;
  bool _loading = true;
  String _error = '';
  String _path = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _path = await vaultFilePath();
    _exists = File(_path).existsSync();
    setState(() => _loading = false);
  }

  Future<void> _submit() async {
    final pw = _pw1.text;
    if (pw.isEmpty) return setState(() => _error = 'Enter a password.');
    if (!_exists) {
      if (pw.length < 8) return setState(() => _error = 'Use at least 8 characters.');
      if (pw != _pw2.text) return setState(() => _error = 'The passwords do not match.');
    }
    try {
      final vault = _exists ? Vault.open(_path, pw) : Vault.create(_path, pw);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomePage(vault: vault)));
    } on WrongPasswordException {
      setState(() => _error = 'Wrong master password. Try again.');
    } on VaultFormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('MyVault',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(_exists ? 'Enter your master password' : 'Create your master password',
                style: const TextStyle(color: Color(0xFF666666))),
            const SizedBox(height: 24),
            TextField(
              controller: _pw1,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Master password'),
              onSubmitted: (_) => _exists ? _submit() : null,
            ),
            if (!_exists) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _pw2,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm master password'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Write this down somewhere safe. There is NO way to recover your '
                'vault if you forget it — that is what keeps it secure.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF666666), fontSize: 12),
              ),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_error, style: const TextStyle(color: Color(0xFFA00000))),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: Text(_exists ? 'Unlock' : 'Create vault'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// =====================================================================
//  Home: searchable list
// =====================================================================
class HomePage extends StatefulWidget {
  final Vault vault;
  const HomePage({super.key, required this.vault});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _search = TextEditingController();

  List<Entry> get _items => widget.vault.search(_search.text);

  void _openEntry(Entry? entry) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => EntryPage(vault: widget.vault, entry: entry)));
    if (changed == true) setState(() {});
  }

  void _lock() {
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const UnlockPage()));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        foregroundColor: Colors.white,
        title: const Text('MyVault'),
        actions: [
          IconButton(onPressed: _lock, icon: const Icon(Icons.lock_outline), tooltip: 'Lock'),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search',
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text('No entries yet. Tap + to add one.',
                      style: TextStyle(color: Color(0xFF666666))))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = items[i];
                    return ListTile(
                      title: Text(e.displayName()),
                      subtitle: Text(
                        [e.username, e.email].where((s) => s.isNotEmpty).join('  •  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _openEntry(e),
                    );
                  },
                ),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF111111),
        foregroundColor: Colors.white,
        onPressed: () => _openEntry(null),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// =====================================================================
//  Entry edit page
// =====================================================================
class EntryPage extends StatefulWidget {
  final Vault vault;
  final Entry? entry;
  const EntryPage({super.key, required this.vault, this.entry});
  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  late Entry _e;
  late bool _isNew;
  final _c = <String, TextEditingController>{};
  final _custom = <List<TextEditingController>>[];
  bool _showPw = false;

  static const _fields = [
    ['title', 'Title / name'],
    ['website', 'Website'],
    ['app', 'App name'],
    ['username', 'Username'],
    ['email', 'Email'],
    ['region', 'Region / country'],
    ['age', 'Age'],
    ['gender', 'Gender'],
    ['phone', 'Phone'],
  ];

  @override
  void initState() {
    super.initState();
    _isNew = widget.entry == null;
    _e = widget.entry ?? Entry();
    for (final f in _fields) {
      _c[f[0]] = TextEditingController(text: _get(f[0]));
    }
    _c['password'] = TextEditingController(text: _e.password);
    _c['notes'] = TextEditingController(text: _e.notes);
    _e.custom.forEach((k, v) => _custom.add([
          TextEditingController(text: k),
          TextEditingController(text: v),
        ]));
  }

  String _get(String key) => {
        'title': _e.title,
        'website': _e.website,
        'app': _e.app,
        'username': _e.username,
        'email': _e.email,
        'region': _e.region,
        'age': _e.age,
        'gender': _e.gender,
        'phone': _e.phone,
      }[key]!;

  void _collect() {
    _e.title = _c['title']!.text.trim();
    _e.website = _c['website']!.text.trim();
    _e.app = _c['app']!.text.trim();
    _e.username = _c['username']!.text.trim();
    _e.email = _c['email']!.text.trim();
    _e.region = _c['region']!.text.trim();
    _e.age = _c['age']!.text.trim();
    _e.gender = _c['gender']!.text.trim();
    _e.phone = _c['phone']!.text.trim();
    _e.password = _c['password']!.text;
    _e.notes = _c['notes']!.text.trim();
    _e.custom = {
      for (final row in _custom)
        if (row[0].text.trim().isNotEmpty) row[0].text.trim(): row[1].text,
    };
  }

  void _save() {
    _collect();
    if (_e.displayName() == '(untitled)') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Give it at least a title, website, or username.')));
      return;
    }
    if (_isNew) {
      widget.vault.add(_e);
    } else {
      widget.vault.update(_e);
    }
    Navigator.of(context).pop(true);
  }

  void _delete() {
    if (_isNew) return Navigator.of(context).pop(false);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete entry'),
        content: Text('Delete "${_e.displayName()}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              widget.vault.deleteById(_e.id);
              Navigator.pop(context);
              Navigator.of(context).pop(true);
            },
            child: const Text('Delete', style: TextStyle(color: Color(0xFFA00000))),
          ),
        ],
      ),
    );
  }

  void _copy(String label, String value) {
    if (value.isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label copied — clears in 30s.')));
    Timer(const Duration(seconds: 30), () async {
      final cur = await Clipboard.getData('text/plain');
      if (cur?.text == value) Clipboard.setData(const ClipboardData(text: ''));
    });
  }

  Future<void> _generate() async {
    final policy = PasswordPolicy.fromJson(_e.passwordPolicy);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => GeneratorSheet(policy: policy),
    );
    if (result != null) {
      setState(() {
        _c['password']!.text = result;
        _showPw = true;
      });
    }
  }

  Widget _field(String key, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _c[key],
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        foregroundColor: Colors.white,
        title: Text(_isNew ? 'New entry' : 'Edit entry'),
        actions: [
          IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final f in _fields.take(5)) _field(f[0], f[1]),
        // password row
        TextField(
          controller: _c['password'],
          obscureText: !_showPw,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            labelText: 'Password',
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPw = !_showPw),
              ),
              IconButton(icon: const Icon(Icons.casino_outlined), onPressed: _generate),
            ]),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy password'),
            onPressed: () => _copy('Password', _c['password']!.text),
          ),
        ),
        for (final f in _fields.skip(5)) _field(f[0], f[1]),
        const SizedBox(height: 8),
        TextField(
          controller: _c['notes'],
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Notes'),
        ),
        const SizedBox(height: 16),
        Row(children: [
          const Text('Extra fields', style: TextStyle(color: Color(0xFF666666))),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add'),
            onPressed: () => setState(() => _custom.add(
                [TextEditingController(), TextEditingController()])),
          ),
        ]),
        for (int i = 0; i < _custom.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _custom[i][0],
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _custom[i][1],
                  decoration: const InputDecoration(labelText: 'Value'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _custom.removeAt(i)),
              ),
            ]),
          ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ]),
    );
  }
}

// =====================================================================
//  Generator bottom sheet
// =====================================================================
class GeneratorSheet extends StatefulWidget {
  final PasswordPolicy policy;
  const GeneratorSheet({super.key, required this.policy});
  @override
  State<GeneratorSheet> createState() => _GeneratorSheetState();
}

class _GeneratorSheetState extends State<GeneratorSheet> {
  late PasswordPolicy _p;
  String _preview = '';

  @override
  void initState() {
    super.initState();
    _p = widget.policy;
    _regen();
  }

  void _regen() {
    try {
      _preview = generatePassword(_p);
    } catch (_) {
      _preview = '';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Generate password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Length'),
          Expanded(
            child: Slider(
              min: 6, max: 64, value: _p.length.toDouble(),
              label: '${_p.length}',
              onChanged: (v) => setState(() { _p.length = v.round(); _regen(); }),
            ),
          ),
          Text('${_p.length}'),
        ]),
        _toggle('Uppercase (A-Z)', _p.useUpper, (v) => _p.useUpper = v),
        _toggle('Lowercase (a-z)', _p.useLower, (v) => _p.useLower = v),
        _toggle('Digits (0-9)', _p.useDigits, (v) => _p.useDigits = v),
        _toggle('Symbols', _p.useSymbols, (v) => _p.useSymbols = v),
        _toggle('Avoid look-alike characters', _p.avoidAmbiguous, (v) => _p.avoidAmbiguous = v),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          width: double.infinity,
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFF111111))),
          child: Row(children: [
            Expanded(child: SelectableText(_preview, style: const TextStyle(fontFamily: 'monospace'))),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _regen),
          ]),
        ),
        const SizedBox(height: 6),
        Text('Strength: ${strengthLabel(_preview)}',
            style: const TextStyle(color: Color(0xFF666666))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _preview.isEmpty ? null : () => Navigator.pop(context, _preview),
              child: const Text('Use this'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _toggle(String label, bool value, void Function(bool) onChanged) => SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        activeThumbColor: const Color(0xFF111111),
        onChanged: (v) => setState(() { onChanged(v); _regen(); }),
      );
}
