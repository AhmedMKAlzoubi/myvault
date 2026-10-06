/// Several vaults ("Work", "Home"...), each an encrypted file with its own
/// master password, files and reminders. The original vault.dat is "My vault";
/// the others live in `vaults/<id>/`. vaults.json lists their names, so the
/// unlock screen can offer them. The same layout as the PC's myvault/paths.py.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'l10n.dart';

const defaultVault = 'default';
final _idRx = RegExp(r'^(default|[0-9a-f]{32})$');

class VaultInfo {
  final String id, name;
  const VaultInfo(this.id, this.name);
}

/// Lets tests point at a temporary folder.
Directory? vaultsRootOverride;

Future<Directory> _root() async =>
    vaultsRootOverride ?? await getApplicationDocumentsDirectory();

/// The vault being unlocked or open (its reminders and fingerprint key).
String currentVault = defaultVault;

Future<List<VaultInfo>> vaultList() async {
  final out = <VaultInfo>[];
  try {
    final f = File('${(await _root()).path}/vaults.json');
    for (final v in jsonDecode(f.readAsStringSync()) as List) {
      final id = '${v['id']}';
      if (_idRx.hasMatch(id)) {
        out.add(VaultInfo(id, '${v['name'] ?? 'My vault'}'));
      }
    }
  } catch (_) {
    // none yet: just the original vault
  }
  if (!out.any((v) => v.id == defaultVault)) {
    out.insert(0, const VaultInfo(defaultVault, 'My vault'));
  }
  return out;
}

Future<void> saveVaults(List<VaultInfo> list) async {
  final f = File('${(await _root()).path}/vaults.json');
  final tmp = File('${f.path}.part');
  tmp.writeAsStringSync(
    jsonEncode([
      for (final v in list) {'id': v.id, 'name': v.name},
    ]),
  );
  tmp.renameSync(f.path);
}

Future<String> newVault(String name) async {
  final r = Random.secure();
  final id = List.generate(
    16,
    (_) => r.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  await saveVaults([...await vaultList(), VaultInfo(id, name.trim())]);
  return id;
}

/// Where one vault's file is (its files and reminders sit beside it).
Future<String> vaultPathOf(String id) async {
  if (!_idRx.hasMatch(id)) throw ArgumentError('bad vault id');
  final root = (await _root()).path;
  if (id == defaultVault) return '$root/vault.dat';
  Directory('$root/vaults/$id').createSync(recursive: true);
  return '$root/vaults/$id/vault.dat';
}

/// Removes a vault from this phone: its file, files and the list entry
/// (the original vault stays listed, empty).
Future<void> deleteVault(String id) async {
  final path = await vaultPathOf(id);
  if (id == defaultVault) {
    for (final f in [File(path), File('$path.tmp')]) {
      if (f.existsSync()) f.deleteSync();
    }
    final files = Directory('${File(path).parent.path}/files');
    if (files.existsSync()) files.deleteSync(recursive: true);
    await saveVaults([
      for (final v in await vaultList())
        v.id == id ? const VaultInfo(defaultVault, 'My vault') : v,
    ]);
  } else {
    final dir = File(path).parent;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    await saveVaults([
      for (final v in await vaultList())
        if (v.id != id) v,
    ]);
  }
}

/// A vault's name to show: the original's default name in the app's language,
/// any name you chose as you typed it.
String vaultLabel(String name) => name == 'My vault' ? tr('My vault') : name;
