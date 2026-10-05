import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myvault/docs.dart';
import 'package:myvault/vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => loadDocSchema()); // the shared document types
  test('reads documents exactly like the PC (shared cases)', () {
    final c = jsonDecode(
      File('test_fixtures/read_cases.json').readAsStringSync(),
    );
    final today = DateTime.parse(c['today'] as String);
    for (final k in c['cases'] as List) {
      expect(
        readDetails(k['text'], today: today),
        k['want'],
        reason: k['name'] as String,
      );
    }
    const td3 =
        'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\nL898902C36UTO7408122F1204159ZE184226B<<<<<10';
    expect(readMrz(td3.replaceAll('1204159', '1204158'))['expires'], isNull);
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
