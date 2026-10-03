// Renders the real screens to PNGs for design review (.impeccable/review/).
// Skipped unless CAPTURE=1:   CAPTURE=1 flutter test test/capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myvault/main.dart';
import 'package:myvault/theme.dart';
import 'package:myvault/vault.dart';

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(
      Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
    );
  }
  await loader.load();
}

void main() {
  final on = Platform.environment['CAPTURE'] == '1';
  final out = '${Directory.current.parent.path}/.impeccable/review';

  testWidgets('capture phone screens', (t) async {
    final fonts =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    await t.runAsync(() async {
      // Styles that name no family fall back to the test font; on a phone they get Roboto.
      for (final fam in ['Roboto', 'FlutterTest', 'Ahem']) {
        await _font(fam, [
          '$fonts/roboto-regular.ttf',
          '$fonts/roboto-medium.ttf',
          '$fonts/roboto-bold.ttf',
        ]);
      }
      await _font('MaterialIcons', ['$fonts/materialicons-regular.otf']);
      await _font('monospace', ['C:/Windows/Fonts/consola.ttf']);
    });
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.625;

    final dir = Directory.systemTemp.createTempSync('mv_capture');
    vaultPathOverride = '${dir.path}/vault.dat';
    final v = await t.runAsync(
      () async => Vault.create(vaultPathOverride!, 'capture-pass'),
    );
    v!.entries = [
      Entry(
        id: '1',
        title: 'Netflix',
        website: 'netflix.com',
        email: 'ahmed@example.com',
        password: 'Rk7#vQ2!mPz9Lw',
        notes: 'Family plan, renews on the 4th.',
        custom: {'Profile PIN': '4471'},
      ),
      Entry(
        id: '2',
        title: 'GitHub',
        website: 'github.com',
        username: 'ahmed-dev',
        password:
            'h8F-2kQz-Wp9x', // fake demo data for screenshots  gitleaks:allow
      ),
      Entry(
        id: '3',
        kind: 'api',
        title: 'OpenWeather production',
        fields: {'service': 'OpenWeather', 'api_key': '9f2c1e7a44b0'},
      ),
      Entry(
        id: '4',
        kind: 'ssh',
        title: 'Home server',
        fields: {
          'host': '192.168.1.40',
          'ssh_user': 'pi',
          'private_key': 'KEY',
        },
      ),
      Entry(
        id: '5',
        kind: 'note',
        title: 'Bank recovery codes',
        notes: '4821-9930',
      ),
      Entry(
        id: '6',
        title: 'Instagram',
        website: 'instagram.com',
        username: 'ahmed.makes',
        password: 'x',
      ),
    ];
    Session.vault = v;

    Future<void> shot(
      Widget page,
      String name, {
      bool dark = false,
      Future<void> Function()? act,
    }) async {
      final key = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Envelope.light, Brightness.light),
            darkTheme: buildTheme(Envelope.dark, Brightness.dark),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: page,
          ),
        ),
      );
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      if (act != null) {
        await act();
        await t.pumpAndSettle();
      }
      await t.runAsync(() async {
        final img =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    await shot(const UnlockPage(), 'phone-lock');
    await shot(const HomePage(), 'phone');
    await shot(const HomePage(), 'phone-dark', dark: true);
    await shot(
      EntryViewPage(entry: v.entries.first),
      'phone-entry',
      act: () async {
        await t.tap(find.byTooltip('Show').first);
      },
    );
    await shot(EntryViewPage(entry: v.entries[3]), 'phone-entry-sealed');
    await shot(const GeneratorPage(), 'phone-generator');
    await shot(const SyncPage(), 'phone-sync');
    await t.pump(const Duration(seconds: 30)); // let reveal timers finish
    dir.deleteSync(recursive: true);
  }, skip: !on);
}
