/// QR sync (phone side). Mirrors myvault/sync.py exactly.
///
/// The PC shows a QR code: `myvault://sync?v=2&h=IPS&p=PORT&k=KEY`.
/// The key is 32 random bytes that only ever travel through the camera. The
/// phone connects over the local WiFi and both sides exchange entries on a
/// channel sealed with that key:
///   4-byte big-endian length + nonce[12] + AES-256-GCM(json, ct||tag)
///   AAD = `MYVAULT_SYNC_v2|c2s-or-s2c|seq`  (no replay, reorder or reflection)
/// The PC accepts one successful sync per code, then stops listening.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'update.dart' as upd;
import 'vault.dart';
import 'version.dart';

const String protocol = 'MYVAULT_SYNC_v2';

class SyncResult {
  final bool ok;
  final String error;
  final int changed;

  /// The PC's MyVault version; empty for PCs older than 0.5 (they don't say).
  String peerVersion = '';
  upd.Package? received; // a newer phone update the PC handed over
  String sent = ''; // version of a PC update this phone handed over
  String updateError = '';
  SyncResult.success(this.changed) : ok = true, error = '';
  SyncResult.failure(this.error) : ok = false, changed = 0;
}

class SyncCode {
  final List<String> hosts;
  final int port;
  final Uint8List key;
  SyncCode(this.hosts, this.port, this.key);

  /// Throws FormatException for anything that isn't a MyVault sync code.
  factory SyncCode.parse(String raw) {
    final u = Uri.parse(raw.trim());
    final q = u.queryParameters;
    if (u.scheme != 'myvault' || u.host != 'sync' || q['v'] != '2') {
      throw const FormatException("That isn't a MyVault sync code.");
    }
    final k = q['k']!;
    final key = base64Url.decode(k + '=' * ((4 - k.length % 4) % 4));
    if (key.length != 32) throw const FormatException('Bad key in sync code.');
    return SyncCode(
      q['h']!.split(','),
      int.parse(q['p']!),
      Uint8List.fromList(key),
    );
  }
}

