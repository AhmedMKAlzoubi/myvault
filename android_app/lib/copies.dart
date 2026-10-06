/// A copy of a vault as one .zip, to keep somewhere safe or move to another
/// device. Same format as the PC's (myvault/copies.py), so either app reads
/// the other's encrypted copies.
///
/// Encrypted: myvault.json (name and sync id), vault.dat and `files/<id>.bin`
/// as they are on this phone; it opens only with the vault's master password.
/// Readable: README.txt, entries.json, logins.csv and the files themselves;
/// anyone who has it can read everything.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'docs.dart';
import 'vault.dart';
import 'vaults.dart';

const _ch = MethodChannel('myvault/docs');
final _member = RegExp(r'^(myvault\.json|vault\.dat|files/[0-9a-f]{32}\.bin)$');

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

Map<String, Uint8List> encryptedCopy(Vault v, String name) => {
  'myvault.json': _utf8(
    jsonEncode({
      'app': 'MyVault',
      'copy': 1,
      'name': name,
      'vault_id': v.vaultId,
    }),
  ),
  'vault.dat': File(v.path).readAsBytesSync(),
  for (final r in liveRefs(v).values)
    if (haveFile(v, r.id)) 'files/${r.id}.bin': readBlob(v, r.id),
};

String _csv(List<String> row) => row
    .map(
      (c) =>
          RegExp(r'[",\r\n]').hasMatch(c) ? '"${c.replaceAll('"', '""')}"' : c,
    )
    .join(',');

Future<Map<String, Uint8List>> readableCopy(Vault v, String name) async {
  final live = v.activeEntries();
  final out = <String, Uint8List>{
    'README.txt': _utf8(
      'This is a READABLE copy of your MyVault vault "$name". It is NOT encrypted.\n\n'
      'Anyone who opens this file can read every password, key and document in it.\n'
      'Keep it offline (not in email or cloud storage), and delete it when you no\n'
      'longer need it.\n\n'
      'entries.json  everything, as MyVault keeps it\n'
      'logins.csv    your logins, ready to import into another password manager\n'
      'files/        the photos and PDFs attached to your entries\n',
    ),
    'entries.json': _utf8(
      const JsonEncoder.withIndent(
        ' ',
      ).convert([for (final e in live) e.toJson()]),
    ),
    'logins.csv': _utf8(
      [
        _csv(['name', 'url', 'username', 'password', 'note']),
        for (final e in live)
          if (e.kind == 'login')
            _csv([
              e.title,
              e.website,
              e.username.isEmpty ? e.email : e.username,
              e.password,
              e.notes,
            ]),
      ].join('\r\n'),
    ),
  };
  for (final e in live) {
    for (final r in fileRefs(e)) {
      if (!haveFile(v, r.id)) continue;
      final stem = '${e.title.isEmpty ? 'Entry' : e.title} - ${r.name}'
          .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
      var base = stem;
      for (var n = 2; out.containsKey('files/$base'); n++) {
        base = '$n $stem';
      }
      out['files/$base'] = await openFile(v, r);
    }
  }
  return out;
}

Future<Uint8List> zip(Map<String, Uint8List> files) async =>
    (await _ch.invokeMethod<Uint8List>('zip', {'files': files}))!;

/// The picked copy's members, or null if nothing was picked.
Future<Map<String, Uint8List>?> pickCopy() async {
  final bytes = await _ch.invokeMethod<Uint8List>('pickCopy');
  if (bytes == null) return null;
  try {
    return (await _ch.invokeMapMethod<String, Uint8List>('unzip', {
      'bytes': bytes,
    }))!;
  } on PlatformException {
    throw const FormatException("That isn't a MyVault copy.");
  }
}

/// [name], or "name (2)"... when a vault on this phone already has it.
String freeName(String name, List<VaultInfo> vaults) {
  final used = {for (final v in vaults) v.name.toLowerCase()};
  final base = name.trim().isEmpty ? 'My vault' : name.trim();
  var out = base;
  for (var n = 2; used.contains(out.toLowerCase()); n++) {
    out = '$base ($n)';
  }
  return out;
}

/// Add an encrypted copy as a new vault on this phone (it keeps its own
/// master password); returns its id. Throws FormatException for people.
Future<String> addCopy(Map<String, Uint8List> files) async {
  if (files.containsKey('README.txt') && files.containsKey('entries.json')) {
    throw const FormatException(
      "That's a readable copy. Only encrypted copies can be added as a vault.",
    );
  }
  if (!files.containsKey('vault.dat') || !files.keys.every(_member.hasMatch)) {
    throw const FormatException("That isn't a MyVault copy.");
  }
  Map meta = const {};
  try {
    if (jsonDecode(utf8.decode(files['vault.dat']!))['magic'] != 'MYVAULT') {
      throw const FormatException("That isn't a MyVault copy.");
    }
    if (files['myvault.json'] != null) {
      meta = jsonDecode(utf8.decode(files['myvault.json']!)) as Map;
    }
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('That copy is damaged.');
  }
  final id = await newVault(
    freeName('${meta['name'] ?? ''}', await vaultList()),
  );
  final home = File(await vaultPathOf(id)).parent.path;
  Directory('$home/files').createSync(recursive: true);
  for (final f in files.entries) {
    if (f.key != 'myvault.json') {
      File('$home/${f.key}').writeAsBytesSync(f.value);
    }
  }
  return id;
}

/// Zip [files] and let the person choose where to save it.
Future<bool> saveCopy(Map<String, Uint8List> files, String name) async =>
    await _ch.invokeMethod<bool>('saveCopy', {
      'bytes': await zip(files),
      'mime': 'application/zip',
      'name': name,
    }) ??
    false;
