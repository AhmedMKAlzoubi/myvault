/// Interface language. English is written in the code; [arabic] (l10n_ar.dart)
/// maps each English string to Arabic, the same way as the PC's ui/ar.json:
/// keys with {0}, {1}… match strings built with interpolation, and a {t0}
/// group is translated as well. Vault data is never passed through [tr].
library;

import 'package:flutter/widgets.dart';

import 'l10n_ar.dart';

/// 'auto' (the phone's language), 'en' or 'ar'. Saved in prefs as 'language'.
final language = ValueNotifier<String>('auto');
const languageChoices = ['auto', 'en', 'ar'];

bool get isArabic =>
    language.value == 'ar' ||
    (language.value == 'auto' &&
        WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'ar');

class _Pattern {
  final RegExp rx;
  final List<String> names = [];
  final String out;
  _Pattern(String key, this.out) : rx = _compile(key) {
    for (final m in RegExp(r'\{(t?\d)\}').allMatches(key)) {
      names.add(m.group(1)!);
    }
  }
  static RegExp _compile(String key) {
    final body = key.splitMapJoin(
      RegExp(r'\{t?\d\}'),
      onMatch: (_) => r'([\s\S]+?)',
      onNonMatch: RegExp.escape,
    );
    return RegExp('^$body\$');
  }

  String fill(RegExpMatch m) =>
      out.replaceAllMapped(RegExp(r'\{(t?\d)\}'), (p) {
        final n = p.group(1)!;
        final v = m.group(names.indexOf(n) + 1)!;
        return n.startsWith('t') ? _word(v) : v;
      });
}

final _patterns = [
  for (final k
      in arabic.keys.where((k) => RegExp(r'\{t?\d\}').hasMatch(k)).toList()
        ..sort((a, b) => b.length - a.length))
    _Pattern(k, arabic[k]!),
];
final _lower = {for (final e in arabic.entries) e.key.toLowerCase(): e.value};

String _word(String v) {
  final x = tr(v);
  return x != v ? x : _lower[v.toLowerCase()] ?? v;
}

/// The string in the interface language.
String tr(String s) {
  if (!isArabic) return s;
  final core = s.trim();
  if (core.isEmpty) return s;
  final hit = arabic[core];
  if (hit != null) return s.replaceFirst(core, hit);
  for (final p in _patterns) {
    final m = p.rx.firstMatch(core);
    if (m != null) return s.replaceFirst(core, p.fill(m));
  }
  return s;
}