Uint8List _randomBytes(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

Uint8List _aad(String dir, int seq) =>
    Uint8List.fromList(utf8.encode('$protocol|$dir|$seq'));

GCMBlockCipher _gcm(bool enc, Uint8List key, Uint8List nonce, Uint8List aad) =>
    GCMBlockCipher(AESEngine())
      ..init(enc, AEADParameters(KeyParameter(key), 128, nonce, aad));

/// Reads exact byte counts off a Socket stream. Keeps whole chunks, so a
/// multi-megabyte update doesn't become one list element per byte.
class _Reader {
  final _chunks = <Uint8List>[];
  int _head = 0, _avail = 0;
  final List<(int, Completer<Uint8List>)> _reqs = [];
  bool _closed = false;

  _Reader(Stream<Uint8List> stream) {
    stream.listen(
      (d) {
        _chunks.add(d);
        _avail += d.length;
        _drain();
      },
      onDone: () {
        _closed = true;
        _drain();
      },
      onError: (_) {
        _closed = true;
        _drain();
      },
    );
  }

  Future<Uint8List> read(int n) {
    final c = Completer<Uint8List>();
    _reqs.add((n, c));
    _drain();
    return c.future;
  }

  void _drain() {
    while (_reqs.isNotEmpty && _avail >= _reqs.first.$1) {
      final (n, c) = _reqs.removeAt(0);
      final out = Uint8List(n);
      var filled = 0;
      while (filled < n) {
        final first = _chunks.first;
        final take = min(n - filled, first.length - _head);
        out.setRange(filled, filled + take, first, _head);
        filled += take;
        _head += take;
        if (_head == first.length) {
          _chunks.removeAt(0);
          _head = 0;
        }
      }
      _avail -= n;
      c.complete(out);
    }
    if (_closed) {
      for (final (_, c) in _reqs) {
        if (!c.isCompleted) c.completeError(const SocketException('closed'));
      }
      _reqs.clear();
    }
  }
}

/// The phone's side of the channel: every message carries its direction and
/// position in the AAD, exactly like _Chan in myvault/sync.py.
class _Chan {
  final Socket sock;
  final Uint8List key;
  final _Reader reader;
  int _out = 0, _in = 0;
  static const _t = Duration(seconds: 10);
  _Chan(this.sock, this.key) : reader = _Reader(sock);

  void sendBytes(Uint8List data) {
    final nonce = _randomBytes(12);
    final ct = _gcm(true, key, nonce, _aad('c2s', _out++)).process(data);
    final header = Uint8List(4);
    ByteData.sublistView(header).setUint32(0, 12 + ct.length, Endian.big);
    sock.add(header);
    sock.add(nonce);
    sock.add(ct);
  }

  void send(Map<String, dynamic> obj) =>
      sendBytes(Uint8List.fromList(utf8.encode(jsonEncode(obj))));

  Future<Uint8List> recvBytes() async {
    final len = ByteData.sublistView(
      await reader.read(4).timeout(_t),
    ).getUint32(0, Endian.big);
    if (len < 28 || len > 16 * 1024 * 1024) {
      throw const FormatException('bad sync message size');
    }
    final blob = await reader.read(len).timeout(_t);
    return _gcm(
      false,
      key,
      blob.sublist(0, 12),
      _aad('s2c', _in++),
    ).process(blob.sublist(12));
  }

  Future<Map<String, dynamic>> recv() async =>
      jsonDecode(utf8.decode(await recvBytes())) as Map<String, dynamic>;
}

Future<upd.Package?> _recvPackage(_Chan ch) async {
  final head = await ch.recv();
  final plat = '${head['platform'] ?? ''}';
  if (plat.isEmpty) return null;
  final size = head['size'] as int;
  if (size <= 0 || size > 200 * 1024 * 1024) {
    throw const FormatException('update package too large');
  }
  final tmp = File(
    '${Directory.systemTemp.path}/myvault-update-${DateTime.now().microsecondsSinceEpoch}',
  );
  final sink = tmp.openWrite();
  try {
    var got = 0;
    while (got < size) {
      final chunk = await ch.recvBytes();
      got += chunk.length;
      sink.add(chunk);
    }
    await sink.close();
    if (got != size) {
      throw const FormatException('update package size mismatch');
    }
    return await upd.store(
      base64.decode(head['manifest'] as String),
      '${head['sig']}',
      plat,
      tmp,
    );
  } finally {
    if (tmp.existsSync()) tmp.deleteSync();
  }
}

Future<String> _sendPackage(_Chan ch, String platform) async {
  final p = (await upd.packages())[platform];
  if (p == null) {
    ch.send({'type': 'package', 'platform': ''});
    return '';
  }
  ch.send({
    'type': 'package',
    'platform': platform,
    'version': p.version,
    'size': p.file.lengthSync(),
    'manifest': base64.encode(p.manifest),
    'sig': p.sig,
  });
  await for (final chunk in p.file.openRead()) {
    // openRead yields up to 64 KB at a time; the PC accepts chunks up to 1 MB.
    ch.sendBytes(Uint8List.fromList(chunk));
    await ch.sock.flush();
  }
  return p.version;
}

/// Connect with a scanned code and sync [vault]. The phone is always the client.
Future<SyncResult> syncWithCode(String raw, Vault vault) async {
  final SyncCode code;
  try {
    code = SyncCode.parse(raw);
  } on FormatException catch (e) {
    return SyncResult.failure(e.message);
  } catch (_) {
    return SyncResult.failure("That isn't a MyVault sync code.");
  }
  var last = "Couldn't reach your PC. Are both devices on the same WiFi?";
  for (final host in code.hosts) {
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        code.port,
        timeout: const Duration(seconds: 6),
      );
      final ch = _Chan(socket, code.key);
      ch.send({
        'type': 'hello',
        'protocol': protocol,
        'device_id': vault.deviceId,
        'app_version': appVersion,
        'platform': upd.platformName,
        'offers': await upd.offers(),
      });
      final hello = await ch.recv();
      if (hello['protocol'] != protocol) {
        return SyncResult.failure('Update MyVault on the PC, then try again.');
      }
      ch.send({
        'type': 'entries',
        'entries': vault.entries.map((e) => e.toJson()).toList(),
      });
      final msg = await ch.recv();
      final remote = ((msg['entries'] ?? []) as List)
          .map((e) => Entry.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      final r = SyncResult.success(vault.mergeIn(remote));
      r.peerVersion = '${hello['app_version'] ?? ''}';

      // Update hand-over (both sides 0.5+). A failure here never undoes the sync.
      if (r.peerVersion.isNotEmpty) {
        try {
          final offered =
              '${((hello['offers'] ?? {}) as Map)[upd.platformName] ?? ''}';
          final want = upd.isNewer(offered, appVersion) ? upd.platformName : '';
          ch.send({'type': 'want', 'platform': want});
          final peerWant = '${(await ch.recv())['platform'] ?? ''}';
          if (want.isNotEmpty) {
            r.received = await _recvPackage(ch); // PC sends first
          }
          if (peerWant.isNotEmpty) r.sent = await _sendPackage(ch, peerWant);
        } catch (e) {
          r.updateError = '$e';
        }
      }
      await socket.flush();
      return r;
    } on InvalidCipherTextException {
      return SyncResult.failure(
        'That code has expired. Show a new one on the PC.',
      );
    } on TimeoutException {
      last = 'Your PC stopped answering. Show a new code and try again.';
    } on SocketException {
      // try the next address in the code
    } catch (e) {
      last = '$e';
    } finally {
      socket?.destroy();
    }
  }
  return SyncResult.failure(last);
}
