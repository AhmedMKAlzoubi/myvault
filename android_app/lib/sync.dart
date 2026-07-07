/// LAN sync (phone side). Mirrors myvault/sync.py exactly so the phone and PC
/// converge over WiFi. The phone is the INITIATOR: it broadcasts to find the
/// desktop, then connects over TCP and exchanges entries on a channel encrypted
/// with a key derived (scrypt) from the shared master password.
///
/// Wire format (must match Python):
///   - discovery: UDP broadcast "MYVAULT_DISCOVER_v1" -> unicast reply
///     `MYVAULT_HERE_v1|{tcpPort}|{deviceId}`
///   - messages: 4-byte big-endian length + (nonce[12] || AES-256-GCM(ct||tag)),
///     keyed by scrypt(password, "myvault-sync-key-v1", N=16384,r=8,p=1).
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'vault.dart';

const int discoveryPort = 8788;
const int syncPort = 8789;
const String protocol = 'MYVAULT_SYNC_v1';
final Uint8List _discoverRequest = Uint8List.fromList(utf8.encode('MYVAULT_DISCOVER_v1'));
const String _replyPrefix = 'MYVAULT_HERE_v1';

final Uint8List _syncSalt = Uint8List.fromList(utf8.encode('myvault-sync-key-v1'));

class SyncResult {
  final bool ok;
  final String peer;
  final String error;
  final int changed;
  SyncResult.success(this.peer, this.changed) : ok = true, error = '';
  SyncResult.failure(this.error, {this.peer = ''}) : ok = false, changed = 0;
}

class Peer {
  final String ip;
  final int port;
  final String deviceId;
  Peer(this.ip, this.port, this.deviceId);
}

Uint8List _randomBytes(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

Uint8List deriveSyncKey(String password) {
  final d = Scrypt()..init(ScryptParameters(16384, 8, 1, 32, _syncSalt));
  return d.process(Uint8List.fromList(utf8.encode(password)));
}

Uint8List _encryptMsg(Uint8List key, Map<String, dynamic> obj) {
  final nonce = _randomBytes(12);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
  final ct = cipher.process(Uint8List.fromList(utf8.encode(jsonEncode(obj))));
  return Uint8List.fromList([...nonce, ...ct]);
}

Map<String, dynamic> _decryptMsg(Uint8List key, Uint8List blob) {
  final nonce = blob.sublist(0, 12);
  final ct = blob.sublist(12);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
  final pt = cipher.process(ct); // throws InvalidCipherTextException on wrong key
  return jsonDecode(utf8.decode(pt)) as Map<String, dynamic>;
}

/// Merge rule: union by id, newest updated_at wins (tombstones included).
List<Map<String, dynamic>> mergeEntries(
    List<Map<String, dynamic>> local, List<Map<String, dynamic>> remote) {
  final byId = <String, Map<String, dynamic>>{};
  for (final e in local) {
    byId[e['id'] as String] = e;
  }
  for (final e in remote) {
    final id = e['id'] as String;
    final cur = byId[id];
    final eu = (e['updated_at'] as num?)?.toDouble() ?? 0;
    final cu = (cur?['updated_at'] as num?)?.toDouble() ?? 0;
    if (cur == null || eu > cu) byId[id] = e;
  }
  return byId.values.toList();
}

/// Reads exact byte counts off a Socket stream.
class _Reader {
  final Queue<int> _bytes = Queue<int>();
  final List<_Req> _reqs = [];
  bool _closed = false;

  _Reader(Stream<Uint8List> stream) {
    stream.listen(
      (d) { _bytes.addAll(d); _drain(); },
      onDone: () { _closed = true; _drain(); },
      onError: (_) { _closed = true; _drain(); },
    );
  }

  Future<Uint8List> read(int n) {
    final c = Completer<Uint8List>();
    _reqs.add(_Req(n, c));
    _drain();
    return c.future;
  }

  void _drain() {
    while (_reqs.isNotEmpty && _bytes.length >= _reqs.first.n) {
      final r = _reqs.removeAt(0);
      final out = Uint8List(r.n);
      for (var i = 0; i < r.n; i++) {
        out[i] = _bytes.removeFirst();
      }
      r.completer.complete(out);
    }
    if (_closed) {
      for (final r in _reqs) {
        if (!r.completer.isCompleted) {
          r.completer.completeError(const SocketException('closed'));
        }
      }
      _reqs.clear();
    }
  }
}

class _Req {
  final int n;
  final Completer<Uint8List> completer;
  _Req(this.n, this.completer);
}

void _send(Socket sock, Uint8List key, Map<String, dynamic> obj) {
  final payload = _encryptMsg(key, obj);
  final header = Uint8List(4);
  ByteData.sublistView(header).setUint32(0, payload.length, Endian.big);
  sock.add(header);
  sock.add(payload);
}

Future<Map<String, dynamic>> _recv(_Reader reader, Uint8List key) async {
  final header = await reader.read(4);
  final len = ByteData.sublistView(header).getUint32(0, Endian.big);
  if (len > 8 * 1024 * 1024) throw const FormatException('message too large');
  final payload = await reader.read(len);
  return _decryptMsg(key, payload);
}

/// Broadcast a discovery request and collect replying peers.
Future<List<Peer>> discover({Duration timeout = const Duration(seconds: 2)}) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  socket.broadcastEnabled = true;
  final found = <String, Peer>{};
  socket.listen((event) {
    if (event == RawSocketEvent.read) {
      final dg = socket.receive();
      if (dg == null) return;
      final text = utf8.decode(dg.data, allowMalformed: true);
      if (text.startsWith(_replyPrefix)) {
        final parts = text.split('|');
        if (parts.length >= 3) {
          found[dg.address.address] =
              Peer(dg.address.address, int.tryParse(parts[1]) ?? syncPort, parts[2]);
        }
      }
    }
  });
  socket.send(_discoverRequest, InternetAddress('255.255.255.255'), discoveryPort);
  await Future.delayed(timeout);
  socket.close();
  return found.values.toList();
}

