"""
LAN sync: keep the vault on two devices (PC, phone, ...) in step over your
home WiFi, privately.

HOW IT STAYS PRIVATE (this matters — entries travel the network):
  * The sync channel is encrypted + authenticated with AES-256-GCM using a key
    derived (scrypt) from your MASTER PASSWORD. Two devices can only sync if they
    share the same master password. Nobody else on the WiFi can read or inject
    entries, because they can't produce a valid GCM tag without that key.
  * Discovery uses a small UDP broadcast that contains NO secrets — just "a
    MyVault device is here". The actual data goes over an authenticated TCP
    channel afterwards.
  * Merge rule: for each entry id, the copy with the newer `updated_at` wins;
    deletions are tombstones that also propagate. Both sides end up identical.

This module is transport + protocol only. The app supplies a small provider
(get_password / get_entries / apply_merged / device_id) so this code never
touches the UI or the Tk main thread directly.
"""

from __future__ import annotations

import json
import os
import socket
import struct
import threading
import time
from dataclasses import dataclass

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

DISCOVERY_PORT = 8788           # UDP, discovery beacons
SYNC_PORT = 8789                # TCP, the encrypted exchange
PROTOCOL = "MYVAULT_SYNC_v1"
DISCOVERY_REQUEST = b"MYVAULT_DISCOVER_v1"
DISCOVERY_REPLY_PREFIX = b"MYVAULT_HERE_v1"

# scrypt params for the sync key. Fixed salt so both devices derive the same key
# from the same master password. (Distinct from the vault-file salt on purpose.)
_SYNC_SALT = b"myvault-sync-key-v1"
_SCRYPT_N = 2 ** 14
_SCRYPT_R = 8
_SCRYPT_P = 1
_NONCE = 12


def derive_sync_key(password: str) -> bytes:
    kdf = Scrypt(salt=_SYNC_SALT, length=32, n=_SCRYPT_N, r=_SCRYPT_R, p=_SCRYPT_P)
    return kdf.derive(password.encode("utf-8"))


# ---- message framing: 4-byte length prefix + AES-GCM(nonce||ct) --------------
def _encrypt(key: bytes, obj: dict) -> bytes:
    nonce = os.urandom(_NONCE)
    ct = AESGCM(key).encrypt(nonce, json.dumps(obj).encode("utf-8"), None)
    return nonce + ct


def _decrypt(key: bytes, blob: bytes) -> dict:
    nonce, ct = blob[:_NONCE], blob[_NONCE:]
    data = AESGCM(key).decrypt(nonce, ct, None)   # raises InvalidTag on wrong key
    return json.loads(data.decode("utf-8"))


def send_msg(sock: socket.socket, key: bytes, obj: dict) -> None:
    payload = _encrypt(key, obj)
    sock.sendall(struct.pack(">I", len(payload)) + payload)


def _recv_exactly(sock: socket.socket, n: int) -> bytes:
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("connection closed mid-message")
        buf += chunk
    return bytes(buf)


def recv_msg(sock: socket.socket, key: bytes) -> dict:
    (length,) = struct.unpack(">I", _recv_exactly(sock, 4))
    if length > 8 * 1024 * 1024:
        raise ValueError("sync message too large")
    return _decrypt(key, _recv_exactly(sock, length))


# ---- the merge (pure function; also unit-tested) -----------------------------
def merge_entries(local: list[dict], remote: list[dict]) -> list[dict]:
    """Union by id, keeping whichever copy of each id has the newer updated_at.
    Deleted tombstones are treated like any other version."""
    by_id: dict[str, dict] = {}
    for e in local:
        by_id[e["id"]] = e
    for e in remote:
        cur = by_id.get(e["id"])
        if cur is None or float(e.get("updated_at", 0)) > float(cur.get("updated_at", 0)):
            by_id[e["id"]] = e
    return list(by_id.values())


