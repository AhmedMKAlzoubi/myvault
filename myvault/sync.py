"""
QR sync: keep the vault on your PC and phone in step, only when you say so.

HOW IT STAYS PRIVATE (entries travel your WiFi, so this matters):
  * Nothing listens until you open "Sync with phone". The PC then makes a
    ONE-TIME random 256-bit key and shows it, with its address, as a QR code.
  * The key only ever travels through the camera. Someone else on the WiFi
    never sees it, so they cannot read or inject anything: every message is
    AES-256-GCM with that key, and the tag fails for anyone without it.
  * Each message also authenticates its direction and sequence number, so
    messages cannot be replayed, reordered or reflected back.
  * The listener closes after one successful sync, or after TTL seconds.
  * No discovery broadcasts and no key derived from your master password,
    so a recorded session cannot be brute-forced offline.

Merge rule: for each entry id the copy with the newer `updated_at` wins;
deletions are tombstones that propagate too. Both sides end up identical.

The app supplies a small provider (get_entries / apply_merged / device_id) so
this module never touches the UI thread directly.
"""

from __future__ import annotations

import base64
import ipaddress
import json
import os
import socket
import struct
import tempfile
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

SYNC_PORT = 8789
PROTOCOL = "MYVAULT_SYNC_v2"
PAIRING_TTL = 120          # seconds the QR stays valid
_NONCE = 12
_MAX_MSG = 16 * 1024 * 1024


def _b64u(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _b64u_dec(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


# ---- message framing: 4-byte length + nonce || AES-GCM(ct||tag) -------------
# AAD = protocol | direction | sequence  -> no replay / reorder / reflection.
def _aad(direction: str, seq: int) -> bytes:
    return f"{PROTOCOL}|{direction}|{seq}".encode()


def send_msg(sock: socket.socket, key: bytes, direction: str, seq: int, obj: dict) -> None:
    nonce = os.urandom(_NONCE)
    ct = AESGCM(key).encrypt(nonce, json.dumps(obj).encode("utf-8"), _aad(direction, seq))
    payload = nonce + ct
    sock.sendall(struct.pack(">I", len(payload)) + payload)


def _recv_exactly(sock: socket.socket, n: int) -> bytes:
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("connection closed mid-message")
        buf += chunk
    return bytes(buf)


def recv_msg(sock: socket.socket, key: bytes, direction: str, seq: int) -> dict:
    (length,) = struct.unpack(">I", _recv_exactly(sock, 4))
    if length < _NONCE + 16 or length > _MAX_MSG:
        raise ValueError("bad sync message size")
    blob = _recv_exactly(sock, length)
    data = AESGCM(key).decrypt(blob[:_NONCE], blob[_NONCE:], _aad(direction, seq))
    return json.loads(data.decode("utf-8"))


# ---- the merge (pure function; also unit-tested) -----------------------------
def merge_entries(local: list[dict], remote: list[dict]) -> list[dict]:
    """Union by id, keeping whichever copy of each id has the newer updated_at.
    Deleted tombstones are treated like any other version."""
    by_id: dict[str, dict] = {e["id"]: e for e in local}
    for e in remote:
        cur = by_id.get(e["id"])
        if cur is None or float(e.get("updated_at", 0)) > float(cur.get("updated_at", 0)):
            by_id[e["id"]] = e
    return list(by_id.values())


def restore_entries(local: list[dict], backup: list[dict], now: float) -> tuple[list[dict], dict]:
    """Merge a paper/PDF backup in. Unlike sync, restoring is a deliberate "bring
    these back": a backup copy beats a local deletion even when the deletion is
    newer. A restored entry gets updated_at=now so the next sync carries the
    restore to your other devices instead of re-deleting it there.
    Returns (merged, counts) with counts added / restored / updated / unchanged."""
    by_id: dict[str, dict] = {e["id"]: e for e in local}
    counts = {"added": 0, "restored": 0, "updated": 0, "unchanged": 0}
    for e in backup:
        cur = by_id.get(e["id"])
        if cur is None:
            by_id[e["id"]] = e
            counts["added"] += 1
        elif cur.get("deleted"):
            by_id[e["id"]] = {**e, "deleted": False, "updated_at": now}
            counts["restored"] += 1
        elif float(e.get("updated_at", 0)) > float(cur.get("updated_at", 0)):
            by_id[e["id"]] = e
            counts["updated"] += 1
        else:
            counts["unchanged"] += 1
    return list(by_id.values()), counts


@dataclass
class SyncResult:
    ok: bool
    peer: str = ""
    error: str = ""
    added_or_updated: int = 0
    peer_version: str = ""      # "" = a MyVault from before 0.5 (doesn't say)
    peer_platform: str = ""
    received: str = ""          # version of an update package we received
    sent: str = ""              # version of an update package we handed over
    update_error: str = ""
    files_received: int = 0     # document files (photos/PDFs) received
    files_error: str = ""


# ---- pairing URI (what the QR code holds) ------------------------------------
def make_uri(hosts: list[str], port: int, key: bytes) -> str:
    return f"myvault://sync?v=2&h={','.join(hosts)}&p={port}&k={_b64u(key)}"


def parse_uri(uri: str) -> tuple[list[str], int, bytes]:
    u = urlparse(uri.strip())
    q = parse_qs(u.query)
    if u.scheme != "myvault" or u.netloc != "sync" or q.get("v") != ["2"]:
        raise ValueError("Not a MyVault sync code.")
    key = _b64u_dec(q["k"][0])
    if len(key) != 32:
        raise ValueError("Bad key in sync code.")
    return q["h"][0].split(","), int(q["p"][0]), key


def lan_addresses() -> list[str]:
    """Private IPv4 addresses of this PC, the default-route one first."""
    out: list[str] = []
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))   # no packet is sent; just picks the route
        out.append(s.getsockname()[0])
    except OSError:
        pass
    finally:
        s.close()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            out.append(info[4][0])
    except OSError:
        pass
    seen, good = set(), []
    for ip in out:
        a = ipaddress.ip_address(ip)
        # Skip loopback, 169.254.x (no DHCP, never reachable) and 100.64/10 (Tailscale).
        if a.is_private and not a.is_loopback and not a.is_link_local and ip not in seen \
                and a not in ipaddress.ip_network("100.64.0.0/10"):
            seen.add(ip)
            good.append(ip)
    return good or ["127.0.0.1"]


