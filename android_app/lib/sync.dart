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

import 'docs.dart' as docs;
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
  int filesReceived = 0; // document files (photos/PDFs)
  String filesError = '';

  /// The PC had a different vault open (the code stays valid: Sync anyway).
  bool vaultMismatch = false;
  String pcVault = '';

  /// An unlock code: the PC's vault opened, or a new one made from this phone's.
  bool unlocked = false, createdOnPc = false, synced = true;
  SyncResult.success(this.changed) : ok = true, error = '';
  SyncResult.failure(this.error) : ok = false, changed = 0;
}

class SyncCode {
  final List<String> hosts;
  final int port;
  final Uint8List key;
  final bool unlock; // the PC's lock screen: this phone opens it
  SyncCode(this.hosts, this.port, this.key, {this.unlock = false});

  /// Throws FormatException for anything that isn't a MyVault sync code.
  factory SyncCode.parse(String raw) {
    final u = Uri.parse(raw.trim());
    final q = u.queryParameters;
    if (u.scheme != 'myvault' ||
        !(u.host == 'sync' || u.host == 'unlock') ||
        q['v'] != '2') {
      throw const FormatException("That isn't a MyVault sync code.");
    }
    final k = q['k']!;
    final key = base64Url.decode(k + '=' * ((4 - k.length % 4) % 4));
    if (key.length != 32) throw const FormatException('Bad key in sync code.');
    // Only addresses on a home network (or this device). A code pointing at an
    // internet server is someone else's, not your PC's: refuse to send the vault.
    final hosts = q['h']!.split(',').where(isPrivateIPv4).toList();
    if (hosts.isEmpty) {
      throw const FormatException(
        "That code doesn't point at a PC on your home network, so MyVault won't sync with it.",
      );
    }
    return SyncCode(
      hosts,
      int.parse(q['p']!),
      Uint8List.fromList(key),
      unlock: u.host == 'unlock',
    );
  }
}

/// 10/8, 172.16/12, 192.168/16, or loopback; IPv4 only, never a hostname.
bool isPrivateIPv4(String h) {
  final a = InternetAddress.tryParse(h);
  if (a == null || a.type != InternetAddressType.IPv4) return false;
  final b = a.rawAddress;
  return b[0] == 10 ||
      b[0] == 127 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168);
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

/// Document files, after the entries (both sides 0.6+): the same steps as
/// _exchange_files in myvault/sync.py. Files travel as stored (encrypted with
/// their own keys); one is kept only if it opens with the key in the vault.
Future<void> _exchangeFiles(_Chan ch, Vault vault, SyncResult r) async {
  final on = (await upd.loadPrefs())['sync_files'] != false;
  final refs = docs.liveRefs(vault);
  final mine = on
      ? {
          for (final id in refs.keys)
            if (docs.haveFile(vault, id)) id,
        }
      : <String>{};
  ch.send({'type': 'files', 'have': mine.toList()..sort()});
  final peerHas = ((await ch.recv())['have'] as List? ?? []).cast<String>();
  final want = on
      ? [
          for (final id in peerHas)
            if (refs.containsKey(id) && !mine.contains(id)) id,
        ]
      : <String>[];
  ch.send({'type': 'files_want', 'ids': want});
  final peerWants = [
    for (final id in ((await ch.recv())['ids'] as List? ?? []).cast<String>())
      if (mine.contains(id)) id,
  ];
  // The PC sends first, then the phone.
  for (;;) {
    final head = await ch.recv();
    final id = '${head['id'] ?? ''}';
    if (id.isEmpty) break;
    final size = head['size'] as int;
    if (size <= 0 || size > 21 * 1024 * 1024) {
      throw const FormatException('document file too large');
    }
    final blob = BytesBuilder(copy: false);
    while (blob.length < size) {
      blob.add(await ch.recvBytes());
    }
    if (want.contains(id) && blob.length == size) {
      await docs.storeBlob(vault, refs[id]!, blob.takeBytes());
      r.filesReceived++;
    }
  }
  for (final id in peerWants) {
    final blob = docs.readBlob(vault, id);
    ch.send({'type': 'file', 'id': id, 'size': blob.length});
    for (var i = 0; i < blob.length; i += 1 << 20) {
      final end = i + (1 << 20) < blob.length ? i + (1 << 20) : blob.length;
      ch.sendBytes(Uint8List.sublistView(blob, i, end));
      await ch.sock.flush();
    }
  }
  ch.send({'type': 'file', 'id': ''});
}

