import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myvault/main.dart';
import 'package:myvault/theme.dart';
import 'package:myvault/vault.dart';

void main() {
  testWidgets('a saved password needs "Change password" and can be put back', (
    t,
  ) async {
    final entry = Entry(
      title: 'GitHub',
      website: 'github.com',
      password: 'OldSecret#1',
    );
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Envelope.light, Brightness.light),
        home: EntryEditPage(entry: entry),
      ),
    );
    TextField pw() => t.widget<TextField>(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Password',
      ),
    );

    expect(pw().readOnly, isTrue);
    expect(find.byTooltip('Generate'), findsNothing);
    expect(find.byTooltip('Change password'), findsOneWidget);

    await t.tap(find.byTooltip('Change password'));
    await t.pumpAndSettle();
    expect(find.text('Replace this password?'), findsOneWidget);
    await t.tap(find.text('Keep it'));
    await t.pumpAndSettle();
    expect(pw().controller!.text, 'OldSecret#1');

    await t.tap(find.byTooltip('Change password'));
    await t.pumpAndSettle();
    await t.tap(find.text('Type a new one'));
    await t.pumpAndSettle();
    expect(pw().readOnly, isFalse);
    expect(pw().controller!.text, isEmpty);
    expect(find.byTooltip('Generate'), findsOneWidget);

    await t.tap(find.text('Keep the old password'));
    await t.pumpAndSettle();
    expect(pw().controller!.text, 'OldSecret#1');
    expect(pw().readOnly, isTrue);
  });

  testWidgets('a new login offers Generate straight away', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Envelope.light, Brightness.light),
        home: EntryEditPage(entry: Entry(), isNew: true),
      ),
    );
    expect(find.byTooltip('Generate'), findsOneWidget);
    expect(find.byTooltip('Change password'), findsNothing);
  });
}
