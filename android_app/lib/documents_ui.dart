/// Personal documents on the phone: the parts of the entry screens that are
/// special to documents (files, reading details, reminders), the file viewer,
/// "Expiring soon", and the settings. Storage and rules live in docs.dart.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'docs.dart';
import 'l10n.dart';
import 'l10n_ar.dart' show arabicMonths;
import 'theme.dart';
import 'update.dart' as upd;
import 'vault.dart';

const _ch = MethodChannel('myvault/docs');

void _snack(BuildContext c, String msg) => ScaffoldMessenger.of(c)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(tr(msg))));

String fmtDay(String iso) {
  final d = parseDay(iso);
  if (d == null) return iso;
  const en = [
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
  return '${d.day} ${(isArabic ? arabicMonths : en)[d.month - 1]} ${d.year}';
}

/// "Expires 1 Mar 2027", in the tint when it's within a month, red once expired.
Widget expiryText(BuildContext context, String iso) {
  final e = Envelope.of(context);
  final n = daysLeft(iso);
  return Text(
    n < 0
        ? tr('Expired ${fmtDay(iso)}')
        : n == 0
        ? tr('Expires today')
        : tr('Expires ${fmtDay(iso)}'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: n < 0 ? e.red : (n <= 30 ? e.tint : e.ink3),
      fontWeight: n <= 30 ? FontWeight.w600 : null,
    ),
  );
}

/// Hand the reminder schedule to Android (ReminderJob). Called after every save.
Future<void> pushReminders(Vault v) async {
  try {
    await _ch.invokeMethod('setReminders', jsonEncode(schedule(v.entries)));
  } on MissingPluginException {
    // tests: no Android side
  }
}

/// Photos the phone took or files you picked, as (name, bytes).
Future<List<(String, Uint8List)>> _getFiles(String how) async {
  final got = await _ch.invokeListMethod<dynamic>(how) ?? [];
  return [
    for (final m in got.cast<Map>()) ('${m['name']}', m['bytes'] as Uint8List),
  ];
}

/// The text in one file (the phone's own reader, on the phone).
Future<String> textOf(Vault v, FileRef r) async {
  final text = await _ch.invokeMethod<String>('ocr', {
    'bytes': await openFile(v, r),
  });
  return text ?? '';
}

/// A picture of the file: the photo itself, or a PDF's first page.
Future<Uint8List> previewOf(Vault v, FileRef r, {int width = 900}) async {
  final data = await openFile(v, r);
  if (!r.isPdf) return data;
  return (await _ch.invokeMethod<Uint8List>('pdfPreview', {
    'bytes': data,
    'width': width,
  }))!;
}

// ---- thumbnails and the viewer ---------------------------------------------------
class FileThumb extends StatelessWidget {
  final Vault vault;
  final FileRef file;
  final VoidCallback? onTap;
  const FileThumb({
    super.key,
    required this.vault,
    required this.file,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 120,
        height: 90,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: e.panel,
          border: Border.all(color: e.rule2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: FutureBuilder<Uint8List>(
          future: previewOf(vault, file, width: 360),
          builder: (_, s) => Stack(
            fit: StackFit.expand,
            children: [
              if (s.hasData)
                Image.memory(
                  s.data!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: e.ink3,
                    ),
                  ),
                ),
              if (s.hasError)
                Center(child: Icon(Icons.cloud_off_outlined, color: e.ink3)),
              if (file.isPdf)
                PositionedDirectional(
                  start: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: e.ink,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'PDF',
                      style: TextStyle(
                        color: e.paper,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
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

class FileViewerPage extends StatelessWidget {
  final Vault vault;
  final FileRef file;
  const FileViewerPage({super.key, required this.vault, required this.file});

  Future<void> _save(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Save an unprotected copy?')),
        content: Text(
          tr(
            "The copy isn't encrypted: any app or person that can open where you save it can see it.",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Save a copy')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final done = await _ch.invokeMethod<bool>('saveCopy', {
        'bytes': await openFile(vault, file),
        'name': file.name,
        'mime': file.mime,
      });
      if (done == true && context.mounted) _snack(context, 'Saved.');
    } on FormatException catch (e) {
      if (context.mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(file.name, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: tr('Save a copy'),
          icon: const Icon(Icons.download_outlined),
          onPressed: () => _save(context),
        ),
      ],
    ),
    body: FutureBuilder<Uint8List>(
      future: previewOf(vault, file, width: 1600),
      builder: (_, s) => s.hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('${s.error}')),
              ),
            )
          : !s.hasData
          ? const Center(child: CircularProgressIndicator())
          : InteractiveViewer(
              maxScale: 6,
              child: Center(child: Image.memory(s.data!)),
            ),
    ),
  );
}

// ---- the view page's document part --------------------------------------------------
class DocumentSection extends StatelessWidget {
  final Vault vault;
  final Entry entry;
  const DocumentSection({super.key, required this.vault, required this.entry});

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    final days = remindDays(entry);
    final files = fileRefs(entry);
    final expires = entry.fields['expires'] ?? '';
    final name = (entry.fields['remind_name'] ?? '').trim();
    final head = TextStyle(
      fontWeight: FontWeight.w600,
      color: e.ink2,
      fontSize: 13,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        Text(tr('Reminders'), style: head),
        const SizedBox(height: 6),
        Text(
          expires.isEmpty
              ? tr('Add the expiry date to get reminders.')
              : days.isEmpty
              ? tr('No reminders set. Tap Edit to add some.')
              : '${days.map((d) => tr(leadLabel(d))).join(tr(','))} ${tr('before it expires, and on the day.')}',
          style: TextStyle(color: e.ink),
        ),
        if (expires.isNotEmpty && days.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${tr('A notification will say:')} “${reminderText(name, entry.fields['doc_type'] ?? '', days.first)}”',
              style: TextStyle(color: e.ink3, fontSize: 12.5),
            ),
          ),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(tr('Files'), style: head),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final f in files)
                FileThumb(
                  vault: vault,
                  file: f,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FileViewerPage(vault: vault, file: f),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---- the edit page's document part ---------------------------------------------------
/// Files, reading details from them, reminders and the name used in them.
/// [fill] sets a field if it's still empty and says whether it did.
class DocumentEditor extends StatefulWidget {
  final Vault vault;
  final Entry entry;
  final bool isNew;
  final bool Function(String key, String value) fill;
  final bool Function(String key) isEmpty;
  final String Function() type; // the type chosen right now
  final DocumentDraft draft;
  const DocumentEditor({
    super.key,
    required this.vault,
    required this.entry,
    required this.isNew,
    required this.fill,
    required this.isEmpty,
    required this.type,
    required this.draft,
  });
  @override
  State<DocumentEditor> createState() => _DocumentEditorState();
}

/// What the editor has collected; the page writes it into the entry on save.
class DocumentDraft {
  List<FileRef> files = [];
  Set<int> days = {};
  final name = TextEditingController();
  void writeTo(Entry e) {
    setFileRefs(e, files);
    e.fields['remind'] = (days.toList()..sort((a, b) => b - a)).join(',');
    if (e.fields['remind']!.isEmpty) e.fields.remove('remind');
    final n = name.text.trim();
    n.isEmpty ? e.fields.remove('remind_name') : e.fields['remind_name'] = n;
  }
}

class _DocumentEditorState extends State<DocumentEditor> {
  final _custom = TextEditingController();
  String _note = '';
  bool _busy = false;
  bool _check = false; // the note asks to check what was filled in
  DocumentDraft get d => widget.draft;

  @override
  void initState() {
    super.initState();
    d.files = fileRefs(widget.entry);
    d.days = widget.isNew ? {30, 7} : remindDays(widget.entry).toSet();
    d.name.text = widget.entry.fields['remind_name'] ?? '';
  }

  Future<void> _add(String how) async {
    try {
      List<(String, Uint8List)> got;
      try {
        got = await _getFiles(how);
      } on PlatformException catch (e) {
        // No Google document scanner on this phone: the plain camera instead.
        if (how != 'scan' || e.code != 'no_scanner') rethrow;
        got = await _getFiles('camera');
      }
      final added = <FileRef>[];
      for (final (name, bytes) in got) {
        added.add(await seal(widget.vault, bytes, name));
      }
      if (added.isEmpty) return;
      setState(() => d.files = [...d.files, ...added]);
      if (widget.isEmpty('expires')) await _read();
    } on FormatException catch (e) {
      if (mounted) _snack(context, e.message);
    } on PlatformException catch (e) {
      if (mounted) {
        _snack(context, e.message ?? "That file couldn't be opened.");
      }
    }
  }

  /// Read every file together (an ID's front and back) and fill in what's
  /// still empty; the page then shows the fields for the type that was found.
  Future<void> _read() async {
    if (d.files.isEmpty) {
      setState(() => _note = tr('Add a photo or PDF of the document first.'));
      return;
    }
    setState(() {
      _busy = true;
      _note = tr('Reading the document…');
    });
    try {
      final texts = <String>[];
      for (final f in d.files) {
        texts.add(await textOf(widget.vault, f));
      }
      final got = readDetails(texts);
      final filled = <String>[];
      for (final MapEntry(:key, :value) in got.entries) {
        if (key == 'how' || key == 'guessed') continue;
        if (widget.fill(key, '$value')) filled.add(key);
      }
      final type = widget.type();
      _check = filled.isNotEmpty;
      _note = filled.isEmpty
          ? tr(
              "Couldn't find new details in these files. Type them in instead.",
            )
          : [
              tr(
                'Scans can be misread: check every highlighted box against the document before saving.',
              ),
              tr(
                got['how'] == 'mrz'
                    ? 'Read from the machine-readable zone (the <<< lines) and checked.'
                    : "Read from the document's text.",
              ),
              tr(
                'Filled in: ${filled.map((k) => tr(docLabel(k, type))).join(tr(', '))}.',
              ),
              if (got['guessed'] == true && filled.contains('expires'))
                tr("The expiry date is a guess (it wasn't labelled)."),
            ].join(' ');
    } on FormatException catch (e) {
      _note = tr(e.message);
      _check = false;
    } on PlatformException catch (e) {
      _note = tr(e.message ?? "That file couldn't be read.");
      _check = false;
    } catch (_) {
      _note = tr("That file couldn't be read.");
      _check = false;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    final chips = {...leads.map((l) => l.$1), ...d.days}.toList()..sort();
    final head = TextStyle(
      fontWeight: FontWeight.w600,
      color: e.ink2,
      fontSize: 13,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(tr('Files'), style: head),
        const SizedBox(height: 4),
        Text(
          tr(
            'Scan both sides of a card. The scanner finds the edges for you; drag the corners to adjust. Files are encrypted the moment you add them, and MyVault reads the details from all of them together, on this phone.',
          ),
          style: TextStyle(color: e.ink3, fontSize: 12.5),
        ),
        const SizedBox(height: 4),
        Text(
          tr(
            "Too dark? Tap the scanner's flash button. Photo too bright or shiny? Pick “No filter” after scanning, tilt the card away from the light, or use the camera instead.",
          ),
          style: TextStyle(color: e.ink3, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final f in d.files)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FileThumb(vault: widget.vault, file: f),
                  IconButton(
                    tooltip: tr('Remove file'),
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => setState(
                      () =>
                          d.files = d.files.where((x) => x.id != f.id).toList(),
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (_note.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: _check ? const EdgeInsets.all(10) : EdgeInsets.zero,
            decoration: _check
                ? BoxDecoration(
                    color: const Color(0xFFB7791F).withValues(alpha: .12),
                    border: Border.all(color: const Color(0xFFB7791F)),
                    borderRadius: BorderRadius.circular(10),
                  )
                : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_check)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(end: 8),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: Color(0xFFB7791F),
                    ),
                  ),
                Expanded(
                  child: Text(_note, style: TextStyle(color: e.ink2)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.icon(
              onPressed: () => _add('scan'),
              icon: const Icon(Icons.document_scanner_outlined, size: 18),
              label: Text(tr('Scan document')),
            ),
            OutlinedButton.icon(
              onPressed: () => _add('camera'),
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: Text(tr('Use the camera')),
            ),
            OutlinedButton.icon(
              onPressed: () => _add('pick'),
              icon: const Icon(Icons.attach_file, size: 18),
              label: Text(tr('Choose files')),
            ),
            if (d.files.isNotEmpty)
              TextButton.icon(
                onPressed: _busy ? null : _read,
                icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                label: Text(tr('Read details')),
              ),
          ],
        ),
        const SizedBox(height: 22),
        Text(tr('Remind me before it expires'), style: head),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final n in chips)
              FilterChip(
                label: Text(tr(leadLabel(n))),
                selected: d.days.contains(n),
                onSelected: (on) =>
                    setState(() => on ? d.days.add(n) : d.days.remove(n)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 110,
              child: TextField(
                controller: _custom,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('Days'),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                final n = int.tryParse(_custom.text.trim());
                if (n != null && n > 0 && n <= 3650) {
                  setState(() => d.days.add(n));
                  _custom.clear();
                }
              },
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr('Add days')),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          tr(
            "Choose as many as you like. You're also reminded on the day it expires.",
          ),
          style: TextStyle(color: e.ink3, fontSize: 12.5),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: d.name,
          maxLength: 40,
          decoration: InputDecoration(
            labelText: tr('Name in reminders'),
            hintText: tr(typeLabel(widget.entry.fields['doc_type'])),
            helperText: tr(
              'Keep numbers and private details out: notifications can be seen on a locked screen.',
            ),
            helperMaxLines: 3,
          ),
        ),
      ],
    );
  }
}

// ---- home: what's expiring soon ---------------------------------------------------------
class ExpiringSoon extends StatelessWidget {
  final List<Entry> docs;
  final void Function(Entry) onOpen;
  const ExpiringSoon({super.key, required this.docs, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    final soon =
        docs
            .where(
              (x) =>
                  x.kind == 'document' &&
                  parseDay(x.fields['expires']) != null &&
                  daysLeft(x.fields['expires']!) <= 90,
            )
            .toList()
          ..sort(
            (a, b) => a.fields['expires']!.compareTo(b.fields['expires']!),
          );
    if (soon.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        border: Border.all(color: e.rule2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 2),
            child: Row(
              children: [
                Icon(Icons.notifications_outlined, size: 18, color: e.ink2),
                const SizedBox(width: 6),
                Text(
                  tr('Expiring soon'),
                  style: TextStyle(fontWeight: FontWeight.w600, color: e.ink2),
                ),
              ],
            ),
          ),
          for (final x in soon)
            ListTile(
              dense: true,
              title: Text(
                x.displayName(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: expiryText(context, x.fields['expires']!),
              onTap: () => onOpen(x),
            ),
        ],
      ),
    );
  }
}

// ---- settings ---------------------------------------------------------------------------
class DocumentsSettingsPage extends StatefulWidget {
  const DocumentsSettingsPage({super.key});
  @override
  State<DocumentsSettingsPage> createState() => _DocumentsSettingsPageState();
}

class _DocumentsSettingsPageState extends State<DocumentsSettingsPage> {
  bool _sync = true, _notify = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await upd.loadPrefs();
    bool allowed = true;
    try {
      allowed = await _ch.invokeMethod<bool>('notifyAllowed') ?? true;
    } on MissingPluginException {
      // tests
    }
    if (!mounted) return;
    setState(() {
      _sync = p['sync_files'] != false;
      _notify = allowed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Documents'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _sync,
            title: Text(tr('Sync document files with your PC')),
            subtitle: Text(
              tr(
                'Photos and PDFs travel encrypted over your WiFi when you sync. Turn off to keep them on this phone only; names, numbers and dates always sync.',
              ),
            ),
            onChanged: (v) async {
              final p = await upd.loadPrefs();
              p['sync_files'] = v;
              await upd.savePrefs(p);
              setState(() => _sync = v);
            },
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _notify
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              color: _notify ? e.ok : e.red,
            ),
            title: Text(
              tr(
                _notify
                    ? 'Reminders can notify you.'
                    : "Notifications are off for MyVault, so reminders can't show.",
              ),
            ),
            subtitle: Text(
              tr(
                'Each reminder says only the document type, or the name you chose, and the time left.',
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: () async {
                try {
                  await _ch.invokeMethod(
                    'testNotify',
                    tr('This is how a document reminder looks.'),
                  );
                } on MissingPluginException {
                  // tests
                }
                _load();
              },
              icon: const Icon(Icons.notifications_outlined, size: 18),
              label: Text(tr('Send a test notification')),
            ),
          ),
          const SizedBox(height: 8),
          if (!_notify)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(
                onPressed: () async {
                  await askNotifications();
                  _load();
                },
                child: Text(tr('Allow notifications')),
              ),
            ),
        ],
      ),
    );
  }
}

Future<bool> askNotifications() async {
  try {
    return await _ch.invokeMethod<bool>('askNotify') ?? false;
  } on MissingPluginException {
    return false;
  }
}

/// The phone's "sync document files" setting (on unless switched off).
Future<bool> syncFilesOn() async =>
    (await upd.loadPrefs())['sync_files'] != false;
