// Unit tests for MyVault's core logic (crypto, generator, vault round-trip).
// These do not need a device/emulator: run with `flutter test`.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:myvault/crypto.dart';
import 'package:myvault/generator.dart';
import 'package:myvault/sync.dart';
import 'package:myvault/paper.dart' as paper;
import 'package:pointycastle/export.dart' show InvalidCipherTextException;
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
    expect(
      () => decryptBytes(blob, 'wrong'),
      throwsA(isA<WrongPasswordException>()),
    );
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

  test('vault merge keeps newest and propagates tombstones', () {
    final dir = Directory.systemTemp.createTempSync('myvault_merge');
    final v = Vault.create('${dir.path}/v.dat', 'pw');
    v.entries = [
      Entry(id: 'x', password: 'old', updatedAt: 100),
      Entry(id: 'y', updatedAt: 100),
    ];
    final changed = v.mergeIn([
      Entry(id: 'x', password: 'new', updatedAt: 200),
      Entry(id: 'y', updatedAt: 50, deleted: true),
      Entry(id: 'z', kind: 'ssh', fields: {'host': 'pi'}, updatedAt: 100),
    ]);
    final m = {for (final e in v.entries) e.id: e};
    expect(changed, 2);
    expect(m['x']!.password, 'new');
    expect(m['y']!.deleted, isFalse);
    expect(m['z']!.fields['host'], 'pi');
    dir.deleteSync(recursive: true);
  });

  test('paper restore brings back deleted entries', () {
    final dir = Directory.systemTemp.createTempSync('myvault_restore');
    final v = Vault.create('${dir.path}/v.dat', 'pw');
    v.entries = [
      Entry(id: 'gone', title: 'Bank', updatedAt: 500, deleted: true),
      Entry(id: 'live', title: 'Mail', password: 'new', updatedAt: 500),
    ];
    final changed = v.restoreIn([
      Entry(id: 'gone', title: 'Bank', password: 'p', updatedAt: 100),
      Entry(id: 'live', title: 'Mail', password: 'old', updatedAt: 100),
    ]);
    final m = {for (final e in v.entries) e.id: e};
    expect(changed, 1);
    expect(m['gone']!.deleted, isFalse);
    expect(m['gone']!.password, 'p');
    expect(m['gone']!.updatedAt, greaterThan(500));
    expect(m['live']!.password, 'new');
    dir.deleteSync(recursive: true);
  });

  test('sync code parses and rejects junk', () {
    final key = List<int>.generate(32, (i) => i);
    final k = base64Url.encode(key).replaceAll('=', '');
    final c = SyncCode.parse(
      'myvault://sync?v=2&h=192.168.1.5,10.0.0.2&p=8789&k=$k',
    );
    expect(c.hosts, ['192.168.1.5', '10.0.0.2']);
    expect(c.port, 8789);
    expect(c.key, key);
    expect(() => SyncCode.parse('https://example.com'), throwsFormatException);
    // A code naming an internet server (or a hostname) is refused outright.
    expect(
      () => SyncCode.parse('myvault://sync?v=2&h=8.8.8.8&p=8789&k=$k'),
      throwsFormatException,
    );
    expect(
      () => SyncCode.parse('myvault://sync?v=2&h=evil.example&p=8789&k=$k'),
      throwsFormatException,
    );
    expect(
      SyncCode.parse(
        'myvault://sync?v=2&h=8.8.8.8,192.168.1.7&p=8789&k=$k',
      ).hosts,
      ['192.168.1.7'],
    );
    expect(
      () => SyncCode.parse('myvault://sync?v=1&h=a&p=1&k=AA'),
      throwsFormatException,
    );
  });

  test('paper block written by Python decrypts in Dart', () async {
    final text = File('test_fixtures/paper_block.txt').readAsStringSync();
    final block = paper.PaperBlock.parse(text)!;
    final key = await paper.deriveBackupKey('paper-fixture-pw', block.salt);
    final e = paper.decryptBlock(block, key);
    expect(e.id, 'paper-fixture-1');
    expect(e.kind, 'api');
    expect(e.fields['client_secret'], 's3cr3t!');
    final wrong = await paper.deriveBackupKey('nope-nope', block.salt);
    expect(
      () => paper.decryptBlock(block, wrong),
      throwsA(isA<InvalidCipherTextException>()),
    );
    expect(paper.PaperBlock.parse('HELLO WORLD'), isNull);
  });

  test('kinds and fields round-trip through JSON', () {
    final e = Entry(
      kind: 'api',
      title: 'Weather',
      fields: {'service': 'OpenWeather', 'api_key': 'K'},
    );
    final back = Entry.fromJson(e.toJson());
    expect(back.kind, 'api');
    expect(back.fields['api_key'], 'K');
    expect(back.displayName(), 'Weather');
    expect(back.matches('openweather'), isTrue);
    expect(back.matches('K'), isFalse);
    expect(Entry.fromJson({'kind': 'bogus'}).kind, 'login');
  });

  test('vault save/open round-trip on disk', () {
    final dir = Directory.systemTemp.createTempSync('myvault_test');
    final path = '${dir.path}/vault.dat';
    final v = Vault.create(path, 'pw');
    v.add(
      Entry(
        title: 'Netflix',
        website: 'netflix.com',
        password: 'p',
        custom: {'pin': '1234'},
      ),
    );

    final v2 = Vault.open(path, 'pw');
    expect(v2.activeEntries().length, 1);
    expect(v2.activeEntries().first.title, 'Netflix');
    expect(v2.activeEntries().first.custom['pin'], '1234');
    expect(v2.search('netflix').isNotEmpty, isTrue);
    expect(v2.search('gmail').isEmpty, isTrue);

    dir.deleteSync(recursive: true);
  });
}
