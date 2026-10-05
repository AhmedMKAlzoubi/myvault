import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myvault/docs.dart';
import 'package:myvault/vault.dart';

void main() {
  test('reads passport and ID zones, with OCR slips and check digits', () {
    const td3 =
        'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\nL898902C36UTO74O8122F1204159ZE184226B<<<<<10';
    final p = readDetails(td3);
    expect(p['how'], 'mrz');
    expect(p['doc_type'], 'passport');
    expect(p['number'], 'L898902C3');
    expect(p['expires'], '2012-04-15');
    expect(p['holder'], 'Anna Maria Eriksson');
    expect(p['country'], 'UTO');
    final id = readDetails(
      'I<UTOD231458907<<<<<<<<<<<<<<<\n7408122F1204159UTO<<<<<<<<<<<6\nERIKSSON<<ANNA<MARIA<<<<<<<<<<',
    );
    expect(id['doc_type'], 'id_card');
    expect(id['number'], 'D23145890');
    expect(readMrz(td3.replaceAll('1204159', '1204158'))['expires'], isNull);
  });

  test('reads labelled dates, numbers and types like the PC does', () {
    final today = DateTime(2026, 10, 5);
    expect(
      readDetails(
        'DRIVING LICENCE\nLicence No: 12345678\nDate of issue 01/02/2020   Date of expiry 01/02/2030\nDate of birth 05/06/1990',
        today: today,
      ),
      {
        'how': 'text',
        'doc_type': 'driving_license',
        'issued': '2020-02-01',
        'expires': '2030-02-01',
        'number': '12345678',
      },
    );
    final car = readDetails(
      'رخصة مركبة\nتاريخ الانتهاء: ٠١/٠٣/٢٠٢٧',
      today: today,
    );
    expect(car['doc_type'], 'car_registration');
    expect(car['expires'], '2027-03-01');
    final lease = readDetails(
      'Lease agreement 1 March 2026 until 28 Feb 2027',
      today: today,
    );
    expect(lease['expires'], '2027-02-28');
    expect(lease['guessed'], true);
  });

  test('reminders say only the type or chosen name', () {
    final e = Entry(
      kind: 'document',
      title: 'My passport',
      fields: {
        'doc_type': 'passport',
        'expires': '2027-03-01',
        'remind': '30,7,x,7',
        'number': 'P123',
      },
    );
    final plan = schedule([e]);
    expect(plan.map((r) => (r['on'], r['days'])).toList(), [
      ('2027-01-30', 30),
      ('2027-02-22', 7),
      ('2027-03-01', 0),
    ]);
    expect(plan.first['text'], 'Passport expires in 1 month.');
    expect(plan.last['text'], 'Passport expires today.');
    expect(
      jsonEncode(plan).contains('P123') ||
          jsonEncode(plan).contains('My passport'),
      isFalse,
    );
  });

  test(
    'opens a file sealed by the PC, and seals files the PC can open',
    () async {
      final fx = jsonDecode(
        File('test_fixtures/doc_file.json').readAsStringSync(),
      );
      final dir = Directory.systemTemp.createTempSync('mv_docs');
      final v = Vault('${dir.path}/vault.dat', 'docs-test-pass');
      final ref = FileRef.fromJson(fx['ref'])!;
      final plain = await openFile(v, ref, base64.decode(fx['blob'] as String));
      expect(plain, base64.decode(fx['plain'] as String));

      final mine = await seal(
        v,
        Uint8List.fromList([0x25, 0x50, 0x44, 0x46, ...List.filled(5000, 7)]),
        'lease.pdf',
      );
      expect(mine.mime, 'application/pdf');
      expect(await openFile(v, mine), [
        0x25,
        0x50,
        0x44,
        0x46,
        ...List.filled(5000, 7),
      ]);
      expect(
        () => storeBlob(
          v,
          FileRef(mine.id, 'x', mine.mime, 1, ref.key),
          readBlob(v, mine.id),
        ),
        throwsFormatException,
      );
      expect(
        () => seal(
          v,
          Uint8List.fromList(utf8.encode('MZ not a document')),
          'x.exe',
        ),
        throwsFormatException,
      );
      final e = Entry(kind: 'document', fields: {});
      setFileRefs(e, [mine]);
      v.entries.add(e);
      expect(cleanup(v), 0);
      e.deleted = true;
      expect(cleanup(v), 1);
      expect(haveFile(v, mine.id), isFalse);
    },
  );
}