/// The sync itself, on an open channel (also right after an unlock).
Future<SyncResult> _syncOn(
  _Chan ch,
  Vault vault, {
  required bool Function(Entry) held,
  bool mergeAnyway = false,
  String vaultName = '',
}) async {
  ch.send({
    'type': 'hello',
    'protocol': protocol,
    'device_id': vault.deviceId,
    'app_version': appVersion,
    'platform': upd.platformName,
    'offers': await upd.offers(),
    'vault_id': vault.vaultId,
    'vault_name': vaultName,
    'merge_anyway': mergeAnyway,
  });
  final hello = await ch.recv();
  if (hello['protocol'] != protocol) {
    return SyncResult.failure('Update MyVault on the PC, then try again.');
  }
  // Which vault this is: the PC gives one an id at its first sync and the
  // phone adopts it, so later a sync never mixes two different vaults.
  final pcId = '${hello['vault_id'] ?? ''}';
  final pcName = '${hello['vault_name'] ?? ''}';
  final differ =
      vault.vaultId.isNotEmpty && pcId.isNotEmpty && vault.vaultId != pcId;
  if (differ && !mergeAnyway && hello['merge_anyway'] != true) {
    return SyncResult.failure(
        "The PC has “$pcName” open, which isn't the vault open on this phone. Open the same vault on both, or choose Sync anyway to merge them.",
      )
      ..vaultMismatch = true
      ..pcVault = pcName;
  }
  if (pcId.isNotEmpty) vault.vaultId = pcId; // saved with the merge below
  ch.send({
    'type': 'entries',
    'entries': [
      for (final e in vault.entries)
        if (!held(e)) e.toJson(),
    ],
  });
  final msg = await ch.recv();
  final remote = ((msg['entries'] ?? []) as List)
      .map((e) => Entry.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
  final r = SyncResult.success(vault.mergeIn(remote, held: held));
  r.peerVersion = '${hello['app_version'] ?? ''}';

  // Update hand-over (both sides 0.5+). A failure here never undoes the sync.
  if (r.peerVersion.isNotEmpty) {
    try {
      final offered =
          '${((hello['offers'] ?? {}) as Map)[upd.platformName] ?? ''}';
      final want = !upd.storeBuild && upd.isNewer(offered, appVersion)
          ? upd.platformName
          : '';
      ch.send({'type': 'want', 'platform': want});
      final peerWant = '${(await ch.recv())['platform'] ?? ''}';
      if (want.isNotEmpty) {
        r.received = await _recvPackage(ch); // PC sends first
      }
      if (peerWant.isNotEmpty) r.sent = await _sendPackage(ch, peerWant);
    } catch (e) {
      r.updateError = '$e';
    }
    if (!upd.isNewer('0.6.0', r.peerVersion) &&
        !upd.isNewer('0.6.0', appVersion)) {
      try {
        await _exchangeFiles(ch, vault, r);
      } catch (e) {
        r.filesError = '$e'; // the entries are synced already
      }
    }
  }
  return r;
}

/// Connect to the PC in [raw] and run [talk] on the channel. The phone is
/// always the client; each address in the code is tried in turn.
Future<SyncResult> _connect(
  String raw,
  Future<SyncResult> Function(_Chan ch, SyncCode code) talk,
) async {
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
      final r = await talk(_Chan(socket, code.key), code);
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

/// Connect with a scanned code and sync [vault].
/// With [only] (entry ids), just those of this phone's entries take part; new
/// entries from the PC still arrive. Entries kept on this phone never take
/// part. [mergeAnyway] syncs even when the PC has a different vault open.
Future<SyncResult> syncWithCode(
  String raw,
  Vault vault, {
  Set<String>? only,
  bool mergeAnyway = false,
  String vaultName = '',
}) => _connect(raw, (ch, code) async {
  if (code.unlock) {
    return SyncResult.failure(
      "That's the PC's unlock code. Scan it from Sync with PC to open the PC's vault.",
    );
  }
  return _syncOn(
    ch,
    vault,
    held: (e) => e.localOnly || (only != null && !only.contains(e.id)),
    mergeAnyway: mergeAnyway,
    vaultName: vaultName,
  );
});

/// Why the PC's vault is offered: 'same' (the vault open on this phone),
/// 'unknown' (they haven't synced yet, so it can't tell), 'other' (another
/// vault), 'wrong' (it didn't open with this phone's master password).
typedef UnlockChoice =
    Future<String> Function(String pcName, String pcVault, String why);

/// The PC's lock-screen code: open the PC's vault with this phone's master
/// password. [decide] answers 'unlock', 'create' (a new vault on the PC made
/// from this phone's; the PC's own vault stays as it is) or '' (stop). The
/// password is only sent for 'same' or 'unknown', so a code for another vault
/// never gets it. Then, if the two copies differ, [askSync].
Future<SyncResult> unlockWithCode(
  String raw,
  Vault vault, {
  required String vaultName,
  required UnlockChoice decide,
  required Future<bool> Function() askSync,
}) => _connect(raw, (ch, code) async {
  if (!code.unlock) {
    return SyncResult.failure("That's a sync code, not an unlock code.");
  }
  ch.send({'type': 'hello', 'protocol': protocol, 'app_version': appVersion});
  final hello = await ch.recv();
  if (hello['protocol'] != protocol || hello['mode'] != 'unlock') {
    return SyncResult.failure('Update MyVault on the PC, then try again.');
  }
  final pcId = '${hello['vault_id'] ?? ''}';
  final pcVault = '${hello['vault_name'] ?? ''}';
  final pcName = '${hello['pc_name'] ?? ''}';
  var why = pcId.isEmpty || vault.vaultId.isEmpty
      ? 'unknown'
      : pcId == vault.vaultId
      ? 'same'
      : 'other';
  var created = false;
  for (;;) {
    final d = await decide(pcName, pcVault, why);
    if (d == 'unlock' && (why == 'same' || why == 'unknown')) {
      ch.send({'type': 'unlock', 'password': vault.password});
      if ((await ch.recv())['type'] == 'unlocked') break;
      why = 'wrong';
    } else if (d == 'create') {
      ch.send({
        'type': 'create',
        'name': vaultName,
        'password': vault.password,
        'vault_id': vault.vaultId,
      });
      final a = await ch.recv();
      if (a['type'] != 'unlocked') {
        return SyncResult.failure(
          '${a['error'] ?? "The PC couldn't make the vault."}',
        );
      }
      created = true;
      break;
    } else {
      ch.send({'type': 'stop'});
      return SyncResult.failure('')..synced = false;
    }
  }
  // Already the same? Then there's nothing to sync.
  final pc = ((await ch.recv())['entries'] ?? {}) as Map;
  final mine = {
    for (final e in vault.entries)
      if (!e.localOnly) e.id: e.updatedAt,
  };
  final same =
      pc.length == mine.length &&
      mine.entries.every((m) => (pc[m.key] as num?)?.toDouble() == m.value);
  final go = !same && (created || await askSync());
  ch.send({'type': 'sync', 'sync': go});
  final r = go
      ? await _syncOn(ch, vault, held: (e) => e.localOnly, vaultName: vaultName)
      : SyncResult.success(0);
  return r
    ..unlocked = true
    ..createdOnPc = created
    ..synced = go || same;
});
