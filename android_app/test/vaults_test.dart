import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myvault/copies.dart';
import 'package:myvault/docs.dart' as docs;
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

  test('a copy: encrypted adds back as a vault, readable is plain', () async {
    final root = Directory.systemTemp.createTempSync('mv_copies');
    vaultsRootOverride = root;
    final v = Vault.create(await vaultPathOf(defaultVault), 'home-pass-1')
      ..vaultId = 'c' * 32;
    final scan = await docs.seal(
      v,
      Uint8List.fromList(utf8.encode('%PDF-1.4 lease')),
      'lease.pdf',
    );
    final doc = Entry(kind: 'document', title: 'Lease');
    docs.setFileRefs(doc, [scan]);
    v.add(
      Entry(
        title: 'Bank',
        website: 'bank.com',
        username: 'me',
        password: 's3, "x"',
      ),
    );
    v.add(doc);

    final enc = encryptedCopy(v, 'My vault');
    expect(enc.keys.toSet(), {
      'myvault.json',
      'vault.dat',
      'files/${scan.id}.bin',
    });
    expect(
      utf8.decode(enc['vault.dat']!, allowMalformed: true),
      isNot(contains('bank.com')),
    );
    final id = await addCopy(enc);
    expect((await vaultList()).map((x) => x.name), [
      'My vault',
      'My vault (2)',
    ]);
    final back = Vault.open(await vaultPathOf(id), 'home-pass-1');
    expect(back.vaultId, 'c' * 32);
    final lease = back.activeEntries().firstWhere((e) => e.title == 'Lease');
    final ref = docs.fileRefs(lease).single;
    expect(utf8.decode(await docs.openFile(back, ref)), '%PDF-1.4 lease');

    final plain = await readableCopy(v, 'My vault');
    expect(
      utf8.decode(plain['logins.csv']!),
      contains('bank.com,me,"s3, ""x"""'),
    );
    expect(plain.containsKey('files/Lease - lease.pdf'), isTrue);
    await expectLater(addCopy(plain), throwsA(isA<FormatException>()));
    await expectLater(
      addCopy({'vault.dat': enc['vault.dat']!, '../escape.bin': Uint8List(1)}),
      throwsA(isA<FormatException>()),
    );
    expect((await vaultList()).length, 2); // nothing added for those
    vaultsRootOverride = null;
  });
}
