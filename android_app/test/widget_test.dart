// Unit tests for MyVault's core logic (crypto, generator, vault round-trip).
// These do not need a device/emulator: run with `flutter test`.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:myvault/crypto.dart';
import 'package:myvault/generator.dart';
import 'package:myvault/sync.dart';
import 'package:myvault/vault.dart';

void main() {
  test('encrypt/decrypt round-trip', () {
    final data = Uint8List.fromList(utf8.encode('secret café ☕ payload'));
    final blob = encryptBytes(data, 'master-pass');
    final back = decryptBytes(blob, 'master-pass');
    expect(utf8.decode(back), 'secret café ☕ payload');
  });

  test('wrong password is rejected', () {
    final blob = encryptBytes(Uint8List.fromList(utf8.encode('x')), 'right');
    expect(() => decryptBytes(blob, 'wrong'), throwsA(isA<WrongPasswordException>()));
  });

  test('generator respects length and charset', () {
    final p = PasswordPolicy(length: 24, useSymbols: false);
    for (var i = 0; i < 50; i++) {
      final pw = generatePassword(p);
      expect(pw.length, 24);
      expect(RegExp(r'^[A-Za-z0-9]+$').hasMatch(pw), isTrue, reason: pw);
    }
  });

  test('generator avoids ambiguous characters', () {
    final p = PasswordPolicy(length: 40, avoidAmbiguous: true);
    for (var i = 0; i < 30; i++) {
      final pw = generatePassword(p);
      expect(RegExp(r'[Il1O0o]').hasMatch(pw), isFalse, reason: pw);
    }
  });

  test('sync merge keeps newest and propagates tombstones', () {
    final local = [
      {'id': 'x', 'updated_at': 100, 'password': 'old'},
      {'id': 'y', 'updated_at': 100},
    ];
    final remote = [
      {'id': 'x', 'updated_at': 200, 'password': 'new'},
      {'id': 'y', 'updated_at': 50, 'deleted': true},
      {'id': 'z', 'updated_at': 100},
    ];
    final merged = {for (final e in mergeEntries(local, remote)) e['id']: e};
    expect(merged['x']!['password'], 'new');
    expect(merged['y']!['deleted'], isNot(true));
    expect(merged.containsKey('z'), isTrue);
  });

  test('sync key derivation is deterministic', () {
    final a = deriveSyncKey('same-pass');
    final b = deriveSyncKey('same-pass');
    final c = deriveSyncKey('different');
    expect(a, equals(b));
    expect(a, isNot(equals(c)));
  });

  test('vault save/open round-trip on disk', () {
    final dir = Directory.systemTemp.createTempSync('myvault_test');
    final path = '${dir.path}/vault.dat';
    final v = Vault.create(path, 'pw');
    v.add(Entry(title: 'Netflix', website: 'netflix.com', password: 'p', custom: {'pin': '1234'}));

    final v2 = Vault.open(path, 'pw');
    expect(v2.activeEntries().length, 1);
    expect(v2.activeEntries().first.title, 'Netflix');
    expect(v2.activeEntries().first.custom['pin'], '1234');
    expect(v2.search('netflix').isNotEmpty, isTrue);
    expect(v2.search('gmail').isEmpty, isTrue);

    dir.deleteSync(recursive: true);
  });
}
