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

    // Removing the file asks first, and can be put back.
    final removeBtn = find.byTooltip('Remove file');
    expect(removeBtn, findsOneWidget);
    await t.tap(removeBtn);
    await t.pumpAndSettle();
    await t.tap(find.text('Keep it'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Remove file'), findsOneWidget); // still there
    await t.tap(find.byTooltip('Remove file'));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Remove file'), findsNothing);
    await t.tap(find.text('Put it back'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Remove file'), findsOneWidget); // back

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
    final sent =
        jsonDecode((calls['setReminders'] as Map)['json'] as String) as List;
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

  testWidgets('on a phone-sized screen, a scan stays after scrolling', (
    t,
  ) async {
    // The page's list only builds what's near the screen. The files used to
    // be filled in by their own section, so scrolling up to check the fields
    // and back down to Save brought the section back empty: no photos saved.
    t.view.physicalSize = const Size(400, 500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('myvault/docs'),
      (call) async => switch (call.method) {
        'pick' => [
          {
            'name': 'front.jpg',
            'bytes': Uint8List.fromList([
              0xff,
              0xd8,
              0xff,
              ...List.filled(500, 3),
            ]),
          },
        ],
        'ocr' => '',
        _ => true,
      },
    );
    final dir = Directory.systemTemp.createTempSync('mv_doc_keep');
    final v = (await t.runAsync(
      () async => Vault.create('${dir.path}/vault.dat', 'doc-keep-pass'),
    ))!;
    Session.open(v);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Envelope.light, Brightness.light),
        home: EntryEditPage(entry: Entry(kind: 'document'), isNew: true),
      ),
    );
    await t.enterText(find.widgetWithText(TextField, 'Name'), 'ID card');
    FocusManager.instance.primaryFocus
        ?.unfocus(); // or it keeps the page at the top
    await t.pump();
    final list = find.byType(ListView);
    Future<void> bring(String text) async {
      // into the middle of the screen, scrolling the page's list
      final pos = t
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position;
      for (var i = 0; i < 30 && find.text(text).evaluate().isEmpty; i++) {
        pos.jumpTo(pos.pixels + 300);
        await t.pump();
      }
      pos.jumpTo(pos.pixels + t.getCenter(find.text(text)).dy - 250);
      await t.pumpAndSettle();
    }

    await bring('Choose files');
    await t.runAsync(() async {
      await t.tap(find.text('Choose files'));
      await Future.delayed(const Duration(milliseconds: 300));
    });
    await t.pumpAndSettle();
    expect(find.byTooltip('Remove file'), findsOneWidget);
    t
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position
        .jumpTo(0); // up to the top, to check the fields
    await t.pumpAndSettle();
    expect(find.byTooltip('Remove file'), findsNothing); // its section is gone
    await bring('Save');
    await t.runAsync(() async {
      await t.tap(find.text('Save'));
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await t.pump();
    final saved = v.activeEntries().single;
    expect(docs.fileRefs(saved).single.name, 'front.jpg');
    expect(docs.cleanup(v), 0); // so the photo isn't deleted at the next unlock
    Session.lock();
  });

  testWidgets("coming back from the camera doesn't lock the vault", (t) async {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('myvault/clipboard'),
      (call) async => null,
    );
    final dir = Directory.systemTemp.createTempSync('mv_away');
    Session.vault = (await t.runAsync(
      () async => Vault.create('${dir.path}/vault.dat', 'away-pass-1'),
    ))!;
    final before = Session.backgroundSeconds;
    addTearDown(() => Session.backgroundSeconds = before);
    Session.backgroundSeconds = 0; // "lock as soon as I leave"
    docs.awayForResult = 1; // the camera app is open for MyVault
    Session.paused();
    docs.awayForResult = 0;
    Session.resumed();
    expect(Session.vault, isNotNull); // the scan isn't lost
    Session.paused(); // leaving MyVault any other way still locks it
    Session.resumed();
    expect(Session.vault, isNull);
  });

  testWidgets(
    'the crop screen starts on the found corners and sends the moved ones',
    (t) async {
      final photo = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAACgAAAAeCAIAAADRv8uKAAAAR0lEQVR4nO3QMREAIBTD0E/9K0EEM7JYqYF0aQy8u6x79iRSRJ3CYCKxv8JY4iivMJY4yiuMJY7yCmOJo7zCWOIorzBWbPUDudACbNfyhxsAAAAASUVORK5CYII=',
      );
      List<double>? sent;
      final looks = <String>[];
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
          if (call.method == 'enhance') {
            looks.add(call.arguments['mode'] as String);
            return photo; // a real picture, so the preview can show it
          }
          return null;
        },
      );
      CropResult? result;
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Envelope.light, Brightness.light),
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () async =>
                  result = await Navigator.of(c).push<CropResult>(
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
          i < 40 && find.text('Cut it out').evaluate().isEmpty;
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
      await t.tap(find.text('Cut it out'));
      await t.runAsync(() async {
        for (var i = 0; i < 40 && find.text('Done').evaluate().isEmpty; i++) {
          await Future.delayed(const Duration(milliseconds: 25));
          await t.pump();
        }
      });
      await t.pumpAndSettle();
      expect(looks, ['scan']); // the scanned look first
      await t.tap(find.text('Black & white'));
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(looks, ['scan', 'bw']);
      await t.tap(find.text('Done'));
      await t.pumpAndSettle();
      expect(result?.photo, photo); // the black-and-white page
      expect(result?.more, isFalse); // Done: no more pages
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
}