/// Connect to a peer and sync a vault. The phone always plays the client role.
Future<SyncResult> connectAndSync(String host, int port, Vault vault) async {
  final key = deriveSyncKey(vault.password);
  Socket? socket;
  try {
    socket = await Socket.connect(host, port, timeout: const Duration(seconds: 8));
    final reader = _Reader(socket);

    _send(socket, key, {'type': 'hello', 'protocol': protocol, 'device_id': vault.deviceId});
    final peerHello = await _recv(reader, key).timeout(const Duration(seconds: 8));
    if (peerHello['protocol'] != protocol) {
      return SyncResult.failure('incompatible sync version', peer: host);
    }

    final local = vault.entries.map((e) => e.toJson()).toList();
    _send(socket, key, {'type': 'entries', 'entries': local});
    final peerMsg = await _recv(reader, key).timeout(const Duration(seconds: 8));
    final remote = ((peerMsg['entries'] ?? []) as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();

    final before = {for (final e in vault.entries) e.id: e.updatedAt};
    final merged = mergeEntries(local, remote);
    vault.entries = merged.map((d) => Entry.fromJson(d)).toList();
    vault.save();
    final changed = vault.entries
        .where((e) => !before.containsKey(e.id) || e.updatedAt > before[e.id]!)
        .length;

    await socket.flush();
    return SyncResult.success((peerHello['device_id'] ?? '?') as String, changed);
  } on InvalidCipherTextException {
    return SyncResult.failure('master passwords do not match', peer: host);
  } on SocketException catch (e) {
    return SyncResult.failure('Could not reach that device (${e.message}).', peer: host);
  } on TimeoutException {
    return SyncResult.failure('The other device did not respond in time.', peer: host);
  } catch (e) {
    return SyncResult.failure('$e', peer: host);
  } finally {
    socket?.destroy();
  }
}

/// Auto-find a peer (or use [host]) and sync.
Future<SyncResult> syncNow(Vault vault, {String? host}) async {
  if (host != null && host.trim().isNotEmpty) {
    return connectAndSync(host.trim(), syncPort, vault);
  }
  final peers = await discover();
  for (final p in peers) {
    if (p.deviceId != vault.deviceId) {
      return connectAndSync(p.ip, p.port, vault);
    }
  }
  return SyncResult.failure('No other MyVault device found on this WiFi.');
}
