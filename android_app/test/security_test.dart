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
