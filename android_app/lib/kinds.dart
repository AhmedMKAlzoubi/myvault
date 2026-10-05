/// Entry kinds and their fields. Must match KINDS in myvault/ui/app.js.
library;

import 'package:flutter/material.dart';

import 'docs.dart';
import 'l10n.dart';
import 'vault.dart';

class FieldDef {
  final String key, label;
  final bool top, secret, multi, mono, gen;
  final TextInputType? type;

  /// A choice from a list (value, label), e.g. a document's type.
  final List<(String, String)>? options;

  /// A day, kept as YYYY-MM-DD and picked from a calendar.
  final bool date;
  const FieldDef(
    this.key,
    this.label, {
    this.top = false,
    this.secret = false,
    this.multi = false,
    this.mono = false,
    this.gen = false,
    this.type,
    this.options,
    this.date = false,
  });

  String read(Entry e) => (top ? _top(e)[key] : e.fields[key]) ?? '';

  void write(Entry e, String v) {
    if (!top) {
      if (v.isEmpty) {
        e.fields.remove(key);
      } else {
        e.fields[key] = v;
      }
      return;
    }
    switch (key) {
      case 'website':
        e.website = v.trim();
      case 'username':
        e.username = v.trim();
      case 'email':
        e.email = v.trim();
      case 'password':
        e.password = v;
      case 'app':
        e.app = v.trim();
      case 'phone':
        e.phone = v.trim();
      case 'region':
        e.region = v.trim();
      case 'age':
        e.age = v.trim();
      case 'gender':
        e.gender = v.trim();
      case 'notes':
        e.notes = v;
    }
  }

  static Map<String, String> _top(Entry e) => {
    'website': e.website,
    'username': e.username,
    'email': e.email,
    'password': e.password,
    'app': e.app,
    'phone': e.phone,
    'region': e.region,
    'age': e.age,
    'gender': e.gender,
    'notes': e.notes,
  };
}

class KindDef {
  final String label, plural, desc;
  final IconData icon;
  final List<FieldDef> fields, more;
  const KindDef(
    this.label,
    this.plural,
    this.desc,
    this.icon,
    this.fields, [
    this.more = const [],
  ]);
}

const kindDefs = <String, KindDef>{
  'login': KindDef(
    'Login',
    'Logins',
    'A website or app sign-in.',
    Icons.key_outlined,
    [
      FieldDef('website', 'Website', top: true, type: TextInputType.url),
      FieldDef('username', 'Username', top: true),
      FieldDef('email', 'Email', top: true, type: TextInputType.emailAddress),
      FieldDef('password', 'Password', top: true, secret: true, gen: true),
    ],
    [
      FieldDef('app', 'App name', top: true),
      FieldDef('phone', 'Phone', top: true, type: TextInputType.phone),
      FieldDef('region', 'Region / country', top: true),
      FieldDef('age', 'Age', top: true, type: TextInputType.number),
      FieldDef('gender', 'Gender', top: true),
    ],
  ),
  'api': KindDef(
    'API key',
    'API keys',
    'Client IDs, client secrets, API keys and tokens.',
    Icons.code,
    [
      FieldDef('service', 'Service'),
      FieldDef('endpoint', 'Endpoint / URL', type: TextInputType.url),
      FieldDef('client_id', 'Client ID', mono: true),
      FieldDef('client_secret', 'Client secret', secret: true),
      FieldDef('api_key', 'API key', secret: true),
      FieldDef('token', 'Access token', secret: true, multi: true),
    ],
  ),
  'ssh': KindDef(
    'SSH key',
    'SSH keys',
    'A private key, its passphrase and the server it opens.',
    Icons.terminal,
    [
      FieldDef('host', 'Host', type: TextInputType.url),
      FieldDef('port', 'Port', type: TextInputType.number),
      FieldDef('ssh_user', 'User'),
      FieldDef('private_key', 'Private key', secret: true, multi: true),
      FieldDef('passphrase', 'Passphrase', secret: true),
      FieldDef('public_key', 'Public key', multi: true, mono: true),
      FieldDef('fingerprint', 'Fingerprint', mono: true),
    ],
  ),
  'note': KindDef(
    'Secure note',
    'Notes',
    'Recovery codes, PINs, anything private.',
    Icons.description_outlined,
    [FieldDef('notes', 'Note', top: true, secret: true, multi: true)],
  ),
  'document': KindDef(
    'Document',
    'Documents',
    'Passport, ID, visa, licence or contract, with a reminder before it expires.',
    Icons.badge_outlined,
    [], // depend on the document's type: docFieldDefs()
  ),
};

KindDef kindOf(Entry e) => kindDefs[e.kind] ?? kindDefs['login']!;

String subtitleOf(Entry e) {
  switch (e.kind) {
    case 'api':
      return e.fields['service'] ?? e.fields['client_id'] ?? '';
    case 'ssh':
      final u = e.fields['ssh_user'] ?? '', h = e.fields['host'] ?? '';
      return u.isNotEmpty && h.isNotEmpty ? '$u@$h' : (h.isNotEmpty ? h : u);
    case 'note':
    case 'document': // the list shows when it expires instead
      return '';
    default:
      return [
        e.username,
        e.email,
      ].firstWhere((s) => s.isNotEmpty, orElse: () => e.website);
  }
}

/// A document's fields: its type's, then any other detail it has, so nothing
/// is ever hidden. [has] says whether a field holds something.
List<FieldDef> docFieldDefs(String type, bool Function(String key) has) {
  final own = typeFieldKeys(type);
  final keys = [
    ...own,
    for (final k in docSchemaFields.keys)
      if (!own.contains(k) && has(k)) k,
  ];
  return [
    FieldDef('doc_type', 'Type', options: docTypes),
    for (final k in keys) _docField(k, type),
  ];
}

/// Every field a document can have (the edit page keeps a box for each).
List<FieldDef> allDocFieldDefs() => docFieldDefs('', (_) => true);

FieldDef _docField(String key, String type) {
  final d = docSchemaFields[key] as Map;
  return FieldDef(
    key,
    docLabel(key, type),
    secret: d['secret'] == true,
    multi: d['multi'] == true,
    mono: d['mono'] == true,
    date: d['date'] == true,
    type: switch (d['type']) {
      'tel' => TextInputType.phone,
      'email' => TextInputType.emailAddress,
      _ => null,
    },
    options: switch (d['options']) {
      'countries' => [('', 'Choose…'), ...nations()],
      final List o => [
        ('', 'Choose…'),
        for (final x in o) ('${(x as List)[0]}', '${x[1]}'),
      ],
      _ => null,
    },
  );
}

/// Nationalities by name in the app's language (assets/countries.json).
List<(String, String)> nations() =>
    [for (final c in countries) (c[0], isArabic ? c[4] : c[2])]
      ..sort((a, b) => a.$2.compareTo(b.$2));
