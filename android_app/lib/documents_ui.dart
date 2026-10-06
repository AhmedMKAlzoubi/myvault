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
import 'vaults.dart';

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
    await _ch.invokeMethod('setReminders', {
      'vault': currentVault, // each vault keeps its own reminders
      'json': jsonEncode(schedule(v.entries)),
    });
  } on MissingPluginException {
    // tests: no Android side
  }
}

/// A deleted vault's reminders stop.
Future<void> clearReminders(String vault) async {
  try {
    await _ch.invokeMethod('setReminders', {'vault': vault, 'json': '[]'});
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

// ---- MyVault's own scanner: crop and straighten a photo ------------------------------
/// What the crop screen gives back: the cut-out page (empty: take it again),
/// and whether to scan another page after it.
typedef CropResult = ({Uint8List photo, bool more});

/// A scan: camera photos, each through the crop screen, page after page
/// (a card's front and back) until the person taps Done.
Future<List<(String, Uint8List)>> scanPages(BuildContext context) async {
  final out = <(String, Uint8List)>[];
  var shot = await _getFiles('camera');
  while (shot.isNotEmpty) {
    if (!context.mounted) break;
    final got = await Navigator.of(context).push<CropResult>(
      MaterialPageRoute(
        builder: (_) => CropPage(photo: shot.first.$2, page: out.length + 1),
      ),
    );
    if (got == null) break; // cancelled: the pages so far are kept
    if (got.photo.isNotEmpty) out.add((shot.first.$1, got.photo));
    if (got.photo.isNotEmpty && !got.more) break;
    shot = await _getFiles('camera'); // retake, or the next page
  }
  return out;
}

/// Drag the box's corners to the document's; it's cut out and straightened.
/// Pops a [CropResult], or null to cancel.
class CropPage extends StatefulWidget {
  final Uint8List photo;
  final int page; // 1 for the first page of this scan
  const CropPage({super.key, required this.photo, this.page = 1});
  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> {
  late Uint8List _photo = widget.photo;
  static const _inset = [
    Offset(.08, .1),
    Offset(.92, .1),
    Offset(.92, .9),
    Offset(.08, .9),
  ];
  List<Offset> _pts = [
    ..._inset,
  ]; // top-left, top-right, bottom-right, bottom-left
  Size? _size; // the photo, in pixels
  bool _busy = false;
  Uint8List? _cut; // the cut-out page, once the corners are set
  String _look = 'scan'; // scan, bw or original
  final _looks = <String, Uint8List>{}; // each look, made once

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final img = await decodeImageFromList(_photo);
    List<double>? found;
    try {
      found = await _ch.invokeListMethod<double>('detect', {'bytes': _photo});
    } on PlatformException {
      // the box stays where it is
    }
    if (!mounted) return;
    setState(() {
      _size = Size(img.width.toDouble(), img.height.toDouble());
      _pts = found != null && found.length == 8
          ? [for (var i = 0; i < 4; i++) Offset(found[2 * i], found[2 * i + 1])]
          : [..._inset];
    });
  }

  Future<void> _rotate() async {
    setState(() => _busy = true);
    final turned = await _ch.invokeMethod<Uint8List>('rotate', {
      'bytes': _photo,
    });
    if (turned != null) _photo = turned;
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  /// Cut the page out along the corners, then show it with the "scanned" look.
  Future<void> _crop() async {
    setState(() => _busy = true);
    try {
      _cut = await _ch.invokeMethod<Uint8List>('warp', {
        'bytes': _photo,
        'points': [
          for (final p in _pts) ...[p.dx, p.dy],
        ],
      });
      _looks.clear();
      await _setLook(_look);
    } on PlatformException catch (e) {
      if (mounted) _snack(context, e.message ?? "That photo couldn't be used.");
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setLook(String look) async {
    setState(() => _look = look);
    if (_looks[look] != null || _cut == null) return;
    final made = await _ch.invokeMethod<Uint8List>('enhance', {
      'bytes': _cut,
      'mode': look,
    });
    if (made != null && mounted) setState(() => _looks[look] = made);
  }

  Future<void> _use({required bool more}) async {
    setState(() => _busy = true);
    try {
      final out = _looks[_look] ?? _cut;
      if (mounted && out != null) {
        Navigator.of(context).pop<CropResult>((photo: out, more: more));
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(context, e.message ?? "That photo couldn't be used.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.page == 1
              ? tr('Crop the document')
              : tr('Crop page ${widget.page}'),
        ),
        actions: [
          if (_cut == null)
            IconButton(
              tooltip: tr('Turn'),
              icon: const Icon(Icons.rotate_right),
              onPressed: _busy || _size == null ? null : _rotate,
            ),
        ],
      ),
      body: _cut != null
          ? _review(e)
          : Column(
              children: [
                Expanded(
                  child: _size == null
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(
                          builder: (_, box) {
                            final scale = [
                              box.maxWidth / _size!.width,
                              box.maxHeight / _size!.height,
                            ].reduce((a, b) => a < b ? a : b);
                            final w = _size!.width * scale,
                                h = _size!.height * scale;
                            final o = Offset(
                              (box.maxWidth - w) / 2,
                              (box.maxHeight - h) / 2,
                            );
                            Offset at(Offset p) =>
                                o + Offset(p.dx * w, p.dy * h);
                            return Stack(
                              children: [
                                Positioned(
                                  left: o.dx,
                                  top: o.dy,
                                  width: w,
                                  height: h,
                                  child: Image.memory(
                                    _photo,
                                    gaplessPlayback: true,
                                  ),
                                ),
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _BoxPainter([
                                      for (final p in _pts) at(p),
                                    ]),
                                  ),
                                ),
                                for (var i = 0; i < 4; i++)
                                  Positioned(
                                    left: at(_pts[i]).dx - 24,
                                    top: at(_pts[i]).dy - 24,
                                    child: GestureDetector(
                                      onPanUpdate: (d) => setState(() {
                                        final p =
                                            _pts[i] +
                                            Offset(
                                              d.delta.dx / w,
                                              d.delta.dy / h,
                                            );
                                        _pts[i] = Offset(
                                          p.dx.clamp(0.0, 1.0),
                                          p.dy.clamp(0.0, 1.0),
                                        );
                                      }),
                                      child: Container(
                                        width: 48,
                                        height: 48,
                                        alignment: Alignment.center,
                                        child: Container(
                                          width: 22,
                                          height: 22,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: e.tint.withValues(
                                              alpha: .35,
                                            ),
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                ),
                Container(
                  color: e.sheet,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          tr(
                            "Drag the corners onto the document's corners. MyVault cuts it out and straightens it, which also helps it read the details.",
                          ),
                          style: TextStyle(color: e.ink2, fontSize: 13),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          alignment: WrapAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context).pop<CropResult>(
                                      (photo: Uint8List(0), more: false),
                                    ),
                              child: Text(tr('Retake')),
                            ),
                            FilledButton.icon(
                              onPressed: _busy || _size == null ? null : _crop,
                              icon: const Icon(Icons.crop, size: 18),
                              label: Text(tr('Cut it out')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// The cut-out page, with its look: scanned (the default), black and white,
  /// or the photo as it was.
  Widget _review(Envelope e) {
    final shown = _looks[_look];
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: shown == null
                ? const Center(child: CircularProgressIndicator())
                : Center(child: Image.memory(shown, gaplessPlayback: true)),
          ),
        ),
        Container(
          color: e.sheet,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'scan', label: Text(tr('Scanned'))),
                    ButtonSegment(
                      value: 'bw',
                      label: Text(tr('Black & white')),
                    ),
                    ButtonSegment(
                      value: 'original',
                      label: Text(tr('Original')),
                    ),
                  ],
                  selected: {_look},
                  onSelectionChanged: _busy ? null : (v) => _setLook(v.first),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    'Scanned: white paper and crisp text, like a scanner. Black & white suits letters and contracts.',
                  ),
                  style: TextStyle(color: e.ink2, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _cut = null),
                      child: Text(tr('Back')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || shown == null
                          ? null
                          : () => _use(more: true),
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: Text(tr('Add another page')),
                    ),
                    FilledButton.icon(
                      onPressed: _busy || shown == null
                          ? null
                          : () => _use(more: false),
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(tr('Done')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BoxPainter extends CustomPainter {
  final List<Offset> pts;
  _BoxPainter(this.pts);

  @override
  void paint(Canvas canvas, Size size) {
    final box = Path()..addPolygon(pts, true);
    // dim what's outside the box
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        box,
      ),
      Paint()..color = Colors.black.withValues(alpha: .45),
    );
    canvas.drawPath(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.pts != pts;
}

/// A file's thumbnail on an edit page, with a remove button that asks first.
/// The file only leaves the entry when it's saved; until then "Put it back"
/// undoes it, and leaving without saving keeps it.
class RemovableThumb extends StatelessWidget {
  final Vault vault;
  final FileRef file;
  final DocumentDraft draft;
  final VoidCallback changed; // the editor redraws
  const RemovableThumb({
    super.key,
    required this.vault,
    required this.file,
    required this.draft,
    required this.changed,
  });

  Future<void> _remove(BuildContext context) async {
    final e = Envelope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Remove this file?')),
        content: Text(
          tr(
            '“${file.name}” leaves this entry when you save. Until then you can put it back, and leaving without saving keeps it.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(tr('Keep it')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Remove'), style: TextStyle(color: e.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final at = draft.files.indexWhere((x) => x.id == file.id);
    if (at < 0) return;
    draft.files = [...draft.files]..removeAt(at);
    changed();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(tr('Removed “${file.name}”.')),
          action: SnackBarAction(
            label: tr('Put it back'),
            onPressed: () {
              if (draft.files.any((x) => x.id == file.id)) return;
              draft.files = [...draft.files]
                ..insert(at.clamp(0, draft.files.length), file);
              changed();
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      FileThumb(vault: vault, file: file),
      IconButton(
        tooltip: tr('Remove file'),
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: () => _remove(context),
      ),
    ],
  );
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

/// Save decrypted copies: as they are, as PDF / Word (all the files, laid out
/// on A4 like a photocopy, an ID card at its real size) or as PNG / JPEG.
/// It always says first that the copy isn't encrypted.
Future<void> downloadFiles(
  BuildContext context,
  Vault vault,
  List<FileRef> files, {
  String name = '',
}) async {
  final one = files.length == 1;
  final e = Envelope.of(context);
  final fmt = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Save an unprotected copy?'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                "The copy isn't encrypted: any app or person that can open where you save it can see it.",
              ),
              style: TextStyle(color: e.red),
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                one
                    ? 'PDF and Word put the page on A4 like a photocopy; an ID card comes out at its real size.'
                    : 'PDF and Word put all the pages together on A4 like a photocopy; an ID card\'s front and back come out at real size, on one page.',
              ),
              style: TextStyle(color: e.ink3, fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (one)
                  OutlinedButton(
                    onPressed: () => Navigator.pop(c, 'original'),
                    child: Text(tr('As it is')),
                  ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, 'pdf'),
                  child: const Text('PDF'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(c, 'docx'),
                  child: Text(tr('Word')),
                ),
                if (one)
                  OutlinedButton(
                    onPressed: () => Navigator.pop(c, 'png'),
                    child: const Text('PNG'),
                  ),
                if (one)
                  OutlinedButton(
                    onPressed: () => Navigator.pop(c, 'jpeg'),
                    child: const Text('JPEG'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (fmt == null || !context.mounted) return;
  try {
    final base = (name.trim().isNotEmpty ? name.trim() : files.first.name)
        .replaceFirst(RegExp(r'\.[A-Za-z0-9]{1,5}$'), '');
    const kinds = {
      'pdf': ('pdf', 'application/pdf'),
      'docx': (
        'docx',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      ),
      'png': ('png', 'image/png'),
      'jpeg': ('jpg', 'image/jpeg'),
    };
    final Uint8List bytes;
    final String fileName, mime;
    if (fmt == 'original') {
      bytes = await openFile(vault, files.first);
      fileName = files.first.name;
      mime = files.first.mime;
    } else {
      bytes = (await _ch.invokeMethod<Uint8List>('export', {
        'files': [for (final f in files) await openFile(vault, f)],
        'format': fmt,
      }))!;
      fileName = '$base.${kinds[fmt]!.$1}';
      mime = kinds[fmt]!.$2;
    }
    final done = await _ch.invokeMethod<bool>('saveCopy', {
      'bytes': bytes,
      'name': fileName,
      'mime': mime,
    });
    if (done == true && context.mounted) _snack(context, 'Saved.');
  } on FormatException catch (e) {
    if (context.mounted) _snack(context, e.message);
  } on PlatformException catch (e) {
    if (context.mounted) {
      _snack(context, e.message ?? "That file couldn't be saved.");
    }
  }
}

class FileViewerPage extends StatelessWidget {
  final Vault vault;
  final FileRef file;
  const FileViewerPage({super.key, required this.vault, required this.file});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(file.name, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: tr('Download'),
          icon: const Icon(Icons.download_outlined),
          onPressed: () => downloadFiles(context, vault, [file]),
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
        if (files.isNotEmpty) FilesView(vault: vault, entry: entry),
      ],
    );
  }
}

/// The view page's files, on any entry: tap one to open it.
class FilesView extends StatelessWidget {
  final Vault vault;
  final Entry entry;
  const FilesView({super.key, required this.vault, required this.entry});

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              tr('Files'),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: e.ink2,
                fontSize: 13,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => downloadFiles(
                context,
                vault,
                fileRefs(entry),
                name: entry.displayName(),
              ),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text(
                tr(fileRefs(entry).length > 1 ? 'Download all' : 'Download'),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final f in fileRefs(entry))
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
    );
  }
}

/// The edit page's files on an entry that isn't a document (a login's
/// recovery codes, say). The page writes [draft]'s files on save.
class FilesEditor extends StatefulWidget {
  final Vault vault;
  final Entry entry;
  final DocumentDraft draft;
  const FilesEditor({
    super.key,
    required this.vault,
    required this.entry,
    required this.draft,
  });
  @override
  State<FilesEditor> createState() => _FilesEditorState();
}

class _FilesEditorState extends State<FilesEditor> {
  DocumentDraft get d => widget.draft;

  @override
  void initState() {
    super.initState();
    d.files = fileRefs(widget.entry);
  }

  Future<void> _add(String how) async {
    try {
      final added = [
        for (final (name, bytes) in await _getFiles(how))
          await seal(widget.vault, bytes, name),
      ];
      if (added.isNotEmpty) setState(() => d.files = [...d.files, ...added]);
    } on FormatException catch (e) {
      if (mounted) _snack(context, e.message);
    } on PlatformException catch (e) {
      if (mounted) {
        _snack(context, e.message ?? "That file couldn't be opened.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          tr('Files'),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: e.ink2,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          tr(
            "Photos or PDFs that belong with this entry. They're encrypted the moment you add them.",
          ),
          style: TextStyle(color: e.ink3, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final f in d.files)
              RemovableThumb(
                vault: widget.vault,
                file: f,
                draft: d,
                changed: () {
                  if (mounted) setState(() {});
                },
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
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
          ],
        ),
        const SizedBox(height: 12),
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
      // Scanning: your camera app (its own flash and exposure), then MyVault's crop screen.
      final got = how == 'scan'
          ? await scanPages(context)
          : await _getFiles(how);
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
            'Scan both sides of a card: take the photo with your camera (use its flash if it\'s dark), then drag the corners onto the card\'s. Files are encrypted the moment you add them, and MyVault reads the details from all of them together, on this phone.',
          ),
          style: TextStyle(color: e.ink3, fontSize: 12.5),
        ),
        const SizedBox(height: 4),
        Text(
          tr(
            'Photo too bright or shiny? Tilt the card away from the light, or turn the flash off.',
          ),
          style: TextStyle(color: e.ink3, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final f in d.files)
              RemovableThumb(
                vault: widget.vault,
                file: f,
                draft: d,
                changed: () {
                  if (mounted) setState(() {});
                },
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
