/// Entry kinds and their fields. Must match KINDS in myvault/ui/app.js.
library;

import 'package:flutter/material.dart';

import 'vault.dart';

class FieldDef {
  final String key, label;
  final bool top, secret, multi, mono, gen;
  final TextInputType? type;
  const FieldDef(
    this.key,
    this.label, {
    this.top = false,
    this.secret = false,
    this.multi = false,
    this.mono = false,
    this.gen = false,
    this.type,
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
      return '';
    default:
      return [
        e.username,
        e.email,
      ].firstWhere((s) => s.isNotEmpty, orElse: () => e.website);
  }
}
