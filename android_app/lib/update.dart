/// Updates for the phone. Mirrors myvault/update.py (see it for the design).
///
/// Packages arrive over QR sync from a newer PC, or online from GitHub Releases
/// if the user said yes. Nothing is stored, offered or installed unless the
/// release manifest carries a valid Ed25519 signature from MyVault's update key
/// and the file matches the manifest's SHA-256. Before installing, Android-side
/// code also checks the APK is this very app (same package, same signing key).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cryptography/cryptography.dart' as ed;
import 'package:pointycastle/export.dart' show SHA256Digest;

import 'version.dart';

const platformName = 'android';

/// MyVault's update key (public half). Same as UPDATE_PUBKEY in myvault/update.py.
/// Not const only so the cross-language test can use a throwaway key.
@visibleForTesting
String updatePubKeyHex =
    'ac26f647835b4fa6349e66b4646feadf04cba6b42d8efda57fa0404f5a0d547e';
const _repo = 'AhmedMKAlzoubi/myvault';
const latestUrl =
    'https://github.com/$_repo/releases/latest/download/latest.json';
String assetUrl(String version, String name) =>
    'https://github.com/$_repo/releases/download/v$version/$name';
final _nameRe = RegExp(r'^MyVault[A-Za-z0-9._-]{1,80}\.(exe|apk)$');
final _verRe = RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}$');

class UpdateException implements Exception {
  final String message;
  UpdateException(this.message);
  @override
  String toString() => message;
}

List<int> vtuple(String v) =>
    _verRe.hasMatch(v) ? v.split('.').map(int.parse).toList() : [0];

bool isNewer(String a, String b) {
  final x = vtuple(a), y = vtuple(b);
  for (var i = 0; i < 3; i++) {
    final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
    if (p != q) return p > q;
  }
  return false;
}

/// Check the Ed25519 signature over the exact manifest bytes, then parse.
Future<Map<String, dynamic>> verifyManifest(
  List<int> raw,
  String sigB64,
) async {
  bool ok;
  try {
    final key = [
      for (var i = 0; i < updatePubKeyHex.length; i += 2)
        int.parse(updatePubKeyHex.substring(i, i + 2), radix: 16),
    ];
    ok = await ed.Ed25519().verify(
      raw,
      signature: ed.Signature(
        base64.decode(sigB64.trim()),
        publicKey: ed.SimplePublicKey(key, type: ed.KeyPairType.ed25519),
      ),
    );
  } catch (_) {
    ok = false;
  }
  if (!ok) {
    throw UpdateException("This update isn't signed by MyVault's update key.");
  }
  return parseManifest(raw);
}

/// Parse a manifest. Only call on bytes [verifyManifest] has checked.
Map<String, dynamic> parseManifest(List<int> raw) {
  final m = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
  if (m['app'] != 'MyVault' || !_verRe.hasMatch('${m['version']}')) {
    throw UpdateException("That isn't a MyVault release manifest.");
  }
  for (final f in ((m['files'] ?? {}) as Map).values) {
    if (!_nameRe.hasMatch('${f['name']}') ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch('${f['sha256']}')) {
      throw UpdateException('Bad file entry in the manifest.');
    }
  }
  return m;
}

Future<String> sha256File(File f) async {
  final d = SHA256Digest();
  await for (final chunk in f.openRead()) {
    d.update(Uint8List.fromList(chunk), 0, chunk.length);
  }
  final out = Uint8List(32);
  d.doFinal(out, 0);
  return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class Package {
  final String platform, version;
  final File file;
  final List<int> manifest;
  final String sig;
  Package(this.platform, this.version, this.file, this.manifest, this.sig);
}

/// Lets tests (test/interop_sync_test.dart) use a temp folder instead.
@visibleForTesting
Directory? supportDirOverride;

Future<Directory> _support() async =>
    supportDirOverride ?? await getApplicationSupportDirectory();

Future<Directory> _root() async {
  final d = Directory('${(await _support()).path}/packages');
  if (!d.existsSync()) d.createSync(recursive: true);
  return d;
}

/// The newest intact package per platform held on this phone.
Future<Map<String, Package>> packages() async {
  final best = <String, Package>{};
  final root = await _root();
  for (final dir in root.listSync().whereType<Directory>()) {
    for (final mf in dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.json'),
    )) {
      final sigFile = File(mf.path.replaceAll(RegExp(r'\.json$'), '.sig'));
      if (!sigFile.existsSync()) continue;
      try {
        final raw = mf.readAsBytesSync();
        final m = await verifyManifest(raw, sigFile.readAsStringSync());
        for (final e in (m['files'] as Map).entries) {
          final f = File('${dir.path}/${e.value['name']}');
          if (!f.existsSync() || f.lengthSync() != e.value['size']) continue;
          final plat = e.key as String;
          if (best[plat] == null ||
              isNewer(m['version'] as String, best[plat]!.version)) {
            best[plat] = Package(
              plat,
              m['version'] as String,
              f,
              raw,
              sigFile.readAsStringSync().trim(),
            );
          }
        }
      } catch (_) {
        continue;
      }
    }
  }
  return best;
}

