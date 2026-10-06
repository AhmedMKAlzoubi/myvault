import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myvault/vault.dart';
import 'package:myvault/vaults.dart';

void main() {
  test('several vaults: separate files, names listed, deleting one', () async {
    final root = Directory.systemTemp.createTempSync('mv_vaults');
    vaultsRootOverride = root;
    expect((await vaultList()).map((v) => v.id), [defaultVault]);
    final home = await vaultPathOf(defaultVault);
    expect(home, '${root.path}/vault.dat'); // the original stays where it was
    Vault.create(home, 'home-pass-1').add(Entry(title: 'Netflix'));

    final work = await newVault('Work');
    final workPath = await vaultPathOf(work);
    expect(workPath, '${root.path}/vaults/$work/vault.dat');
    Vault.create(workPath, 'work-pass-1').add(Entry(title: 'Jira'));
    expect((await vaultList()).map((v) => v.name), ['My vault', 'Work']);
    expect(
      Vault.open(workPath, 'work-pass-1').activeEntries().single.title,
      'Jira',
    );
    expect(
      () => Vault.open(workPath, 'home-pass-1'),
      throwsA(isA<Exception>()),
    ); // each opens only with its own

    await deleteVault(work);
    expect((await vaultList()).map((v) => v.name), ['My vault']);
    expect(Directory('${root.path}/vaults/$work').existsSync(), isFalse);
    expect(File(home).existsSync(), isTrue); // the others are untouched
    vaultsRootOverride = null;
  });
}
