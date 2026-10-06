/// Unlock with a fingerprint or face (BiometricBridge.kt): the master password
/// is kept encrypted by a Keystore key that only a strong biometric opens.
library;

import 'package:flutter/services.dart';

import 'l10n.dart';
import 'vaults.dart';

const _ch = MethodChannel('myvault/biometric');

/// (the phone can do it, it's turned on).
Future<(bool, bool)> bioStatus() async {
  try {
    final m =
        await _ch.invokeMapMethod<String, dynamic>('status', {
          'vault': currentVault,
        }) ??
        {};
    return (m['available'] == true, m['enabled'] == true);
  } on MissingPluginException {
    return (false, false); // tests, or an activity without the bridge
  }
}

Map<String, String> _texts(String title) => {
  'vault': currentVault,
  'title': tr(title),
  'cancel': tr('Use the password'),
};

/// Asks for a fingerprint, then remembers [password]. False if cancelled.
Future<bool> bioEnable(String password) async {
  try {
    return await _ch.invokeMethod<bool>('enable', {
          'password': password,
          ..._texts('Turn on fingerprint unlock'),
        }) ==
        true;
  } on PlatformException {
    return false;
  }
}

/// The master password after a fingerprint; null if cancelled. Throws
/// PlatformException('changed') when the phone's fingerprints changed.
Future<String?> bioUnlock() async {
  try {
    return await _ch.invokeMethod<String>('unlock', _texts('Unlock MyVault'));
  } on PlatformException catch (e) {
    if (e.code == 'changed') rethrow;
    return null;
  }
}

Future<void> bioDisable() async {
  try {
    await _ch.invokeMethod('disable', {'vault': currentVault});
  } on MissingPluginException {
    // nothing to turn off
  }
}
