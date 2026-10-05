/// Vault model + persistence for the Android app. Reads/writes the SAME
/// encrypted file format as the Windows app (see VAULT_FORMAT.md), so the two
/// stay compatible and can later sync over LAN.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'crypto.dart';

double _now() => DateTime.now().millisecondsSinceEpoch / 1000.0;

const kinds = ['login', 'api', 'ssh', 'note', 'document'];
const searchableFields = [
  'service',
  'client_id',
  'endpoint',
  'host',
  'ssh_user',
  'fingerprint',
];

class Entry {
  String id;
  String kind; // login | api | ssh | note
  String title, website, app, username, email, password;
  String region, age, gender, phone, notes;
  Map<String, String> custom;
  Map<String, String> fields; // kind-specific values (see kinds.dart)
  Map<String, dynamic> passwordPolicy;
  double createdAt, updatedAt;
  bool deleted;

  Entry({
    String? id,
    this.kind = 'login',
    this.title = '',
    this.website = '',
    this.app = '',
    this.username = '',
    this.email = '',
    this.password = '',
    this.region = '',
    this.age = '',
    this.gender = '',
    this.phone = '',
    this.notes = '',
    Map<String, String>? custom,
    Map<String, String>? fields,
    Map<String, dynamic>? passwordPolicy,
    double? createdAt,
    double? updatedAt,
    this.deleted = false,
  }) : id = id ?? _uuid(),
       custom = custom ?? {},
       fields = fields ?? {},
       passwordPolicy = passwordPolicy ?? {'length': 16},
       createdAt = createdAt ?? _now(),
       updatedAt = updatedAt ?? _now();

  void touch() => updatedAt = _now();

  /// A separate copy, to edit without touching this one until it's saved.
  Entry copy() =>
      Entry.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);

  /// Takes every value of [o] (an edited copy of this entry).
  void copyFrom(Entry o) {
    kind = o.kind;
    title = o.title;
    website = o.website;
    app = o.app;
    username = o.username;
    email = o.email;
    password = o.password;
    region = o.region;
    age = o.age;
    gender = o.gender;
    phone = o.phone;
    notes = o.notes;
    custom = o.custom;
    fields = o.fields;
    passwordPolicy = o.passwordPolicy;
    deleted = o.deleted;
  }

  String displayName() {
    for (final v in [
      title,
      website,
      app,
      fields['service'] ?? '',
      fields['host'] ?? '',
      username,
      email,
    ]) {
      if (v.trim().isNotEmpty) return v;
    }
    return '(untitled)';
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [
      title,
      website,
      app,
      username,
      email,
      if (kind != 'note') notes, // a secure note's body is secret
      ...custom.keys,
      ...custom.values,
      for (final k in searchableFields) fields[k] ?? '',
    ].join(' ').toLowerCase();
    return hay.contains(q);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'title': title,
    'website': website,
    'app': app,
    'username': username,
    'email': email,
    'password': password,
    'region': region,
    'age': age,
    'gender': gender,
    'phone': phone,
    'notes': notes,
    'custom': custom,
    'fields': fields,
    'password_policy': passwordPolicy,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted': deleted,
  };

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
    id: j['id'] as String?,
    kind: kinds.contains(j['kind']) ? j['kind'] as String : 'login',
    title: (j['title'] ?? '') as String,
    website: (j['website'] ?? '') as String,
    app: (j['app'] ?? '') as String,
    username: (j['username'] ?? '') as String,
    email: (j['email'] ?? '') as String,
    password: (j['password'] ?? '') as String,
    region: (j['region'] ?? '') as String,
    age: (j['age'] ?? '') as String,
    gender: (j['gender'] ?? '') as String,
    phone: (j['phone'] ?? '') as String,
    notes: (j['notes'] ?? '') as String,
    custom: ((j['custom'] ?? {}) as Map).map((k, v) => MapEntry('$k', '$v')),
    fields: ((j['fields'] ?? {}) as Map).map((k, v) => MapEntry('$k', '$v')),
    passwordPolicy: ((j['password_policy'] ?? {'length': 16}) as Map)
        .cast<String, dynamic>(),
    createdAt: (j['created_at'] as num?)?.toDouble(),
    updatedAt: (j['updated_at'] as num?)?.toDouble(),
    deleted: (j['deleted'] ?? false) as bool,
  );
}

const historyKeep = 10;

/// An email address with a name, an @ and a full domain (gmail.com, not gmail).
final _email = RegExp(r'^[^@\s]+@[^@\s.]+(\.[^@\s.]+)*\.[^@\s.]{2,}$');

/// Why the entry's email address can't be right, or '' (same rule as the PC).
String emailProblem(Entry e) {
  for (final v in [e.email, e.fields['email'] ?? '']) {
    if (v.trim().isNotEmpty && !_email.hasMatch(v.trim())) {
      return '“${v.trim()}” isn\'t a complete email address. It needs a name, @ and the full domain, such as name@gmail.com.';
    }
  }
  return '';
}