# ---- one round, both roles ----------------------------------------------------
CHUNK = 1 << 20


class _Chan:
    """Numbers every message per direction, so the AAD binds its position."""

    def __init__(self, sock, key, is_server):
        self.sock, self.key = sock, key
        self.me, self.peer = ("s2c", "c2s") if is_server else ("c2s", "s2c")
        self.out = self.inn = 0

    def send(self, obj: dict) -> None:
        send_msg(self.sock, self.key, self.me, self.out, obj)
        self.out += 1

    def recv(self) -> dict:
        m = recv_msg(self.sock, self.key, self.peer, self.inn)
        self.inn += 1
        return m

    def send_raw(self, data: bytes) -> None:
        nonce = os.urandom(_NONCE)
        ct = AESGCM(self.key).encrypt(nonce, data, _aad(self.me, self.out))
        self.sock.sendall(struct.pack(">I", len(ct) + _NONCE) + nonce + ct)
        self.out += 1

    def recv_raw(self) -> bytes:
        (length,) = struct.unpack(">I", _recv_exactly(self.sock, 4))
        if length < _NONCE + 16 or length > CHUNK + 64:
            raise ValueError("bad sync chunk size")
        blob = _recv_exactly(self.sock, length)
        data = AESGCM(self.key).decrypt(blob[:_NONCE], blob[_NONCE:], _aad(self.peer, self.inn))
        self.inn += 1
        return data


def _send_package(ch: _Chan, provider, platform: str) -> str:
    pkg = provider.package_for(platform)
    if pkg is None:
        ch.send({"type": "package", "platform": ""})
        return ""
    size = pkg.path.stat().st_size
    ch.send({"type": "package", "platform": platform, "version": pkg.version, "size": size,
             "manifest": base64.b64encode(pkg.manifest).decode(), "sig": pkg.sig})
    with open(pkg.path, "rb") as f:
        while chunk := f.read(CHUNK):
            ch.send_raw(chunk)
    return pkg.version


