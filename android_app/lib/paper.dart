/// Restore from a paper backup (the encrypted PDF printed by the PC app).
/// Mirrors myvault/paper.py: each QR code on the sheet is one Base32 block
///   "MVP1" | salt(16) | nonce(12) | AES-256-GCM(zlib(entry JSON), aad="MVP1"+salt)
/// with key = scrypt(backup password, salt, N=2^17, r=8, p=1).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'vault.dart';

final _magic = Uint8List.fromList(utf8.encode('MVP1'));
const _b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// RFC 4648 Base32, ignoring spaces, case and padding. Null if it isn't Base32.
Uint8List? base32Decode(String text) {
  final clean = text.toUpperCase().replaceAll(RegExp(r'[\s=]'), '');
  final out = <int>[];
  var buf = 0, bits = 0;
  for (final ch in clean.split('')) {
    final v = _b32.indexOf(ch);
    if (v < 0) return null;
    buf = (buf << 5) | v;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.add((buf >> bits) & 0xff);
    }
  }
  return Uint8List.fromList(out);
}

class PaperBlock {
  final Uint8List salt, nonce, ct;
  PaperBlock(this.salt, this.nonce, this.ct);

  /// Null when the text isn't a MyVault backup block.
  static PaperBlock? parse(String text) {
    final raw = base32Decode(text);
    if (raw == null || raw.length < 4 + 16 + 12 + 16) return null;
    for (var i = 0; i < 4; i++) {
      if (raw[i] != _magic[i]) return null;
    }
    return PaperBlock(raw.sublist(4, 20), raw.sublist(20, 32), raw.sublist(32));
  }

  String get saltKey => base64.encode(salt);
}

Uint8List _scrypt((String, Uint8List) a) {
  final d = Scrypt()..init(ScryptParameters(1 << 17, 8, 1, 32, a.$2));
  return d.process(Uint8List.fromList(utf8.encode(a.$1)));
}

/// Deliberately slow (that's what protects the paper). Runs off the UI thread.
Future<Uint8List> deriveBackupKey(String password, Uint8List salt) =>
    Isolate.run(() => _scrypt((password, salt)));

/// Decrypts one block. Throws InvalidCipherTextException on a wrong password.
Entry decryptBlock(PaperBlock b, Uint8List key) {
  final aad = Uint8List.fromList([..._magic, ...b.salt]);
  final gcm = GCMBlockCipher(AESEngine())
    ..init(false, AEADParameters(KeyParameter(key), 128, b.nonce, aad));
  final body = gcm.process(b.ct);
  final json =
      jsonDecode(utf8.decode(zlib.decode(body))) as Map<String, dynamic>;
  return Entry.fromJson(json);
}