Future<Map<String, String>> offers() async => {
  for (final p in (await packages()).values) p.platform: p.version,
};

/// Check a received/downloaded file against its manifest, then keep it.
Future<Package> store(
  List<int> manifest,
  String sig,
  String platform,
  File tmp,
) async {
  final m = await verifyManifest(manifest, sig);
  final f = (m['files'] as Map)[platform];
  if (f == null) {
    throw UpdateException("The manifest doesn't list that package.");
  }
  if (tmp.lengthSync() != f['size'] || await sha256File(tmp) != f['sha256']) {
    throw UpdateException(
      "The update file is damaged (its fingerprint doesn't match).",
    );
  }
  final dir = Directory('${(await _root()).path}/${m['version']}')
    ..createSync(recursive: true);
  final dest = await tmp.copy('${dir.path}/${f['name']}');
  await tmp.delete();
  File('${dir.path}/manifest-$platform.json').writeAsBytesSync(manifest);
  File('${dir.path}/manifest-$platform.sig').writeAsStringSync(sig);
  return Package(platform, m['version'] as String, dest, manifest, sig);
}

/// A downloaded/received APK newer than this app, waiting to be installed.
Future<Package?> readyApk() async {
  final p = (await packages())[platformName];
  return p != null && isNewer(p.version, appVersion) ? p : null;
}

// ---- preferences (a tiny JSON file; no extra plugin) -----------------------
Future<File> _prefsFile() async =>
    File('${(await _support()).path}/update_prefs.json');

Future<Map<String, dynamic>> loadPrefs() async {
  try {
    return jsonDecode(await (await _prefsFile()).readAsString())
        as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

Future<void> savePrefs(Map<String, dynamic> p) async =>
    (await _prefsFile()).writeAsString(jsonEncode(p));

// ---- online ------------------------------------------------------------------
Future<List<int>> _get(
  String url,
  int limit, {
  void Function(int)? onBytes,
  IOSink? sink,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', 'MyVault-update-check');
    final res = await req.close();
    if (res.statusCode == 404) {
      throw UpdateException('No release has been published yet.');
    }
    if (res.statusCode != 200) {
      throw UpdateException('GitHub answered ${res.statusCode}.');
    }
    final out = <int>[];
    var got = 0;
    await for (final chunk in res) {
      got += chunk.length;
      if (got > limit) throw UpdateException('Unexpectedly large download.');
      if (sink != null) {
        sink.add(chunk);
      } else {
        out.addAll(chunk);
      }
      onBytes?.call(got);
    }
    return out;
  } on SocketException {
    throw UpdateException(
      "Couldn't reach GitHub. Check your internet connection.",
    );
  } finally {
    client.close();
  }
}

class Release {
  final Map<String, dynamic> manifest;
  final List<int> raw;
  final String sig;
  Release(this.manifest, this.raw, this.sig);
  String get version => manifest['version'] as String;
  int sizeOf(String plat) =>
      (((manifest['files'] as Map)[plat] ?? {})['size'] ?? 0) as int;
}

Future<Release> checkOnline() async {
  final raw = await _get(latestUrl, 64 * 1024);
  final sig = utf8.decode(await _get('$latestUrl.sig', 1024)).trim();
  return Release(await verifyManifest(raw, sig), raw, sig);
}

Future<Package> download(
  Release r,
  String platform, {
  void Function(double)? progress,
}) async {
  final f = (r.manifest['files'] as Map)[platform];
  if (f == null) {
    throw UpdateException('This release has no $platform package.');
  }
  final size = f['size'] as int;
  final tmp = File('${(await _root()).path}/${f['name']}.part');
  final sink = tmp.openWrite();
  try {
    await _get(
      assetUrl(r.version, f['name'] as String),
      size,
      sink: sink,
      onBytes: (n) => progress?.call(n / size),
    );
  } finally {
    await sink.close();
  }
  return store(r.raw, r.sig, platform, tmp);
}

/// A Google Play build (`flutter build appbundle --flavor play`): Play does the
/// updates, so MyVault never checks GitHub or installs APKs itself.
final storeBuild = appFlavor == 'play';

// ---- installing ----------------------------------------------------------------
const _ch = MethodChannel('myvault/update');

/// Hands the APK to Android's installer. Returns false when the user first has
/// to allow "Install unknown apps" for MyVault (Android opens that screen).
Future<bool> installApk(Package p) async {
  try {
    return (await _ch.invokeMethod<bool>('installApk', p.file.path)) ?? false;
  } on PlatformException catch (e) {
    throw UpdateException(e.message ?? "That update can't be installed.");
  }
}
