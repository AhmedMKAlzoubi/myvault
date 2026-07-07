/// Password generator — mirrors the Python version so behavior matches across
/// devices. Uses Random.secure() (OS CSPRNG).
library;

import 'dart:math';

const _lower = 'abcdefghijklmnopqrstuvwxyz';
const _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const _digits = '0123456789';
const defaultSymbols = '!@#\$%^&*-_=+?';
const _ambiguous = 'Il1O0o|`\'"{}[]()/\\~,;:.<>';

class PasswordPolicy {
  int length;
  bool useLower;
  bool useUpper;
  bool useDigits;
  bool useSymbols;
  bool avoidAmbiguous;
  String allowedSymbols;

  PasswordPolicy({
    this.length = 16,
    this.useLower = true,
    this.useUpper = true,
    this.useDigits = true,
    this.useSymbols = true,
    this.avoidAmbiguous = true,
    this.allowedSymbols = defaultSymbols,
  });

  Map<String, dynamic> toJson() => {
        'length': length,
        'use_lower': useLower,
        'use_upper': useUpper,
        'use_digits': useDigits,
        'use_symbols': useSymbols,
        'avoid_ambiguous': avoidAmbiguous,
        'allowed_symbols': allowedSymbols,
      };

  factory PasswordPolicy.fromJson(Map<String, dynamic>? j) {
    if (j == null) return PasswordPolicy();
    return PasswordPolicy(
      length: (j['length'] ?? 16) as int,
      useLower: (j['use_lower'] ?? true) as bool,
      useUpper: (j['use_upper'] ?? true) as bool,
      useDigits: (j['use_digits'] ?? true) as bool,
      useSymbols: (j['use_symbols'] ?? true) as bool,
      avoidAmbiguous: (j['avoid_ambiguous'] ?? true) as bool,
      allowedSymbols: (j['allowed_symbols'] ?? defaultSymbols) as String,
    );
  }
}

String _strip(String s) {
  if (s.isEmpty) return s;
  final set = _ambiguous.split('').toSet();
  return s.split('').where((c) => !set.contains(c)).join();
}

String generatePassword(PasswordPolicy p) {
  final rnd = Random.secure();
  var groups = <String>[];
  if (p.useLower) groups.add(_lower);
  if (p.useUpper) groups.add(_upper);
  if (p.useDigits) groups.add(_digits);
  if (p.useSymbols && p.allowedSymbols.isNotEmpty) groups.add(p.allowedSymbols);
  if (p.avoidAmbiguous) groups = groups.map(_strip).toList();
  groups = groups.where((g) => g.isNotEmpty).toList();
  final pool = groups.join();
  if (pool.isEmpty) {
    throw ArgumentError('Enable at least one character type.');
  }
  final length = [p.length, groups.length, 1].reduce(max);

  final chars = <String>[];
  for (final g in groups) {
    chars.add(g[rnd.nextInt(g.length)]);
  }
  while (chars.length < length) {
    chars.add(pool[rnd.nextInt(pool.length)]);
  }
  // Fisher-Yates shuffle with secure RNG.
  for (var i = chars.length - 1; i > 0; i--) {
    final j = rnd.nextInt(i + 1);
    final t = chars[i];
    chars[i] = chars[j];
    chars[j] = t;
  }
  return chars.join();
}

String strengthLabel(String pw) {
  if (pw.isEmpty) return '';
  var pool = 0;
  if (pw.contains(RegExp(r'[a-z]'))) pool += 26;
  if (pw.contains(RegExp(r'[A-Z]'))) pool += 26;
  if (pw.contains(RegExp(r'[0-9]'))) pool += 10;
  if (pw.contains(RegExp(r'[^A-Za-z0-9]'))) pool += 20;
  final bits = pool == 0 ? 0.0 : pw.length * (log(pool) / log(2));
  if (bits < 40) return 'Weak';
  if (bits < 70) return 'Okay';
  if (bits < 100) return 'Strong';
  return 'Very strong';
}
