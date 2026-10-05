/// Personal documents: the phone side of myvault/docs.py. Same file format,
/// same reading rules, same reminders. Keep the two in step.
///
/// * Each photo or PDF is stored next to the vault as its own encrypted file:
///   nonce || AES-256-GCM(file, key, aad = file id), with a random key kept
///   inside the vault entry. Files move between devices exactly as stored.
/// * readDetails() pulls type, holder, number and dates from a document's text:
///   from the machine-readable zone (checked with its check digits) or from
///   dates next to words like "expiry".
/// * Reminders go to Android as {key, on, expires, entry, days, text}: the text
///   says only the type (or the name you chose) and the time left.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pointycastle/export.dart';

import 'l10n.dart';
import 'vault.dart';

// Document types and their fields: assets/doc_types.json, the same file as the
// Windows app's myvault/ui/doc_types.json. Loaded once at start (loadDocSchema).
Map<String, dynamic> _schema = {
  'fields': <String, dynamic>{},
  'types': <String, dynamic>{},
};
Future<void> loadDocSchema() async {
  _schema =
      jsonDecode(await rootBundle.loadString('assets/doc_types.json'))
          as Map<String, dynamic>;
}

Map<String, dynamic> get docSchemaFields =>
    _schema['fields'] as Map<String, dynamic>;
Map<String, dynamic> get _typeMap => _schema['types'] as Map<String, dynamic>;
List<(String, String)> get docTypes => [
  ('', 'Choose a type'),
  for (final t in _typeMap.entries) (t.key, '${(t.value as Map)['label']}'),
];
String typeLabel(String? k) =>
    '${(_typeMap[k ?? ''] as Map?)?['label'] ?? 'Document'}';
List<String> typeFieldKeys(String type) => [
  for (final k
      in ((_typeMap[type] ?? _typeMap['other'] ?? {'fields': []})
              as Map)['fields']
          as List)
    '$k',
];

/// The field's name on this type of document ("Owner" on a car registration).
String docLabel(String key, String type) => key == 'doc_type'
    ? 'Type'
    : '${((_typeMap[type] as Map?)?['labels'] as Map?)?[key] ?? (docSchemaFields[key] as Map?)?['label'] ?? key}';

const leads = <(int, String)>[
  (1, '1 day'),
  (3, '3 days'),
  (7, '1 week'),
  (14, '2 weeks'),
  (30, '1 month'),
  (60, '2 months'),
  (90, '3 months'),
  (180, '6 months'),
  (365, '1 year'),
];
String leadLabel(int d) =>
    leads.firstWhere((l) => l.$1 == d, orElse: () => (d, '$d days')).$2;

const maxFile = 20 * 1024 * 1024;

// ---- the entry's document fields ------------------------------------------------
class FileRef {
  final String id, name, mime, key;
  final int size;
  FileRef(this.id, this.name, this.mime, this.size, this.key);
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mime': mime,
    'size': size,
    'key': key,
  };
  static FileRef? fromJson(dynamic j) {
    if (j is! Map) return null;
    final id = '${j['id'] ?? ''}';
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id) ||
        '${j['key'] ?? ''}'.isEmpty) {
      return null;
    }
    return FileRef(
      id,
      '${j['name'] ?? 'document'}',
      '${j['mime'] ?? ''}',
      (j['size'] as num?)?.toInt() ?? 0,
      '${j['key']}',
    );
  }

  bool get isPdf => mime == 'application/pdf';
}

List<FileRef> fileRefs(Entry e) {
  try {
    return [
      for (final j in (jsonDecode(e.fields['files'] ?? '[]') as List))
        ?FileRef.fromJson(j),
    ];
  } catch (_) {
    return [];
  }
}

void setFileRefs(Entry e, List<FileRef> refs) {
  if (refs.isEmpty) {
    e.fields.remove('files');
  } else {
    e.fields['files'] = jsonEncode(refs.map((r) => r.toJson()).toList());
  }
}

List<int> remindDays(Entry e) {
  final out = <int>{};
  for (final p in (e.fields['remind'] ?? '').split(',')) {
    final n = int.tryParse(p.trim());
    if (n != null && n > 0 && n <= 3650) out.add(n);
  }
  return out.toList()..sort((a, b) => b - a);
}

DateTime? parseDay(String? s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch((s ?? '').trim());
  if (m == null) return null;
  final d = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  return d.month == int.parse(m[2]!) ? d : null;
}

String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

