"""Cross-language QR sync check: starts a real PC-side PairingSession and runs
the Dart phone client against it (android_app/test/interop_sync_test.dart).

Checks entries converge, and the update hand-over in both directions: the PC
passes the phone a (signed) 0.9.0 APK while the phone passes the PC a 0.9.0
Windows installer, which the PC verifies against the update signature.
Needs Flutter on PATH. Run:  python tests/interop_sync.py"""

import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from cryptography.hazmat.primitives import serialization          # noqa: E402
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey  # noqa: E402

PKG = "0.9.0"


def release(folder: Path, key, platform: str, name: str, data: bytes) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    (folder / name).write_bytes(data)
    raw = json.dumps({"app": "MyVault", "version": PKG, "files": {platform: {
        "name": name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}}}).encode()
    (folder / f"manifest-{platform}.json").write_bytes(raw)
    (folder / f"manifest-{platform}.sig").write_text(base64.b64encode(key.sign(raw)).decode())


with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    os.environ["LOCALAPPDATA"] = str(d / "pc")              # PC data dir (and its package cache)
    from myvault import docs, sync, update                # noqa: E402
    from myvault.vault import Entry, Vault               # noqa: E402

    key = Ed25519PrivateKey.generate()                  # stands in for the real update key
    update.UPDATE_PUBKEY = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    apk, installer = os.urandom(2_500_000), os.urandom(1_700_000)
    release(update.cache_dir() / PKG, key, "android", f"MyVault-{PKG}.apk", apk)
    release(d / "phone" / "packages" / PKG, key, "windows", f"MyVault-Setup-{PKG}.exe", installer)

    class Provider:
        def __init__(self, v):
            self.v = v
        def device_id(self): return "pc-test"
        def get_entries(self): return [e.to_dict() for e in self.v.entries]
        def apply_merged(self, merged):
            self.v.entries = [Entry.from_dict(x) for x in merged]
            self.v.save()
            return len(merged)
        def app_version(self): return "0.6.0"
        def platform(self): return "windows"
        def offers(self): return update.offers()
        def package_for(self, plat): return update.packages().get(plat)
        def receive_package(self, plat, manifest, sig, tmp): return update.store(manifest, sig, plat, tmp).version
        # document files
        def file_sync(self): return True
        def file_refs(self):
            return {r["id"]: r for e in self.v.entries if e.kind == "document" and not e.deleted for r in docs.refs(e.fields)}
        def has_file(self, i): return docs.have(i)
        def read_file(self, i): return docs.read_blob(i)
        def store_file(self, i, blob): docs.store_blob(self.file_refs()[i], blob)

    v = Vault.create(d / "pc.dat", "pc-pass-123")
    pc_scan = b"%PDF-1.4 PC lease " + os.urandom(1_500_000)           # more than one sync chunk
    pc_ref = docs.seal(pc_scan, "lease.pdf")
    v.entries = [Entry(id="from-pc", kind="api", title="PC API", fields={"api_key": "PC-KEY"}, updated_at=400),
                 Entry(id="shared", title="Shared", password="pc-older", updated_at=100),
                 Entry(id="pc-doc", kind="document", title="Lease", updated_at=400,
                       fields={"doc_type": "rental", "expires": "2027-02-28", "files": json.dumps([pc_ref])})]
    s = sync.PairingSession(Provider(v), port=0, ttl=120)
    uri = s.uri.replace(s.uri.split("h=")[1].split("&")[0], "127.0.0.1")
    env = dict(os.environ, MYVAULT_SYNC_URI=uri, MYVAULT_PHONE_DIR=str(d / "phone"),
               MYVAULT_PC_VERSION="0.6.0", MYVAULT_PKG_VERSION=PKG, MYVAULT_APK_SIZE=str(len(apk)),
               MYVAULT_PC_FILE=pc_ref["id"], MYVAULT_PC_FILE_SIZE=str(len(pc_scan)),
               MYVAULT_UPDATE_PUBKEY=update.UPDATE_PUBKEY.hex())
    flutter = "flutter.bat" if os.name == "nt" else "flutter"
    rc = subprocess.call([flutter, "test", "test/interop_sync_test.dart"], cwd=ROOT / "android_app", env=env)
    end = time.time() + 10
    while s.state == "waiting" and time.time() < end:
        time.sleep(0.1)
    ids = {e.id: e for e in Vault.open(d / "pc.dat", "pc-pass-123").entries}
    assert rc == 0, "Dart side failed"
    assert s.state == "done", s.state
    assert ids["from-phone"].fields["private_key"] == "PK"
    assert ids["shared"].password == "phone-newer"
    got = update.packages()["windows"]
    assert s.result.received == PKG and got.path.read_bytes() == installer, (s.result, got)
    phone_version = re.search(r"appVersion = '([0-9.]+)'", (ROOT / "android_app" / "lib" / "version.dart").read_text()).group(1)
    assert s.result.sent == PKG and s.result.peer_version == phone_version, s.result
    phone_ref = docs.refs(ids["phone-doc"].fields)[0]
    assert docs.open_sealed(phone_ref)[:12] == b"\xff\xd8\xff phone ID" and s.result.files_received == 1, s.result
    print("INTEROP OK: entries converged; APK went PC -> phone and the installer phone -> PC, both verified;")
    print("            document files went both ways and open with their keys")

    # The PC's lock screen: the Dart phone opens it, then they sync on the same link.
    from myvault import app, paths                       # noqa: E402
    api = app.Api()
    assert api.unlock("pc-pass-123")["ok"]
    api._vault.entries = [Entry(id="pc-only", title="On the PC", updated_at=100)]
    vid = app._SyncProvider(api).vault_identity()[0]
    api.lock()
    u = sync.PairingSession(None, port=0, ttl=120, unlocker=app._Unlocker(api, paths.DEFAULT))
    env = {k: v for k, v in env.items() if k != "MYVAULT_SYNC_URI"}
    env.update(MYVAULT_UNLOCK_URI=u.uri.replace(u.uri.split("h=")[1].split("&")[0], "127.0.0.1"), MYVAULT_VAULT_ID=vid)
    rc = subprocess.call([flutter, "test", "test/interop_sync_test.dart", "--plain-name", "unlock a live Python PC"],
                         cwd=ROOT / "android_app", env=env)
    end = time.time() + 10
    while u.state == "waiting" and time.time() < end:
        time.sleep(0.1)
    assert rc == 0, "Dart unlock side failed"
    assert u.state == "done" and api._vault is not None, u.last_error
    assert {e.id for e in api._vault.entries} == {"pc-only", "phone-only"}
    print("INTEROP OK: the phone unlocked the PC's vault and synced it on the same link")