/// When a login's password changes, the old one goes into its history
/// (fields['password_history'], newest first). Same as keep_old_password() on the PC.
void keepOldPassword(Entry e, String old) {
  if (old.isEmpty || old == e.password) return;
  var past = <dynamic>[];
  try {
    past = jsonDecode(e.fields['password_history'] ?? '[]') as List;
  } catch (_) {}
  e.fields['password_history'] = jsonEncode(
    [
      {'password': old, 'until': _now()},
      ...past,
    ].take(historyKeep).toList(),
  );
}

/// A login's earlier passwords, newest first: (password, until).
List<(String, double)> passwordHistory(Entry e) {
  try {
    return [
      for (final h in jsonDecode(e.fields['password_history'] ?? '[]') as List)
        ('${h['password']}', (h['until'] as num).toDouble()),
    ];
  } catch (_) {
    return [];
  }
}

class Vault {
  final String path;
  String password;
  String deviceId;
  double updatedAt;
  List<Entry> entries;

  Vault(this.path, this.password)
    : deviceId = _uuid(),
      updatedAt = _now(),
      entries = [];

  static Vault open(String path, String password) {
    final bytes = File(path).readAsBytesSync();
    final clear = decryptBytes(Uint8List.fromList(bytes), password);
    final data = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    final v = Vault(path, password);
    v.deviceId = (data['device_id'] ?? v.deviceId) as String;
    v.updatedAt = (data['updated_at'] as num?)?.toDouble() ?? _now();
    v.entries = ((data['entries'] ?? []) as List)
        .map((e) => Entry.fromJson(e as Map<String, dynamic>))
        .toList();
    return v;
  }

  static Vault create(String path, String password) {
    final v = Vault(path, password);
    v.save();
    return v;
  }

  void save() {
    updatedAt = _now();
    final payload = {
      'content_version': 2,
      'device_id': deviceId,
      'updated_at': updatedAt,
      'entries': entries.map((e) => e.toJson()).toList(),
    };
    final blob = encryptBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      password,
    );
    // Atomic write: temp then rename.
    final tmp = File('$path.tmp');
    tmp.writeAsBytesSync(blob, flush: true);
    if (File(path).existsSync()) File(path).deleteSync();
    tmp.renameSync(path);
    onSave?.call();
  }

  /// Called after every save (the app hands reminders to Android).
  void Function()? onSave;

  /// Restore from a paper backup. Unlike sync, a backup copy beats a local
  /// deletion even when the deletion is newer (restoring means "bring these
  /// back"); a restored entry is touched so the next sync spreads it.
  /// Mirrors restore_entries() in myvault/sync.py. Returns how many changed.
  int restoreIn(List<Entry> backup) {
    final byId = {for (final e in entries) e.id: e};
    var changed = 0;
    for (final e in backup) {
      final cur = byId[e.id];
      if (cur == null || e.updatedAt > cur.updatedAt) {
        byId[e.id] = e;
        changed++;
      } else if (cur.deleted) {
        e.deleted = false;
        e.touch();
        byId[e.id] = e;
        changed++;
      }
    }
    entries = byId.values.toList();
    save();
    return changed;
  }

  /// Merge entries from sync: newest updated_at per id wins.
  /// Returns how many entries were added or changed here.
  int mergeIn(List<Entry> incoming) {
    final byId = {for (final e in entries) e.id: e};
    var changed = 0;
    for (final e in incoming) {
      final cur = byId[e.id];
      if (cur == null || e.updatedAt > cur.updatedAt) {
        byId[e.id] = e;
        changed++;
      }
    }
    entries = byId.values.toList();
    save();
    return changed;
  }

  void changePassword(String newPassword) {
    password = newPassword;
    save();
  }

  List<Entry> activeEntries() => entries.where((e) => !e.deleted).toList();

  List<Entry> search(String query) {
    final items = activeEntries().where((e) => e.matches(query)).toList();
    items.sort(
      (a, b) => a.displayName().toLowerCase().compareTo(
        b.displayName().toLowerCase(),
      ),
    );
    return items;
  }

  Entry? getById(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  void add(Entry e) {
    entries.add(e);
    save();
  }

  void update(Entry e) {
    e.touch();
    save();
  }

  void deleteById(String id) {
    final e = getById(id);
    if (e != null) {
      e.deleted = true;
      e.password = '';
      e.fields = {};
      e.touch();
      save();
    }
  }
}

// Minimal UUID v4 (random) — good enough for stable entry ids.
String _uuid() {
  final r = _rng;
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final s = List.generate(16, hex).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-'
      '${s.substring(16, 20)}-${s.substring(20)}';
}

final _rng = Random.secure();
