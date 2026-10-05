/// Two-factor codes (TOTP, RFC 6238), the same rules as myvault/otp.py.
/// test_fixtures/otp_cases.json checks both.
library;

import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class OtpSpec {
  final String secret, algorithm, issuer, account;
  final int digits, period;
  const OtpSpec(
    this.secret, {
    this.digits = 6,
    this.period = 30,
    this.algorithm = 'SHA1',
    this.issuer = '',
    this.account = '',
  });
}

/// Throws FormatException if [text] isn't a 2FA secret or otpauth:// link.
OtpSpec parseOtp(String text) {
  text = text.trim();
  var digits = 6, period = 30;
  var alg = 'SHA1', issuer = '', account = '';
  if (text.toLowerCase().startsWith('otpauth://')) {
    final u = Uri.tryParse(text);
    if (u == null || u.host.toLowerCase() != 'totp') {
      throw const FormatException(
        'Only time-based codes (TOTP) are supported.',
      );
    }
    final q = {
      for (final e in u.queryParameters.entries) e.key.toLowerCase(): e.value,
    };
    final label = Uri.decodeComponent(u.path.replaceFirst(RegExp('^/'), ''));
    final i = label.lastIndexOf(':');
    issuer = (q['issuer'] ?? (i < 0 ? '' : label.substring(0, i))).trim();
    account = label.substring(i + 1).trim();
    final d = int.tryParse(q['digits'] ?? '6'),
        p = int.tryParse(q['period'] ?? '30');
    if (d == null || p == null) {
      throw const FormatException("That 2FA link isn't valid.");
    }
    digits = d;
    period = p;
    alg = (q['algorithm'] ?? 'SHA1').toUpperCase();
    text = q['secret'] ?? '';
  }
  final secret = text
      .replaceAll(RegExp(r'[\s-]'), '')
      .toUpperCase()
      .replaceFirst(RegExp(r'=+$'), '');
  if (!RegExp(r'^[A-Z2-7]{16,}$').hasMatch(secret) ||
      !_digests.containsKey(alg) ||
      ![6, 7, 8].contains(digits) ||
      period < 10 ||
      period > 300) {
    throw const FormatException(
      "That isn't a 2FA secret. Paste the setup key or the otpauth:// link.",
    );
  }
  return OtpSpec(
    secret,
    digits: digits,
    period: period,
    algorithm: alg,
    issuer: issuer,
    account: account,
  );
}

final _digests = <String, Digest Function()>{
  'SHA1': SHA1Digest.new,
  'SHA256': SHA256Digest.new,
  'SHA512': SHA512Digest.new,
};

Uint8List _base32(String s) {
  const abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final out = <int>[];
  var buf = 0, bits = 0;
  for (final c in s.split('')) {
    buf = (buf << 5) | abc.indexOf(c);
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.add((buf >> bits) & 0xff);
    }
  }
  return Uint8List.fromList(out);
}

/// The current code and the seconds it stays valid. [now] is in seconds.
(String, int) otpCode(Object spec, {double? now}) {
  final s = spec is OtpSpec ? spec : parseOtp('$spec');
  final t = (now ?? DateTime.now().millisecondsSinceEpoch / 1000).floor();
  final mac = HMac.withDigest(_digests[s.algorithm]!())
    ..init(KeyParameter(_base32(s.secret)));
  final counter = ByteData(8)..setInt64(0, t ~/ s.period);
  final h = mac.process(counter.buffer.asUint8List());
  final o = h.last & 0x0f;
  final n =
      (ByteData.sublistView(h, o, o + 4).getUint32(0) & 0x7fffffff) %
      _pow10(s.digits);
  return ('$n'.padLeft(s.digits, '0'), s.period - t % s.period);
}

int _pow10(int n) => n == 0 ? 1 : 10 * _pow10(n - 1);
