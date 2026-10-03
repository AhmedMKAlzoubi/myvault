// Cross-language QR sync check: Dart phone client <-> Python PC server.
// Skipped unless MYVAULT_SYNC_URI is set. Run with:  python tests/interop_sync.py
//
// Besides entries, it checks the update hand-over in both directions in one
// session: the (newer) PC passes the phone its APK, and the phone passes the PC
// a Windows installer it holds.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myvault/sync.dart';
import 'package:myvault/update.dart' as upd;
import 'package:myvault/vault.dart';

void main() {
  final env = Platform.environment;
  final uri = env['MYVAULT_SYNC_URI'];
  test(
    'sync with a live Python PairingSession',
    () async {
      upd.supportDirOverride = Directory(env['MYVAULT_PHONE_DIR']!);
      final realKey = upd.updatePubKeyHex;
      addTearDown(() => upd.updatePubKeyHex = realKey);
      upd.updatePubKeyHex =
          env['MYVAULT_UPDATE_PUBKEY']!; // the test's throwaway key
      final dir = Directory.systemTemp.createTempSync('myvault_interop');
      final v = Vault.create('${dir.path}/phone.dat', 'phone-pass');
      v.entries = [
        Entry(
          id: 'from-phone',
          kind: 'ssh',
          title: 'Phone SSH',
          fields: {'private_key': 'PK'},
          updatedAt: 500,
        ),
        Entry(
          id: 'shared',
          title: 'Shared',
          password: 'phone-newer',
          updatedAt: 300,
        ),
      ];
      final r = await syncWithCode(uri!, v);
      expect(r.ok, isTrue, reason: r.error);
      final m = {for (final e in v.entries) e.id: e};
      expect(m['from-pc']!.fields['api_key'], 'PC-KEY');
      expect(m['shared']!.password, 'phone-newer');
      expect(
        Vault.open('${dir.path}/phone.dat', 'phone-pass').entries.length,
        3,
      );

      expect(r.peerVersion, env['MYVAULT_PC_VERSION']);
      expect(r.updateError, '', reason: r.updateError);
      expect(
        r.received?.version,
        env['MYVAULT_PKG_VERSION'],
      ); // APK from the PC
      expect(
        await r.received!.file.length(),
        int.parse(env['MYVAULT_APK_SIZE']!),
      );
      expect(r.sent, env['MYVAULT_PKG_VERSION']); // Windows installer to the PC
      dir.deleteSync(recursive: true);
    },
    skip: uri == null
        ? 'set MYVAULT_SYNC_URI (python tests/interop_sync.py)'
        : false,
  );

  test(
    'the real signed release manifest verifies; altered copies do not',
    () async {
      final raw = File('test_fixtures/release_manifest.json').readAsBytesSync();
      final sig = File(
        'test_fixtures/release_manifest.json.sig',
      ).readAsStringSync();
      final m = await upd.verifyManifest(raw, sig);
      expect(m['version'], '0.5.0');
      final tampered = List<int>.from(raw)..[raw.length ~/ 2] ^= 1;
      expect(
        () => upd.verifyManifest(tampered, sig),
        throwsA(isA<upd.UpdateException>()),
      );
      expect(
        () => upd.verifyManifest(raw, 'AAAA'),
        throwsA(isA<upd.UpdateException>()),
      );
    },
  );

  test('version compare and manifest parsing', () {
    expect(upd.isNewer('0.10.0', '0.9.9'), isTrue);
    expect(upd.isNewer('0.5.0', '0.5.0'), isFalse);
    expect(upd.isNewer('junk', '0.1.0'), isFalse);
    expect(
      () => upd.parseManifest('{"app":"Other","version":"1.0.0"}'.codeUnits),
      throwsA(isA<upd.UpdateException>()),
    );
  });
}
