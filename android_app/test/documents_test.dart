// A document on the phone, end to end with Android's side simulated: pick a
// scan, it's encrypted and read, the details fill in, Save keeps files and
// reminders, and Android gets a schedule that says only the type.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myvault/docs.dart' as docs;
import 'package:myvault/documents_ui.dart';
import 'package:myvault/main.dart';
import 'package:myvault/theme.dart';
import 'package:myvault/vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => docs.loadDocSchema()); // the shared document types
  testWidgets('pick a scan, details fill in, save keeps files and reminders', (
    t,
  ) async {
    t.view.physicalSize = const Size(
      1000,
      4000,
    ); // everything on screen at once
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final calls = <String, dynamic>{};
    const td3 =
        'PASSPORT\nP<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\nL898902C36UTO7408122F3004157ZE184226B<<<<<10';
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('myvault/docs'),
      (call) async {
        calls[call.method] = call.arguments;
        switch (call.method) {
          case 'pick':
            return [
              {
                'name': 'passport.jpg',
                'bytes': Uint8List.fromList([
                  0xff,
                  0xd8,
                  0xff,
                  ...List.filled(3000, 1),
                ]),
              },
            ];
          case 'ocr':
            return td3;
          case 'notifyAllowed':
          case 'askNotify':
          case 'setReminders':
            return true;
        }
        return null;
      },
    );
    final dir = Directory.systemTemp.createTempSync('mv_doc_ui');
    final v = (await t.runAsync(
      () async => Vault.create('${dir.path}/vault.dat', 'doc-ui-pass'),
    ))!;
    Session.open(v);
    final entry = Entry(kind: 'document');
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Envelope.light, Brightness.light),
        home: EntryEditPage(entry: entry, isNew: true),
      ),
    );

    await t.enterText(find.widgetWithText(TextField, 'Name'), 'My passport');
    await t.runAsync(() async {
      await t.tap(find.text('Choose files'));
      for (
        var i = 0;
        i < 40 && !find.textContaining('Filled in').evaluate().isNotEmpty;
        i++
      ) {
        await Future.delayed(const Duration(milliseconds: 50));
        await t.pump();
      }
    });
    await t.pump();
    expect(find.textContaining('Filled in'), findsOneWidget);
    expect(
      find.text('Anna Maria Eriksson'),
      findsOneWidget,
    ); // holder filled from the zone
    expect(find.text('15 Apr 2030'), findsOneWidget); // expiry, shown as a date

    await t.tap(find.text('3 months'));
    await t.pump();
    await t.runAsync(() async {
      await t.tap(
        find.byTooltip('Save').hitTestable().evaluate().isEmpty
            ? find.text('Save')
            : find.byTooltip('Save'),
      );
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await t.pump();

    final saved = v.activeEntries().single;
    expect(saved.kind, 'document');
    expect(saved.fields['doc_type'], 'passport');
    expect(saved.fields['number'], 'L898902C3');
    expect(saved.fields['expires'], '2030-04-15');
    expect(saved.fields['remind'], '90,30,7');
    final file = docs.fileRefs(saved).single;
    expect(file.name, 'passport.jpg');
    expect(docs.haveFile(v, file.id), isTrue);
    final sent = jsonDecode(calls['setReminders'] as String) as List;
    expect(sent.first['text'], 'Passport expires in 3 months.');
    expect(
      jsonEncode(sent).contains('L898902C3'),
      isFalse,
    ); // no numbers outside the vault
    expect(
      calls.containsKey('askNotify'),
      isTrue,
    ); // asked once there were reminders
    Session.lock();
  });

  testWidgets(
    'the crop screen starts on the found corners and sends the moved ones',
    (t) async {
      final photo = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAACgAAAAeCAIAAADRv8uKAAAAR0lEQVR4nO3QMREAIBTD0E/9K0EEM7JYqYF0aQy8u6x79iRSRJ3CYCKxv8JY4iivMJY4yiuMJY7yCmOJo7zCWOIorzBWbPUDudACbNfyhxsAAAAASUVORK5CYII=',
      );
      List<double>? sent;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('myvault/docs'),
        (call) async {
          if (call.method == 'detect') return [.1, .1, .9, .1, .9, .9, .1, .9];
          if (call.method == 'warp') {
            sent = [
              for (final x in call.arguments['points'] as List)
                (x as num).toDouble(),
            ];
            return Uint8List.fromList([1, 2, 3]);
          }
          return null;
        },
      );
      Uint8List? result;
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Envelope.light, Brightness.light),
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () async =>
                  result = await Navigator.of(c).push<Uint8List>(
                    MaterialPageRoute(builder: (_) => CropPage(photo: photo)),
                  ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.runAsync(() async {
        for (
          var i = 0;
          i < 40 && find.text('Use this').evaluate().isEmpty;
          i++
        ) {
          await Future.delayed(const Duration(milliseconds: 25));
          await t.pump();
        }
        await Future.delayed(
          const Duration(milliseconds: 100),
        ); // the photo decodes
        await t.pump();
      });
      await t.pumpAndSettle();
      // Drag the top-left corner down and right a little.
      final handles = find.byType(GestureDetector);
      await t.drag(handles.first, const Offset(30, 20));
      await t.pump();
      await t.tap(find.text('Use this'));
      await t.pumpAndSettle();
      expect(result, Uint8List.fromList([1, 2, 3]));
      expect(sent, hasLength(8));
      expect(sent![0], greaterThan(.1)); // moved right
      expect(sent![1], greaterThan(.1)); // and down
      expect(sent!.sublist(2), [
        .9,
        .1,
        .9,
        .9,
        .1,
        .9,
      ]); // the others where found
    },
  );

  testWidgets(
    'Scan with NFC: a card access number opens the chip, and its details fill in',
    (t) async {
      t.view.physicalSize = const Size(1000, 4000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      Map? asked;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('myvault/nfc'),
        (call) async {
          if (call.method == 'status') return 'on';
          if (call.method == 'read') {
            asked = call.arguments as Map;
            // what the chip's DG1 holds: the TD1 zone of a Jordanian ID card
            return 'IDJORAB123456719901234567<<<<<\n'
                '9006050M3103120JOR<<<<<<<<<<<6\n'
                'MOHAMMED<<AHMED<<<<<<<<<<<<<<<';
          }
          return null;
        },
      );
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('myvault/docs'),
        (call) async => null,
      );
      final dir = Directory.systemTemp.createTempSync('mv_nfc_ui');
      final v = (await t.runAsync(
        () async => Vault.create('${dir.path}/vault.dat', 'nfc-ui-pass'),
      ))!;
      Session.open(v);
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Envelope.light, Brightness.light),
          home: EntryEditPage(entry: Entry(kind: 'document'), isNew: true),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Scan with NFC'));
      await t.pumpAndSettle();
      expect(
        find.text('Passport number'),
        findsOneWidget,
      ); // asks for the printed details
      await t.tap(find.text('Use a card access number instead'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Card access number'),
        '123456',
      );
      await t.pump();
      await t.tap(find.text('Start'));
      await t.pumpAndSettle();
      expect(asked?['can'], '123456');
      expect(find.textContaining('Read from the chip'), findsOneWidget);
      expect(find.text('Ahmed Mohammed'), findsOneWidget);
      expect(find.text('9901234567'), findsOneWidget); // the ID number
      expect(find.text('AB1234567'), findsOneWidget); // the card's own number
      Session.lock();
    },
  );
}
