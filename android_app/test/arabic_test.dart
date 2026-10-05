// The phone app in Arabic: every screen's text is translated, the layout is
// right to left, and vault data (names, passwords) is shown exactly as saved.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myvault/documents_ui.dart';
import 'package:myvault/l10n.dart';
import 'package:myvault/l10n_ar.dart';
import 'package:myvault/main.dart';
import 'package:myvault/theme.dart';
import 'package:myvault/update_ui.dart';
import 'package:myvault/vault.dart';

// Names and terms that stay in Latin letters in the Arabic interface.
final _keep = RegExp(
  r'MyVault|GitHub|Android|Chrome|PDF|JPG|PNG|WebP|Wi.Fi|WiFi|API|SSH|QR|PIN|APK|GPL-3\.0|URL|'
  r'ahmedmohammedkhear@gmail\.com|l و1 وO و0 وI|English',
);

List<String> _english(WidgetTester t, Set<String> data) {
  final left = <String>[];
  for (final w in t.widgetList(
    find.byWidgetPredicate((w) => w is Text || w is RichText),
  )) {
    final s = w is Text
        ? (w.data ?? w.textSpan?.toPlainText() ?? '')
        : (w as RichText).text.toPlainText();
    final dir = w is Text ? w.textDirection : (w as RichText).textDirection;
    // passwords and code are data, shown left to right
    if (dir == TextDirection.ltr) continue;
    final rest = data
        .fold(s, (r, d) => r.replaceAll(d, ''))
        .replaceAll(_keep, '');
    if (RegExp(r'[A-Za-z]{2,}').hasMatch(rest)) left.add(s);
  }
  return left;
}

Widget _app(Widget home) => MaterialApp(
  theme: buildTheme(Envelope.light, Brightness.light),
  locale: const Locale('ar'),
  supportedLocales: const [Locale('en'), Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: home,
);

void main() {
  setUp(() => language.value = 'ar');
  tearDown(() => language.value = 'auto');

  test('tr: exact, patterns, {t0} groups, untouched data', () {
    expect(tr('Unlock'), 'فتح');
    expect(tr('  Unlock '), '  فتح ');
    expect(tr('Copy password'), 'نسخ كلمة المرور');
    expect(
      tr('Password copied. It clears from the clipboard in 30 s.'),
      'تم نسخ كلمة المرور. سيُمسح من الحافظة بعد 30 ثانية.',
    );
    expect(tr('Strength: Very strong'), 'القوة: قوية جدًا');
    expect(tr('Nothing matches “bank”'), 'لا شيء يطابق «bank»');
    expect(
      tr('Locked after 5 minutes without use.'),
      'أُقفل بعد 5 دقائق من عدم الاستخدام.',
    );
    expect(tr('My own note title'), 'My own note title');
    language.value = 'en';
    expect(tr('Unlock'), 'Unlock');
  });

  test('every Arabic entry keeps its placeholders', () {
    final ph = RegExp(r'\{t?\d\}');
    for (final e in arabic.entries) {
      expect(e.value.trim(), isNotEmpty, reason: e.key);
      expect(
        (ph.allMatches(e.value).map((m) => m[0]).toList()..sort()),
        (ph.allMatches(e.key).map((m) => m[0]).toList()..sort()),
        reason: e.key,
      );
    }
  });

  testWidgets('screens are translated and right to left', (t) async {
    final dir = Directory.systemTemp.createTempSync('mv_ar');
    vaultPathOverride = '${dir.path}/vault.dat';
    final v = await t.runAsync(
      () async => Vault.create(vaultPathOverride!, 'arabic-test'),
    );
    final login = Entry(
      title: 'GitHub work',
      website: 'github.com',
      username: 'ahmed-dev',
      password: 'Pw!2?abc',
    );
    v!.add(login);
    final passport = Entry(
      kind: 'document',
      title: 'Family passport',
      fields: {
        'doc_type': 'passport',
        'holder': 'Ahmed Mohammed',
        'country': 'Jordan',
        'expires': '2026-11-20',
        'remind': '30,7',
      },
    );
    v.add(passport);
    Session.open(v);
    final data = {
      'GitHub work',
      'github.com',
      'ahmed-dev',
      'Pw!2?abc',
      'Family passport',
      'Ahmed Mohammed',
      'Jordan',
    };

    final pages = <String, Widget>{
      'home': const HomePage(),
      'entry': EntryViewPage(entry: login),
      'edit': EntryEditPage(entry: login),
      'new': EntryEditPage(entry: Entry(), isNew: true),
      'generator': const GeneratorPage(),
      'change master': const ChangeMasterPage(),
      'auto-lock': const AutoLockPage(),
      'language': const LanguagePage(),
      'about': const AboutPage(),
      'restore': const RestorePaperPage(),
      'document': EntryViewPage(entry: passport),
      'edit document': EntryEditPage(entry: passport),
      'new document': EntryEditPage(
        entry: Entry(kind: 'document'),
        isNew: true,
      ),
      'documents settings': const DocumentsSettingsPage(),
    };
    for (final p in pages.entries) {
      await t.pumpWidget(_app(p.value));
      await t.pump(const Duration(milliseconds: 100));
      expect(_english(t, data), isEmpty, reason: p.key);
      expect(
        Directionality.of(t.element(find.byType(Scaffold).first)),
        TextDirection.rtl,
        reason: p.key,
      );
    }

    // a password is shown exactly as saved, left to right
    await t.pumpWidget(_app(EntryViewPage(entry: login)));
    await t.tap(find.byTooltip('إظهار').first);
    await t.pump();
    final shown = t.widget<Text>(find.text('Pw!2?abc'));
    expect(shown.textDirection, TextDirection.ltr);
    Session.lock();
    await t.pumpWidget(const SizedBox());
    await t.pump(
      const Duration(seconds: 25),
    ); // let the reveal's re-cover timer finish
  });
}