@dataclass
class SyncResult:
    ok: bool
    peer: str = ""
    error: str = ""
    added_or_updated: int = 0


class SyncProvider:
    """What the app must implement so sync can read/write the vault safely."""
    def get_password(self) -> str: raise NotImplementedError
    def get_entries(self) -> list[dict]: raise NotImplementedError
    def apply_merged(self, merged: list[dict]) -> int: raise NotImplementedError
    def device_id(self) -> str: raise NotImplementedError


def _exchange(sock: socket.socket, key: bytes, provider: SyncProvider,
              is_server: bool) -> SyncResult:
    """One sync round. Both sides send HELLO then their entries, then merge."""
    my_id = provider.device_id()
    # HELLO first — if the other side used a different master password, its key
    # differs and this decrypt raises InvalidTag -> we report a clean error.
    if is_server:
        peer_hello = recv_msg(sock, key)
        send_msg(sock, key, {"type": "hello", "protocol": PROTOCOL, "device_id": my_id})
    else:
        send_msg(sock, key, {"type": "hello", "protocol": PROTOCOL, "device_id": my_id})
        peer_hello = recv_msg(sock, key)
    if peer_hello.get("protocol") != PROTOCOL:
        return SyncResult(False, error="incompatible sync version")
    peer_id = peer_hello.get("device_id", "?")

    local = provider.get_entries()
    if is_server:
        peer_msg = recv_msg(sock, key)
        send_msg(sock, key, {"type": "entries", "entries": local})
    else:
        send_msg(sock, key, {"type": "entries", "entries": local})
        peer_msg = recv_msg(sock, key)
    remote = peer_msg.get("entries", [])

    merged = merge_entries(local, remote)
    changed = provider.apply_merged(merged)
    return SyncResult(True, peer=peer_id, added_or_updated=changed)


def connect_and_sync(host: str, port: int, provider: SyncProvider,
                     timeout: float = 8.0) -> SyncResult:
    """Client role: connect to a peer and sync. Used by 'Sync now' and auto-sync."""
    key = derive_sync_key(provider.get_password())
    try:
        with socket.create_connection((host, port), timeout=timeout) as sock:
            sock.settimeout(timeout)
            return _exchange(sock, key, provider, is_server=False)
    except InvalidTag:
        return SyncResult(False, peer=host, error="master passwords do not match")
    except (OSError, ValueError, ConnectionError) as exc:
        return SyncResult(False, peer=host, error=str(exc))


