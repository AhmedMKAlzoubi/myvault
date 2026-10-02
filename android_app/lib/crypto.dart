/// Dart port of MyVault's encryption. MUST stay byte-compatible with the
/// Python version (see VAULT_FORMAT.md): scrypt (N=32768,r=8,p=1) -> AES-256-GCM,
/// where the stored `data` is ciphertext followed by the 16-byte GCM tag.
///
/// PointyCastle's GCMBlockCipher already appends/consumes the tag in exactly
/// that layout, and its Scrypt matches Python's, so files interoperate.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

const _magic = 'MYVAULT';
const _formatVersion = 1;
const _scryptN = 32768;
const _scryptR = 8;
const _scryptP = 1;
const _keyLen = 32;
const _saltLen = 16;
const _nonceLen = 12;
const _tagBits = 128;

class WrongPasswordException implements Exception {
  final String message;
  WrongPasswordException([this.message = 'Wrong master password.']);
  @override
  String toString() => message;
}

class VaultFormatException implements Exception {
  final String message;
  VaultFormatException([this.message = 'Unrecognized vault file.']);
  @override
  String toString() => message;
}

Uint8List _randomBytes(int n) {
  final rnd = Random.secure();
  return Uint8List.fromList(List<int>.generate(n, (_) => rnd.nextInt(256)));
}

Uint8List _deriveKey(
  String password,
  Uint8List salt,
  int n,
  int r,
  int p,
  int dkLen,
) {
  final derivator = Scrypt()..init(ScryptParameters(n, r, p, dkLen, salt));
  return derivator.process(Uint8List.fromList(utf8.encode(password)));
}

Uint8List _gcm(
  bool forEncryption,
  Uint8List key,
  Uint8List nonce,
  Uint8List input,
) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      forEncryption,
      AEADParameters(KeyParameter(key), _tagBits, nonce, Uint8List(0)),
    );
  return cipher.process(input);
}

/// Encrypt raw bytes into a full MyVault file (UTF-8 JSON envelope).
Uint8List encryptBytes(Uint8List plaintext, String password) {
  final salt = _randomBytes(_saltLen);
  final key = _deriveKey(password, salt, _scryptN, _scryptR, _scryptP, _keyLen);
  final nonce = _randomBytes(_nonceLen);
  final data = _gcm(true, key, nonce, plaintext); // ciphertext + tag

  final envelope = {
    'magic': _magic,
    'version': _formatVersion,
    'kdf': {
      'algo': 'scrypt',
      'n': _scryptN,
      'r': _scryptR,
      'p': _scryptP,
      'dklen': _keyLen,
      'salt': base64.encode(salt),
    },
    'cipher': {
      'algo': 'AES-256-GCM',
      'nonce': base64.encode(nonce),
      'data': base64.encode(data),
    },
  };
  return Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(envelope)),
  );
}

/// Decrypt a MyVault file. Throws [WrongPasswordException] on bad password/tamper.
Uint8List decryptBytes(Uint8List fileBytes, String password) {
  final Map<String, dynamic> envelope;
  try {
    envelope = jsonDecode(utf8.decode(fileBytes)) as Map<String, dynamic>;
  } catch (_) {
    throw VaultFormatException('File is not valid MyVault data.');
  }
  if (envelope['magic'] != _magic) {
    throw VaultFormatException('This is not a MyVault file.');
  }
  final Uint8List salt, nonce, data;
  final int n, r, p, dkLen;
  try {
    final kdf = envelope['kdf'] as Map<String, dynamic>;
    salt = base64.decode(kdf['salt'] as String);
    n = kdf['n'] as int;
    r = kdf['r'] as int;
    p = kdf['p'] as int;
    dkLen = kdf['dklen'] as int;
    final cipher = envelope['cipher'] as Map<String, dynamic>;
    nonce = base64.decode(cipher['nonce'] as String);
    data = base64.decode(cipher['data'] as String);
  } catch (_) {
    throw VaultFormatException('The vault file is corrupt or unreadable.');
  }
  final key = _deriveKey(password, salt, n, r, p, dkLen);
  try {
    return _gcm(false, key, nonce, data);
  } on InvalidCipherTextException {
    throw WrongPasswordException(
      'Wrong master password (or the file was altered).',
    );
  }
}