int daysLeft(String iso, [DateTime? today]) {
  final t = today ?? DateTime.now();
  return parseDay(iso)!.difference(DateTime(t.year, t.month, t.day)).inDays;
}

// ---- encrypted files --------------------------------------------------------------
Directory filesDir(Vault v) {
  final d = Directory('${File(v.path).parent.path}/files');
  if (!d.existsSync()) d.createSync(recursive: true);
  return d;
}

File _blob(Vault v, String id) {
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
    throw const FormatException('bad file id');
  }
  return File('${filesDir(v).path}/$id.bin');
}

String sniffMime(Uint8List b) {
  bool at(List<int> sig, [int off = 0]) =>
      b.length >= off + sig.length &&
      List.generate(sig.length, (i) => b[off + i] == sig[i]).every((x) => x);
  if (at([0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (at([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return 'image/png';
  if (at([0x25, 0x50, 0x44, 0x46])) return 'application/pdf';
  if (at([0x52, 0x49, 0x46, 0x46]) && at([0x57, 0x45, 0x42, 0x50], 8)) {
    return 'image/webp';
  }
  return '';
}

Uint8List _gcm(
  bool enc,
  Uint8List key,
  Uint8List nonce,
  String id,
  Uint8List data,
) {
  final c = GCMBlockCipher(AESEngine())
    ..init(
      enc,
      AEADParameters(
        KeyParameter(key),
        128,
        nonce,
        Uint8List.fromList(utf8.encode(id)),
      ),
    );
  return c.process(data);
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Encrypt and keep a document file; returns the reference for the entry.
/// Raises FormatException with a message for people.
Future<FileRef> seal(Vault v, Uint8List data, String name) async {
  if (data.length > maxFile) {
    throw const FormatException('That file is over 20 MB.');
  }
  final mime = sniffMime(data);
  if (mime.isEmpty) {
    throw const FormatException(
      'Only photos (JPG, PNG, WebP) and PDFs can be added.',
    );
  }
  final rnd = Random.secure();
  Uint8List bytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
  final id = _hex(bytes(16)), key = bytes(32), nonce = bytes(12);
  final ct = await Isolate.run(() => _gcm(true, key, nonce, id, data));
  final f = _blob(v, id);
  final tmp = File('${f.path}.part');
  await tmp.writeAsBytes([...nonce, ...ct], flush: true);
  await tmp.rename(f.path);
  return FileRef(
    id,
    name.split(RegExp(r'[\\/]')).last.isEmpty
        ? 'document'
        : name.split(RegExp(r'[\\/]')).last,
    mime,
    data.length,
    base64.encode(key),
  );
}

bool haveFile(Vault v, String id) {
  try {
    return _blob(v, id).existsSync();
  } on FormatException {
    return false;
  }
}

Uint8List readBlob(Vault v, String id) => _blob(v, id).readAsBytesSync();

/// The plain file. Throws FormatException if it's missing or doesn't open.
Future<Uint8List> openFile(Vault v, FileRef r, [Uint8List? blob]) async {
  if (blob == null) {
    final f = _blob(v, r.id);
    if (!f.existsSync()) {
      throw const FormatException(
        "That file isn't on this device yet. Sync with the device that has it.",
      );
    }
    blob = await f.readAsBytes();
  }
  final b = blob;
  try {
    final key = base64.decode(r.key);
    return await Isolate.run(
      () => _gcm(false, key, b.sublist(0, 12), r.id, b.sublist(12)),
    );
  } catch (_) {
    throw const FormatException('That file is damaged.');
  }
}

/// Keep a file received from another device, after checking it opens.
Future<void> storeBlob(Vault v, FileRef r, Uint8List blob) async {
  await openFile(v, r, blob);
  final f = _blob(v, r.id);
  final tmp = File('${f.path}.part');
  await tmp.writeAsBytes(blob, flush: true);
  await tmp.rename(f.path);
}

/// Files of live documents, by id.
Map<String, FileRef> liveRefs(Vault v) => {
  for (final e in v.activeEntries())
    if (e.kind == 'document')
      for (final r in fileRefs(e)) r.id: r,
};

/// Delete stored files no live document refers to.
int cleanup(Vault v) {
  final keep = liveRefs(v).keys.toSet();
  var gone = 0;
  for (final f in filesDir(v).listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (name.endsWith('.bin') &&
        !keep.contains(name.substring(0, name.length - 4))) {
      f.deleteSync();
      gone++;
    }
  }
  return gone;
}

// ---- reminders -------------------------------------------------------------------
String reminderText(String name, String type, int days) {
  final n = name.isNotEmpty ? name : tr(typeLabel(type));
  return days == 0
      ? tr('$n expires today.')
      : tr('$n expires in ${leadLabel(days)}.');
}

List<Map<String, dynamic>> schedule(Iterable<Entry> entries) {
  final out = <Map<String, dynamic>>[];
  for (final e in entries) {
    if (e.deleted || e.kind != 'document') continue;
    final expires = parseDay(e.fields['expires']);
    final days = remindDays(e);
    if (expires == null || days.isEmpty) continue;
    final name = (e.fields['remind_name'] ?? '').trim();
    final type = e.fields['doc_type'] ?? 'other';
    for (final d in [...days, 0]) {
      out.add({
        'key': '${e.id}:${isoDay(expires)}:$d',
        'entry': e.id,
        'on': isoDay(expires.subtract(Duration(days: d))),
        'expires': isoDay(expires),
        'days': d,
        'text': reminderText(
          name.length > 40 ? name.substring(0, 40) : name,
          type,
          d,
        ),
      });
    }
  }
  out.sort((a, b) => (a['on'] as String).compareTo(b['on'] as String));
  return out;
}

// ---- reading details from a document's text ---------------------------------------
const _w = [7, 3, 1];
String _fixDigits(String s) {
  const from = 'OQDIZSBGL', to = '001125861';
  return s.split('').map((c) {
    final i = from.indexOf(c);
    return i < 0 ? c : to[i];
  }).join();
}

int _check(String s) {
  var t = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    final v = c >= 48 && c <= 57 ? c - 48 : (c >= 65 && c <= 90 ? c - 55 : 0);
    t += v * _w[i % 3];
  }
  return t % 10;
}

String? _field(String s, String digit, bool numeric) {
  for (final (f, d) in [
    (s, digit),
    (numeric ? _fixDigits(s) : s, _fixDigits(digit)),
  ]) {
    final n = int.tryParse(d);
    if (n != null && _check(f) == n) return f;
  }
  return null;
}

String _yymmdd(String s, bool future) {
  final y = int.tryParse(s.substring(0, 2)),
      m = int.tryParse(s.substring(2, 4));
  final d = int.tryParse(s.substring(4, 6));
  if (y == null || m == null || d == null || m < 1 || m > 12 || d < 1) {
    return '';
  }
  final now = DateTime.now().year % 100;
  final year = future || y <= now ? 2000 + y : 1900 + y;
  final date = DateTime(year, m, d);
  return date.month == m ? isoDay(date) : '';
}

String _title(String w) =>
    w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase();

String _name(String s) {
  final t = s.replaceAll(RegExp(r'^<+|<+$'), '');
  final i = t.indexOf('<<');
  final surname = i < 0 ? t : t.substring(0, i),
      given = i < 0 ? '' : t.substring(i + 2);
  String words(String x) =>
      x.split('<').where((w) => w.isNotEmpty).map(_title).join(' ');
  return [words(given), words(surname)].where((x) => x.isNotEmpty).join(' ');
}

String _kind(String code) => switch (code.isEmpty ? '' : code[0]) {
  'P' => 'passport',
  'V' => 'visa',
  'I' || 'A' || 'C' => 'id_card',
  _ => 'other',
};

Map<String, dynamic> _td23(List<String> b) {
  final l1 = b[0], l2 = b[1];
  final out = <String, dynamic>{
    'doc_type': _kind(l1.substring(0, 2)),
    'country': l1.substring(2, 5).replaceAll('<', ''),
    'holder': _name(l1.substring(5)),
    'nationality': l2.substring(10, 13).replaceAll('<', ''),
    'gender': 'MF'.contains(l2[20]) ? l2[20] : '',
  };
  final number = _field(l2.substring(0, 9), l2[9], false);
  final birth = _field(l2.substring(13, 19), l2[19], true);
  final expiry = _field(l2.substring(21, 27), l2[27], true);
  if (number != null) out['number'] = number.replaceAll('<', '');
  if (birth != null) out['birth_date'] = _yymmdd(birth, false);
  if (expiry != null) out['expires'] = _yymmdd(expiry, true);
  return out;
}

Map<String, dynamic> _td1(List<String> b) {
  final l1 = b[0], l2 = b[1], l3 = b[2];
  final out = <String, dynamic>{
    'doc_type': _kind(l1.substring(0, 2)),
    'country': l1.substring(2, 5).replaceAll('<', ''),
    'holder': _name(l3),
    'nationality': l2.substring(15, 18).replaceAll('<', ''),
    'gender': 'MF'.contains(l2[7]) ? l2[7] : '',
  };
  final number = _field(l1.substring(5, 14), l1[14], false);
  final birth = _field(l2.substring(0, 6), l2[6], true);
  final expiry = _field(l2.substring(8, 14), l2[14], true);
  if (number != null) out['number'] = number.replaceAll('<', '');
  if (birth != null) out['birth_date'] = _yymmdd(birth, false);
  if (expiry != null) out['expires'] = _yymmdd(expiry, true);
  return out;
}

Map<String, dynamic> readMrz(String text) {
  final lines = <String>[];
  for (final raw in text.toUpperCase().split('\n')) {
    final l = raw.replaceAll(RegExp(r'\s+'), '').replaceAll('«', '<');
    if (l.length >= 28 &&
        RegExp(r'^[A-Z0-9<]+$').hasMatch(l) &&
        '<'.allMatches(l).length >= 2) {
      lines.add(l);
    }
  }
  for (final (width, rows) in [(44, 2), (36, 2), (30, 3)]) {
    final fit = [
      for (final l in lines)
        if ((l.length - width).abs() <= 3)
          l.padRight(width, '<').substring(0, width),
    ];
    for (var i = 0; i + rows <= fit.length; i++) {
      final block = fit.sublist(i, i + rows);
      final got = rows == 3 ? _td1(block) : _td23(block);
      if ('${got['expires'] ?? ''}'.isNotEmpty) return {...got, 'how': 'mrz'};
    }
  }
  return {};
}

// The same rules as myvault/docs.py: keep the two in step (the shared cases in
// test_fixtures/read_cases.json check both).
const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};
RegExp _rx(String s) => RegExp(s, caseSensitive: false);
final _expiry = _rx(
  r'expir|valid\s*(until|thru|through|to)|end\s*date|انتهاء|صالح[ةه]?\s*(حتى|لغاية)|ينتهي',
);
final _issue = _rx(r'issue|start\s*date|إصدار|الإصدار|تحرير');
final _birth = _rx(r'birth|born|\bdob\b|ميلاد|الولادة');
final _number = _rx(
  r'(?:\bno\b\.?|number|\bnum\b\.?|رقم)\s*[:.#]?\s*([A-Z0-9][A-Z0-9-]{4,17})',
);
final _notNumber = _rx(
  r'plate|phone|\btel\b|mobile|chassis|\bvin\b|اللوحة|هاتف',
);
// Most specific first. "Residence" alone is often an ID card's address line, so a
// residence permit has to say so.
const _residence =
    r'residen(ce|cy|t)\s*(permit|card)|تصريح\s*إقامة|(?<![ء-ي])إقامة(?![ء-ي])';
final _types = [
  ('passport', r'\bpassport\b|جواز\s*(ال)?سفر'),
  ('visa', r'\bvisa\b|تأشيرة'),
  (
    'driving_license',
    r"driv\w*\s*licen[cs]e|driver'?s\s*licen|رخصة\s*(ال)?قيادة|رخصة\s*سوق",
  ),
  (
    'car_registration',
    r'vehicle\s*(registration|licen[cs]e)|registration\s*certificate|\bchassis\b|رخصة\s*(ال)?مركبة|رخصة\s*سيارة|تسجيل\s*(ال)?مركبة',
  ),
  ('residence', _residence),
  (
    'id_card',
    r'identity|national\s*(id|number|no)|\bid\s*card|personal\s*(id|card|number)|هوية|بطاقة\s*(ال)?(شخصية|تعريف)|الرقم\s*الوطني',
  ),
  (
    'rental',
    r'\blease\b|tenan|rental\s*(agreement|contract)|إيجار|استئجار|المؤجر|المستأجر',
  ),
  ('insurance', r'insurance|\bpolicy\b|تأمين'),
];
// Details read from "Label: value" lines (the value may also be on the next line).
const _labels = {
  'holder': r'\b(full\s*)?name\b|الاسم',
  'nationality': r'nationality|الجنسية',
  'gender': r'\bsex\b|gender|الجنس',
  'birth_place':
      r'place\s*of\s*birth|birth\s*place|مكان\s*(ال)?(ولادة|الميلاد)',
  'address': r'address|place\s*of\s*residence|العنوان|مكان\s*الإقامة',
  'landlord': r'landlord|lessor|المؤجر',
  'employer': r'sponsor|employer|الكفيل|صاحب\s*العمل',
  'insurer': r'insurer|insurance\s*company|شركة\s*التأمين',
  'licence_class': r'\bclass\b|\bcategory\b|الفئة',
  'plate': r'plate(\s*(\bno\b\.?|number))?|رقم\s*اللوحة',
  'vehicle': r'make\s*(and|&)\s*model|\bmodel\b|الطراز',
  'visa_type': r'visa\s*type|type\s*of\s*visa|نوع\s*التأشيرة',
  'rent': r'monthly\s*rent|rent\s*amount|قيمة\s*الإيجار|الأجرة',
  'country':
      r'issuing\s*(country|authority|state)|issued\s*by|place\s*of\s*issue|جهة\s*الإصدار|مكان\s*الإصدار',
  'phone': r'phone|mobile|\btel\b|هاتف|موبايل|جوال',
};

/// The value after a label on its line, or on the next line if it's alone.
String _after(String label, List<String> lines) {
  final rx = _rx(label);
  for (var i = 0; i < lines.length; i++) {
    final m = rx.firstMatch(lines[i]);
    if (m == null) continue;
    var rest = lines[i]
        .substring(m.end)
        .replaceFirst(RegExp(r'^[\s:：.#\-–]+'), '')
        .trim();
    if (rest.isEmpty && i + 1 < lines.length) rest = lines[i + 1].trim();
    if (rest.isNotEmpty) return rest.length > 80 ? rest.substring(0, 80) : rest;
  }
  return '';
}

String _clean(String key, String v) {
  if (key == 'gender') {
    final g = v.trim().toUpperCase();
    final c = g.isEmpty ? '' : g[0];
    return c == 'M' || v.contains('ذكر')
        ? 'M'
        : (c == 'F' || v.contains('أنثى') ? 'F' : '');
  }
  if (key == 'phone') {
    final digits = v.replaceAll(RegExp(r'[^\d+]'), '');
    final n = digits.replaceAll('+', '').length;
    return n >= 7 && n <= 15 ? digits : '';
  }
  const noDigits = {
    'holder',
    'nationality',
    'birth_place',
    'landlord',
    'employer',
    'insurer',
  };
  if (noDigits.contains(key) && RegExp(r'\d').hasMatch(v)) return '';
  return v;
}

Iterable<(int, String)> _dates(String text) sync* {
  final pats = <(RegExp, List<String?> Function(Match))>[
    (
      RegExp(r'\b(\d{4})[./-](\d{1,2})[./-](\d{1,2})\b'),
      (m) => [m[1], m[2], m[3]],
    ),
    (
      RegExp(r'\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b'),
      (m) => [m[3], m[2], m[1]],
    ),
    (
      RegExp(r'\b(\d{1,2})\s*([A-Za-z]{3})[a-z]*\.?,?\s*(\d{4})\b'),
      (m) => [m[3], '${_months[m[2]!.toLowerCase()] ?? ''}', m[1]],
    ),
    (
      RegExp(r'\b([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})\b'),
      (m) => [m[3], '${_months[m[1]!.toLowerCase()] ?? ''}', m[2]],
    ),
  ];
  for (final (rx, order) in pats) {
    for (final m in rx.allMatches(text)) {
      final p = order(m);
      var y = int.tryParse(p[0] ?? ''), mo = int.tryParse(p[1] ?? '');
      var d = int.tryParse(p[2] ?? '');
      if (y == null || mo == null || d == null) continue;
      if (mo > 12 && d <= 12) (mo, d) = (d, mo); // month-first (US) date
      if (mo < 1 || mo > 12 || d < 1) continue;
      final date = DateTime(y, mo, d);
      if (date.month == mo) yield (m.start, isoDay(date));
    }
  }
}

/// Best guesses from a document's text: one string per page or side (an ID
/// card's front and back). The person checks them before saving.
///
/// Dates follow the order every document has: birth < issue < expiry. A label
/// next to a date is used when it fits that order; when it doesn't, the order
/// decides. A birth date is never taken for an expiry date.
Map<String, dynamic> readDetails(Object texts, {DateTime? today}) {
  final t = today ?? DateTime.now();
  var text = texts is List ? texts.join('\n') : '$texts';
  const ar = '٠١٢٣٤٥٦٧٨٩', fa = '۰۱۲۳۴۵۶۷۸۹';
  text = text.split('').map((c) {
    final i = ar.indexOf(c), j = fa.indexOf(c);
    return i >= 0 ? '$i' : (j >= 0 ? '$j' : c);
  }).join();
  final lines = text.split('\n');
  final found = readMrz(text);
  if (found.isEmpty) {
    found['how'] = 'text';
    for (final (kind, rx) in _types) {
      if (_rx(rx).hasMatch(text)) {
        found['doc_type'] = kind;
        break;
      }
    }
  } else if (found['doc_type'] == 'id_card' && _rx(_residence).hasMatch(text)) {
    found['doc_type'] = 'residence';
  }
  for (final MapEntry(:key, :value) in _labels.entries) {
    if ('${found[key] ?? ''}'.isEmpty) {
      found[key] = _clean(key, _after(value, lines));
    }
  }
  found['email'] =
      RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+').firstMatch(text)?[0] ?? '';
  found['vin'] =
      RegExp(
        r'\b(?=[A-HJ-NPR-Z0-9]*\d)(?=[A-HJ-NPR-Z0-9]*[A-Z])[A-HJ-NPR-Z0-9]{17}\b',
      ).firstMatch(text)?[0] ??
      '';

  // ---- dates
  final seen = <(String, String?)>[];
  for (final (pos, iso) in _dates(text)) {
    final y = int.parse(iso.substring(0, 4));
    if (y < 1900 || y > t.year + 30) continue;
    final before = text.substring(max(0, pos - 50), pos);
    (int, String)? best;
    for (final (label, rx) in [
      ('expires', _expiry),
      ('issued', _issue),
      ('birth', _birth),
    ]) {
      for (final m in rx.allMatches(before)) {
        if (best == null || m.end > best.$1) best = (m.end, label);
      }
    }
    seen.add((iso, best?.$2));
  }
  String? first(String label) {
    for (final (d, l) in seen) {
      if (l == label) return d;
    }
    return null;
  }

  final days = {for (final (d, _) in seen) d}.toList()..sort();
  final now = isoDay(t);
  final old = isoDay(DateTime(t.year - 12, t.month, t.day));
  final recent = isoDay(DateTime(t.year - 15, t.month, t.day));
  String? birth = found['birth_date'] as String? ?? first('birth');
  if (birth != null && birth.compareTo(now) > 0) birth = null;
  if (birth == null && days.isNotEmpty && days.first.compareTo(old) <= 0) {
    birth = days.first;
  }
  bool afterBirth(String d) =>
      d != birth && (birth == null || d.compareTo(birth) > 0);
  String? expires = found['expires'] as String?;
  if (expires == null) {
    final labelled = first('expires');
    if (labelled != null && afterBirth(labelled)) {
      expires = labelled;
    } else {
      final later = [
        for (final d in days)
          if (afterBirth(d) && d.compareTo(recent) >= 0) d,
      ];
      if (later.isNotEmpty) {
        expires = later.last;
        found['guessed'] = true;
      }
    }
  }
  String? issued = first('issued');
  if (!(issued != null &&
      afterBirth(issued) &&
      (expires == null || issued.compareTo(expires) < 0))) {
    final before = [
      for (final d in days)
        if (afterBirth(d) &&
            d.compareTo(now) <= 0 &&
            expires != null &&
            d.compareTo(expires) < 0)
          d,
    ];
    issued = before.isEmpty ? null : before.last;
  }
  found
    ..['birth_date'] = birth
    ..['expires'] = expires
    ..['issued'] = issued;

  // ---- the document's number
  if ('${found['number'] ?? ''}'.isEmpty) {
    for (final m in _number.allMatches(text)) {
      final pre = text.substring(max(0, m.start - 14), m.start);
      if (!_notNumber.hasMatch(pre) && RegExp(r'\d').hasMatch(m[1]!)) {
        found['number'] = m[1];
        break;
      }
    }
  }
  if ('${found['number'] ?? ''}'.isEmpty) {
    // unlabelled: a national number or a passport-style one
    final m = RegExp(
      r'(?<![\d+])(?:[129]\d{9}|\b[A-Z]{1,2}\d{6,8})(?![\dA-Z])',
    ).firstMatch(text);
    if (m != null) found['number'] = m[0];
  }
  found.removeWhere((k, v) => v == null || v == '');
  return found;
}
