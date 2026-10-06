/// Password health: weak and reused passwords, and (only when asked) leaked
/// ones. The same as myvault/health.py: the leak check sends Have I Been Pwned
/// only the first 5 characters of each password's SHA-1 hash.
library;

import 'dart:convert';
import 'dart:io';

import 'package:pointycastle/export.dart';

import 'generator.dart';
import 'vault.dart';

class HealthReport {
  final int total;
  final List<Entry> weak;
  final List<List<Entry>> reused;
  const HealthReport(this.total, this.weak, this.reused);
}

HealthReport healthReport(List<Entry> entries) {
  final logins = [
    for (final e in entries)
      if (!e.deleted && e.kind == 'login' && e.password.isNotEmpty) e,
  ];
  final same = <String, List<Entry>>{};
  for (final e in logins) {
    (same[e.password] ??= []).add(e);
  }
  return HealthReport(
    logins.length,
    [
      for (final e in logins)
        if (strengthLabel(e.password) == 'Weak') e,
    ],
    [
      for (final g in same.values)
        if (g.length > 1) g,
    ],
  );
}

String _sha1(String s) => SHA1Digest()
    .process(utf8.encode(s))
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join()
    .toUpperCase();

Future<String> _fetch(String prefix) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await c.getUrl(
      Uri.parse('https://api.pwnedpasswords.com/range/$prefix'),
    );
    req.headers
      ..set('Add-Padding', 'true')
      ..set('User-Agent', 'MyVault');
    final res = await req.close();
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    return await res.transform(utf8.decoder).join();
  } finally {
    c.close();
  }
}

/// How many times each password appears in known leaks (0 = not found).
Future<Map<String, int>> leakCounts(
  Iterable<String> passwords, {
  Future<String> Function(String prefix) fetch = _fetch,
}) async {
  final out = <String, int>{};
  for (final pw in passwords.toSet()) {
    final h = _sha1(pw);
    final counts = <String, int>{};
    for (final line in const LineSplitter().convert(
      await fetch(h.substring(0, 5)),
    )) {
      final i = line.indexOf(':');
      if (i > 0) {
        counts[line.substring(0, i).trim()] =
            int.tryParse(line.substring(i + 1).trim()) ?? 0;
      }
    }
    out[pw] = counts[h.substring(5)] ?? 0;
  }
  return out;
}
