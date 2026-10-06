import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myvault/health.dart';
import 'package:myvault/otp.dart';
import 'package:myvault/vault.dart';
import 'package:pointycastle/export.dart';

void main() {
  test('2FA codes match the PC (RFC 6238 vectors)', () {
    final c = jsonDecode(
      File('test_fixtures/otp_cases.json').readAsStringSync(),
    );
    for (final k in c['cases'] as List) {
      final (code, left) = otpCode(
        k['text'],
        now: (k['time'] as num).toDouble(),
      );
      expect(code, k['code'], reason: '${k['text']} @ ${k['time']}');
      if (k['left'] != null) expect(left, k['left']);
    }
    for (final bad in c['bad'] as List) {
      expect(() => parseOtp('$bad'), throwsFormatException, reason: '$bad');
    }
    final s = parseOtp((c['cases'] as List).first['text'] as String);
    expect((s.issuer, s.account), ('Example', 'alice@example.com'));
  });

  test('an email address needs its full domain (same rule as the PC)', () {
    for (final ok in ['me@gmail.com', 'a.b+c@mail.co.uk', '']) {
      expect(emailProblem(Entry(email: ok)), isEmpty, reason: ok);
    }
    for (final bad in [
      'zduhsu@gmail',
      'a@b.c',
      '@gmail.com',
      'x y@gmail.com',
      'me@gmail.',
    ]) {
      expect(emailProblem(Entry(email: bad)), contains(bad), reason: bad);
    }
    expect(
      emailProblem(Entry(kind: 'document', fields: {'email': 'a@b'})),
      isNotEmpty,
    );
  });

  test('a deleted entry keeps nothing but the marker', () {
    final dir = Directory.systemTemp.createTempSync('mv_wipe');
    final v = Vault.create('${dir.path}/v.dat', 'pw-12345678');
    final e = Entry(
      kind: 'note',
      title: 'Bank PIN',
      notes: '1234',
      custom: {'PUK': '5678'},
    );
    v.add(e);
    v.deleteById(e.id);
    final t = Vault.open('${dir.path}/v.dat', 'pw-12345678').getById(e.id)!;
    expect(t.deleted, isTrue);
    expect(
      [t.title, t.notes, t.custom, t.fields],
      ['', '', <String, String>{}, <String, String>{}],
    );
    expect(t.kind, 'note');
    final old = Entry.fromJson({
      'id': 'x',
      'kind': 'note',
      'notes': 'secret',
      'deleted': true,
      'updated_at': 5.0,
    });
    expect((old.notes, old.updatedAt, old.deleted), ('', 5.0, true));
  });

  test('delete several, then undo brings them back newer', () {
    final dir = Directory.systemTemp.createTempSync('mv_many');
    final v = Vault.create('${dir.path}/v.dat', 'pw-12345678');
    final es = [
      for (var i = 0; i < 3; i++)
        Entry(kind: 'note', title: 'N$i', notes: 'secret $i'),
    ];
    es.forEach(v.add);
    final ids = [for (final e in es) e.id];
    final gone = v.deleteMany(ids.take(2));
    expect(gone.length, 2);
    expect(v.activeEntries().map((e) => e.title), ['N2']);
    final at = v.getById(ids[0])!.updatedAt;
    v.undoDelete(gone);
    expect(v.activeEntries().map((e) => e.title).toSet(), {'N0', 'N1', 'N2'});
    expect(v.getById(ids[0])!.notes, 'secret 0');
    expect(v.getById(ids[0])!.updatedAt, greaterThanOrEqualTo(at));
  });

  test('a sync leaves kept and left-out entries as they are', () {
    final dir = Directory.systemTemp.createTempSync('mv_held');
    final v = Vault.create('${dir.path}/v.dat', 'pw-12345678');
    v.entries = [
      Entry(id: 'a', title: 'Shared', updatedAt: 100),
      Entry(id: 'b', title: 'Kept', updatedAt: 100, localOnly: true),
      Entry(id: 'c', title: 'Left out', updatedAt: 100),
    ];
    final only = {'a', 'b'};
    final changed = v.mergeIn([
      Entry(id: 'a', title: 'Shared v2', updatedAt: 200),
      Entry(id: 'b', title: "PC's copy", updatedAt: 300),
      Entry(id: 'c', title: 'Newer on the PC', updatedAt: 300),
      Entry(id: 'n', title: 'New on the PC', updatedAt: 100),
    ], held: (e) => e.localOnly || !only.contains(e.id));
    expect(changed, 2);
    expect(
      {for (final e in v.entries) e.id: e.title},
      {'a': 'Shared v2', 'b': 'Kept', 'c': 'Left out', 'n': 'New on the PC'},
    );
    final back = Vault.open('${dir.path}/v.dat', 'pw-12345678');
    expect(back.getById('b')!.localOnly, isTrue); // the flag is kept
  });

  test('old passwords are kept, newest first, at most 10', () {
    final e = Entry(password: 'first');
    for (final pw in ['second', 'second', 'third']) {
      final old = e.password;
      e.password = pw;
      keepOldPassword(e, old);
    }
    expect(passwordHistory(e).map((h) => h.$1), ['second', 'first']);
    for (var i = 0; i < 15; i++) {
      final old = e.password;
      e.password = 'pw$i';
      keepOldPassword(e, old);
    }
    expect(passwordHistory(e).length, historyKeep);
  });

  test(
    'health finds weak and reused; the leak check sends 5 characters',
    () async {
      final a = Entry(title: 'A', password: 'abc');
      final b = Entry(title: 'B', password: 'abc');
      final c = Entry(title: 'C', password: 'Long-and-Unique-Passphrase-42!');
      final r = healthReport([a, b, c]);
      expect(r.total, 3);
      expect(r.weak, [a, b]);
      expect(r.reused, [
        [a, b],
      ]);
      final h = SHA1Digest()
          .process(utf8.encode('abc'))
          .map((x) => x.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      final asked = <String>[];
      final got = await leakCounts(
        ['abc', 'abc'],
        fetch: (p) async {
          asked.add(p);
          return '${h.substring(5)}:42\r\nFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF:0';
        },
      );
      expect(got, {'abc': 42});
      expect(asked, [h.substring(0, 5)]);
    },
  );
}