def _recv_package(ch: _Chan, provider, result: SyncResult) -> None:
    head = ch.recv()
    if not head.get("platform"):
        return
    size = int(head["size"])
    if not 0 < size <= 200 * 1024 * 1024:
        raise ValueError("update package too large")
    fd, name = tempfile.mkstemp(prefix="myvault-update-")
    os.close(fd)
    tmp = Path(name)
    try:
        got = 0
        with open(tmp, "wb") as out:
            while got < size:
                chunk = ch.recv_raw()
                got += len(chunk)
                out.write(chunk)
        if got != size:
            raise ValueError("update package size mismatch")
        result.received = provider.receive_package(head["platform"], base64.b64decode(head["manifest"]),
                                                   head["sig"], tmp)
    finally:
        tmp.unlink(missing_ok=True)


FILES_FROM = (0, 6, 0)          # both devices must be this new to swap document files


def _swap(ch: _Chan, is_server: bool, msg: dict) -> dict:
    """The client speaks first, the server answers: both end up with the other's message."""
    if is_server:
        peer = ch.recv()
        ch.send(msg)
        return peer
    ch.send(msg)
    return ch.recv()


def _exchange_files(ch: _Chan, provider, is_server: bool, r: SyncResult) -> None:
    """Document files for the documents both sides now share. They travel as
    stored (already encrypted with each file's own key) inside the sync channel;
    the receiver keeps one only if it opens with the key in the vault. A device
    with file sync switched off neither offers nor asks."""
    on = provider.file_sync()
    refs = provider.file_refs()                    # id -> reference, for live documents
    mine = {i for i in refs if provider.has_file(i)} if on else set()
    peer_has = set(_swap(ch, is_server, {"type": "files", "have": sorted(mine)}).get("have", []))
    want = sorted(i for i in peer_has if i in refs and i not in mine) if on else []
    peer_wants = [i for i in _swap(ch, is_server, {"type": "files_want", "ids": want}).get("ids", []) if i in mine]
    for server_sends in (True, False):             # the server's files first, then the client's
        if server_sends == is_server:
            for fid in peer_wants:
                blob = provider.read_file(fid)
                ch.send({"type": "file", "id": fid, "size": len(blob)})
                for i in range(0, len(blob), CHUNK):
                    ch.send_raw(blob[i:i + CHUNK])
            ch.send({"type": "file", "id": ""})
        else:
            while (head := ch.recv()).get("id"):
                size = int(head["size"])
                if not 0 < size <= 21 * 1024 * 1024:
                    raise ValueError("document file too large")
                blob = bytearray()
                while len(blob) < size:
                    blob += ch.recv_raw()
                if head["id"] in want and len(blob) == size:
                    provider.store_file(head["id"], bytes(blob))
                    r.files_received += 1