class SyncService:
    """Runs the TCP sync server, the UDP discovery responder, and periodic
    auto-discovery that initiates a sync when a peer is found."""

    def __init__(self, provider: SyncProvider, on_result=None,
                 sync_port: int = SYNC_PORT, discovery_port: int = DISCOVERY_PORT,
                 auto: bool = True):
        self.provider = provider
        self.on_result = on_result or (lambda r: None)
        self.sync_port = sync_port
        self.discovery_port = discovery_port
        self.auto = auto
        self._threads: list[threading.Thread] = []
        self._stop = threading.Event()
        self._tcp: socket.socket | None = None
        self._udp: socket.socket | None = None
        self.last_result: SyncResult | None = None

    # -- lifecycle --
    def start(self) -> None:
        self._stop.clear()
        self._start_tcp_server()
        self._start_udp_responder()
        if self.auto:
            self._spawn(self._auto_loop)

    def stop(self) -> None:
        self._stop.set()
        for s in (self._tcp, self._udp):
            try:
                if s:
                    s.close()
            except OSError:
                pass
        self._tcp = self._udp = None

    def _spawn(self, target) -> None:
        t = threading.Thread(target=target, daemon=True, name="myvault-sync")
        t.start()
        self._threads.append(t)

    # -- TCP server (peer connects to us) --
    def _start_tcp_server(self) -> None:
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("0.0.0.0", self.sync_port))
        srv.listen(4)
        srv.settimeout(1.0)
        self._tcp = srv
        self._spawn(self._tcp_accept_loop)

    def _tcp_accept_loop(self) -> None:
        key_pw = None
        while not self._stop.is_set():
            try:
                conn, addr = self._tcp.accept()  # type: ignore[union-attr]
            except socket.timeout:
                continue
            except OSError:
                break
            self._spawn(lambda c=conn, a=addr: self._serve(c, a))

    def _serve(self, conn: socket.socket, addr) -> None:
        with conn:
            conn.settimeout(8.0)
            key = derive_sync_key(self.provider.get_password())
            try:
                result = _exchange(conn, key, self.provider, is_server=True)
            except InvalidTag:
                result = SyncResult(False, peer=addr[0], error="master passwords do not match")
            except (OSError, ValueError, ConnectionError, KeyError) as exc:
                result = SyncResult(False, peer=addr[0], error=str(exc))
        self._report(result)

    # -- UDP discovery responder (reply to broadcasts with our TCP port) --
    def _start_udp_responder(self) -> None:
        udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        udp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        udp.bind(("0.0.0.0", self.discovery_port))
        udp.settimeout(1.0)
        self._udp = udp
        self._spawn(self._udp_loop)

    def _udp_loop(self) -> None:
        reply = (DISCOVERY_REPLY_PREFIX + b"|" +
                 str(self.sync_port).encode() + b"|" +
                 self.provider.device_id().encode())
        while not self._stop.is_set():
            try:
                data, sender = self._udp.recvfrom(1024)  # type: ignore[union-attr]
            except socket.timeout:
                continue
            except OSError:
                break
            if data.strip() == DISCOVERY_REQUEST:
                try:
                    self._udp.sendto(reply, sender)  # unicast reply
                except OSError:
                    pass

    # -- active discovery + initiate (so two PCs also sync automatically) --
    def _auto_loop(self) -> None:
        # small initial delay so both sides are listening
        self._stop.wait(3.0)
        while not self._stop.is_set():
            peers = self.discover(timeout=1.5)
            for ip, port, dev in peers:
                if dev == self.provider.device_id():
                    continue
                # Only the device with the smaller id initiates, so two peers
                # don't sync each other twice at once.
                if self.provider.device_id() < dev:
                    self._report(connect_and_sync(ip, port, self.provider))
            self._stop.wait(20.0)

    def discover(self, timeout: float = 1.5) -> list[tuple[str, int, str]]:
        """Broadcast a discovery request; collect (ip, tcp_port, device_id)."""
        found: dict[str, tuple[str, int, str]] = {}
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        s.settimeout(timeout)
        try:
            s.sendto(DISCOVERY_REQUEST, ("255.255.255.255", self.discovery_port))
            end = time.time() + timeout
            while time.time() < end:
                try:
                    data, sender = s.recvfrom(1024)
                except socket.timeout:
                    break
                if data.startswith(DISCOVERY_REPLY_PREFIX):
                    parts = data.split(b"|")
                    if len(parts) >= 3:
                        found[sender[0]] = (sender[0], int(parts[1]), parts[2].decode())
        finally:
            s.close()
        return list(found.values())

    def sync_now(self, host: str | None = None) -> SyncResult:
        """Manual sync: to a specific host, or auto-discover and pick a peer."""
        if host:
            r = connect_and_sync(host, self.sync_port, self.provider)
            self._report(r)
            return r
        for ip, port, dev in self.discover(timeout=2.0):
            if dev != self.provider.device_id():
                r = connect_and_sync(ip, port, self.provider)
                self._report(r)
                return r
        r = SyncResult(False, error="No other MyVault device found on this network.")
        self._report(r)
        return r

    def _report(self, result: SyncResult) -> None:
        self.last_result = result
        try:
            self.on_result(result)
        except Exception:
            pass


def local_ip() -> str:
    """Best-effort LAN IP of this machine (for showing 'connect to me at ...')."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))   # no packets sent; just picks the route
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()