def _exchange(sock: socket.socket, key: bytes, provider, is_server: bool) -> SyncResult:
    ch = _Chan(sock, key, is_server)
    my_ver = getattr(provider, "app_version", lambda: "")()
    my_plat = getattr(provider, "platform", lambda: "")()
    hello = {"type": "hello", "protocol": PROTOCOL, "device_id": provider.device_id(),
             "app_version": my_ver, "platform": my_plat,
             "offers": getattr(provider, "offers", dict)()}
    if is_server:
        peer_hello = ch.recv()
        ch.send(hello)
    else:
        ch.send(hello)
        peer_hello = ch.recv()
    if peer_hello.get("protocol") != PROTOCOL:
        return SyncResult(False, error="The other device runs an incompatible MyVault version.")

    local = provider.get_entries()
    if is_server:
        remote = ch.recv().get("entries", [])
        ch.send({"type": "entries", "entries": local})
    else:
        ch.send({"type": "entries", "entries": local})
        remote = ch.recv().get("entries", [])

    changed = provider.apply_merged(merge_entries(local, remote))
    r = SyncResult(True, peer=str(peer_hello.get("device_id", "?")), added_or_updated=changed,
                   peer_version=str(peer_hello.get("app_version", "")),
                   peer_platform=str(peer_hello.get("platform", "")))

    # Update hand-over. Only between devices that both speak it (0.5+), and
    # never at the expense of the sync that already succeeded.
    if not r.peer_version or not my_ver:
        return r
    from .update import newer
    offered = (peer_hello.get("offers") or {}).get(my_plat, "")
    want = my_plat if hasattr(provider, "receive_package") and newer(offered, my_ver) else ""
    try:
        if is_server:
            peer_want = ch.recv().get("platform", "")
            ch.send({"type": "want", "platform": want})
        else:
            ch.send({"type": "want", "platform": want})
            peer_want = ch.recv().get("platform", "")
        for server_sends in (True, False):        # the server's package first, then the client's
            if server_sends == is_server and peer_want:
                r.sent = _send_package(ch, provider, peer_want)
            elif server_sends != is_server and want:
                _recv_package(ch, provider, r)
    except Exception as exc:   # a failed hand-over must never undo a good sync
        r.update_error = str(exc) or exc.__class__.__name__
    from .update import vtuple
    if vtuple(r.peer_version) >= FILES_FROM and vtuple(my_ver) >= FILES_FROM and hasattr(provider, "file_refs"):
        try:
            _exchange_files(ch, provider, is_server, r)
        except Exception as exc:   # likewise: entries are already synced
            r.files_error = str(exc) or exc.__class__.__name__
    return r


def connect_and_sync(uri: str, provider, timeout: float = 8.0) -> SyncResult:
    """Client role (the phone, or a test): connect using a scanned sync code."""
    try:
        hosts, port, key = parse_uri(uri)
    except (ValueError, KeyError, IndexError) as exc:
        return SyncResult(False, error=str(exc))
    last = "Could not reach the PC."
    for host in hosts:
        try:
            with socket.create_connection((host, port), timeout=timeout) as sock:
                sock.settimeout(timeout)
                return _exchange(sock, key, provider, is_server=False)
        except InvalidTag:
            return SyncResult(False, peer=host, error="That sync code has expired. Scan a fresh one.")
        except (OSError, ValueError, ConnectionError) as exc:
            last = str(exc)
    return SyncResult(False, error=last)


class PairingSession:
    """PC side: listen for ONE phone holding the key from our QR, then close."""

    def __init__(self, provider, port: int = SYNC_PORT, ttl: float = PAIRING_TTL):
        self.provider = provider
        self.key = os.urandom(32)
        self.expires_at = time.time() + ttl
        self.result: SyncResult | None = None
        self.failed_attempts = 0
        self.last_error = ""
        self._stop = threading.Event()
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            srv.bind(("0.0.0.0", port))
        except OSError:
            srv.bind(("0.0.0.0", 0))       # preferred port busy: any free one
        srv.listen(4)
        srv.settimeout(0.5)
        self._srv = srv
        self.port = srv.getsockname()[1]
        self.uri = make_uri(lan_addresses(), self.port, self.key)
        threading.Thread(target=self._loop, daemon=True, name="myvault-pairing").start()

    @property
    def state(self) -> str:
        if self.result is not None:
            return "done"
        if self._stop.is_set() or time.time() > self.expires_at:
            return "expired"
        return "waiting"

    def cancel(self) -> None:
        self._stop.set()

    def _loop(self) -> None:
        try:
            while not self._stop.is_set() and time.time() < self.expires_at:
                try:
                    conn, addr = self._srv.accept()
                except TimeoutError:
                    continue
                except OSError:
                    break
                with conn:
                    conn.settimeout(8.0)
                    try:
                        r = _exchange(conn, self.key, self.provider, is_server=True)
                    except InvalidTag:
                        # Someone without the key. Ignore them, keep waiting.
                        self.failed_attempts += 1
                        continue
                    except (OSError, ValueError, ConnectionError, KeyError) as exc:
                        self.last_error = str(exc)   # dropped mid-way: keep waiting
                        continue
                if r.ok:
                    self.result = r
                    break
                self.last_error = r.error
        finally:
            self._stop.set()
            self._srv.close()
