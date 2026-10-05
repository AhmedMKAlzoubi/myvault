"""Core logic tests (no GUI). Run:  python -m pytest  (or)  python tests/test_core.py"""

import base64
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from myvault import crypto, paper, sync, webmatch
from myvault.generator import PasswordPolicy, generate
from myvault.vault import Vault, Entry


def test_encrypt_roundtrip():
    data = b"hello secret world \x00\xff"
    blob = crypto.encrypt(data, "correct horse battery staple")
    assert crypto.decrypt(blob, "correct horse battery staple") == data


def test_wrong_password_rejected():
    blob = crypto.encrypt(b"top secret", "right-password")
    try:
        crypto.decrypt(blob, "WRONG-password")
    except crypto.WrongPasswordError:
        pass
    else:
        raise AssertionError("wrong password should have been rejected")


def test_tamper_detected():
    blob = bytearray(crypto.encrypt(b"payload", "pw"))
    # flip a byte inside the base64 ciphertext region near the end
    blob[-8] = blob[-8] ^ 0x01
    try:
        crypto.decrypt(bytes(blob), "pw")
    except (crypto.WrongPasswordError, crypto.VaultFormatError):
        pass
    else:
        raise AssertionError("tampering should have been detected")


def test_generator_respects_policy():
    p = PasswordPolicy(length=20, use_symbols=False, use_upper=True,
                       use_lower=True, use_digits=True)
    for _ in range(200):
        pw = generate(p)
        assert len(pw) == 20
        assert all(c.isalnum() for c in pw), pw
        assert any(c.isdigit() for c in pw)
        assert any(c.isupper() for c in pw)
        assert any(c.islower() for c in pw)


def test_generator_avoids_ambiguous():
    p = PasswordPolicy(length=40, avoid_ambiguous=True)
    for _ in range(100):
        pw = generate(p)
        assert not any(c in "Il1O0o" for c in pw), pw


def test_vault_crud_and_persistence():
    with tempfile.TemporaryDirectory() as d:
        path = Path(d) / "vault.dat"
        v = Vault.create(path, "master-pass")
        e = Entry(title="Netflix", website="netflix.com",
                  username="ahmed", password="p@ss", custom={"pin": "1234"})
        v.add(e)
        assert path.exists()

        # reopen with correct password
        v2 = Vault.open(path, "master-pass")
        assert len(v2.active_entries()) == 1
        got = v2.active_entries()[0]
        assert got.title == "Netflix"
        assert got.custom["pin"] == "1234"

        # search
        assert v2.search("netflix")
        assert not v2.search("gmail")

        # soft delete leaves a tombstone but hides from active list
        v2.delete(got.id)
        assert v2.active_entries() == []
        assert any(x.deleted for x in v2.entries)

        # wrong password cannot open
        try:
            Vault.open(path, "nope")
        except crypto.WrongPasswordError:
            pass
        else:
            raise AssertionError("wrong password opened the vault")


def test_change_password():
    with tempfile.TemporaryDirectory() as d:
        path = Path(d) / "vault.dat"
        v = Vault.create(path, "old-pass")
        v.add(Entry(title="X"))
        v.change_password("new-longer-pass")
        # old no longer works, new does
        try:
            Vault.open(path, "old-pass")
        except crypto.WrongPasswordError:
            pass
        else:
            raise AssertionError("old password should be invalid")
        assert Vault.open(path, "new-longer-pass").active_entries()[0].title == "X"


def test_webmatch_normalize():
    assert webmatch.normalize_host("https://www.Netflix.com/login") == "netflix.com"
    assert webmatch.normalize_host("netflix.com") == "netflix.com"
    assert webmatch.normalize_host("accounts.google.com") == "accounts.google.com"
    assert webmatch.normalize_host("") == ""


def test_webmatch_hosts_match():
    assert webmatch.hosts_match("www.netflix.com", "netflix.com")
    assert webmatch.hosts_match("accounts.google.com", "google.com")
    assert webmatch.hosts_match("google.com", "accounts.google.com")
    assert not webmatch.hosts_match("netflix.com", "netflixx.com")
    assert not webmatch.hosts_match("evil-netflix.com", "netflix.com")
    assert not webmatch.hosts_match("gmail.com", "netflix.com")


def test_merge_newest_wins_and_tombstones():
    local = [
        {"id": "x", "updated_at": 100, "password": "old"},
        {"id": "y", "updated_at": 100},
    ]
    remote = [
        {"id": "x", "updated_at": 200, "password": "new"},   # newer -> wins
        {"id": "y", "updated_at": 50, "deleted": True},       # older -> ignored
        {"id": "z", "updated_at": 100},                        # new id -> added
    ]
    merged = {e["id"]: e for e in sync.merge_entries(local, remote)}
    assert merged["x"]["password"] == "new"
    assert merged["y"].get("deleted") is not True     # older delete loses
    assert "z" in merged


class _Provider:
    """Test sync provider backed by a real Vault."""
    def __init__(self, vault):
        self.vault = vault
    def get_entries(self):
        return [e.to_dict() for e in self.vault.entries]   # includes tombstones
    def apply_merged(self, merged):
        before = {e.id: e.updated_at for e in self.vault.entries}
        self.vault.entries = [Entry.from_dict(d) for d in merged]
        self.vault.save()
        return sum(1 for e in self.vault.entries
                   if before.get(e.id) is None or e.updated_at > before[e.id])
    def device_id(self):
        return self.vault.device_id


def _wait_done(session, timeout=5):
    import time
    end = time.time() + timeout
    while session.state == "waiting" and time.time() < end:
        time.sleep(0.05)


def test_qr_sync_convergence():
    with tempfile.TemporaryDirectory() as d:
        # Different master passwords are fine: the QR key is what authorizes.
        va = Vault.create(Path(d) / "a.dat", "password-A")
        vb = Vault.create(Path(d) / "b.dat", "password-B")
        va.device_id, vb.device_id = "device-A", "device-B"
        va.entries = [
            Entry(id="x", title="Netflix", password="old", updated_at=100),
            Entry(id="y", title="Gmail", updated_at=100),
        ]
        vb.entries = [
            Entry(id="x", title="Netflix", password="NEW", updated_at=200),  # newer
            Entry(id="z", kind="ssh", title="Server", fields={"private_key": "K"}, updated_at=100),
            Entry(id="y", title="Gmail", updated_at=300, deleted=True),      # delete
        ]
        session = sync.PairingSession(_Provider(va), port=0, ttl=10)
        uri = session.uri.replace(session.uri.split("h=")[1].split("&")[0], "127.0.0.1")
        result = sync.connect_and_sync(uri, _Provider(vb))
        _wait_done(session)
        assert result.ok, result.error
        assert session.state == "done"

        a_ids = {e.id: e for e in va.entries}
        b_ids = {e.id: e for e in vb.entries}
        assert a_ids["x"].password == "NEW" and b_ids["x"].password == "NEW"
        assert a_ids["y"].deleted and b_ids["y"].deleted
        assert a_ids["z"].fields["private_key"] == "K"
        va2 = Vault.open(Path(d) / "a.dat", "password-A")
        assert {e.id for e in va2.entries} == {"x", "y", "z"}

        # Session closes after one sync: a second connect fails.
        assert not sync.connect_and_sync(uri, _Provider(vb), timeout=1).ok


def test_qr_sync_rejects_wrong_key():
    with tempfile.TemporaryDirectory() as d:
        va = Vault.create(Path(d) / "a.dat", "pw-aaaaaaaa")
        vb = Vault.create(Path(d) / "b.dat", "pw-bbbbbbbb")
        va.device_id, vb.device_id = "A", "B"
        session = sync.PairingSession(_Provider(va), port=0, ttl=10)
        forged = sync.make_uri(["127.0.0.1"], session.port, os.urandom(32))
        result = sync.connect_and_sync(forged, _Provider(vb), timeout=2)
        assert not result.ok
        assert session.state == "waiting"     # an attacker doesn't end the session
        session.cancel()
        assert va.entries == []


def test_restore_brings_back_deleted_entries():
    local = [
        {"id": "gone", "title": "Bank", "deleted": True, "updated_at": 500},   # deleted after the backup
        {"id": "live", "title": "Mail", "password": "new", "updated_at": 500},
    ]
    backup = [
        {"id": "gone", "title": "Bank", "password": "p", "updated_at": 100},
        {"id": "live", "title": "Mail", "password": "old", "updated_at": 100},
        {"id": "fresh", "title": "New", "updated_at": 100},
    ]
    merged, counts = sync.restore_entries(local, backup, now=900)
    m = {e["id"]: e for e in merged}
    assert counts == {"added": 1, "restored": 1, "updated": 0, "unchanged": 1}
    assert m["gone"]["deleted"] is False and m["gone"]["password"] == "p"
    assert m["gone"]["updated_at"] == 900          # newer than the deletion, so sync spreads it
    assert m["live"]["password"] == "new"          # a live, newer entry is never overwritten


def _signed_release(tmp: Path, version: str, files: dict):
    """A release manifest signed with a throwaway key (patched in as the update key)."""
    import base64, hashlib, json
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives import serialization
    from myvault import update
    key = Ed25519PrivateKey.generate()
    update.UPDATE_PUBKEY = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    entries = {}
    for plat, (name, data) in files.items():
        (tmp / name).write_bytes(data)
        entries[plat] = {"name": name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    raw = json.dumps({"app": "MyVault", "version": version, "files": entries}).encode()
    return raw, base64.b64encode(key.sign(raw)).decode()


class _UpdatingProvider(_Provider):
    def __init__(self, vault, version, platform, pkg=None):
        super().__init__(vault)
        self.version, self.plat, self.pkg = version, platform, pkg
        self.stored = None
    def app_version(self): return self.version
    def platform(self): return self.plat
    def offers(self): return {self.pkg.platform: self.pkg.version} if self.pkg else {}
    def package_for(self, plat): return self.pkg if self.pkg and self.pkg.platform == plat else None
    def receive_package(self, plat, manifest, sig, tmp):
        from myvault import update
        self.stored = update.store(manifest, sig, plat, tmp)
        return self.stored.version


def test_documents_read_like_the_phone():
    """The shared cases (also run by the phone's tests), plus a broken check digit."""
    import datetime as dt
    import json
    from myvault import docs
    c = json.loads((ROOT / "android_app" / "test_fixtures" / "read_cases.json").read_text("utf-8"))
    today = dt.date.fromisoformat(c["today"])
    for case in c["cases"]:
        got = docs.read_details(case["text"], today=today)
        assert got == case["want"], (case["name"], got)
    td3 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\nL898902C36UTO7408122F1204159ZE184226B<<<<<10"
    assert "expires" not in docs.read_mrz(td3.replace("1204159", "1204158"))


def test_document_types_are_the_same_on_pc_and_phone():
    import json
    pc = json.loads((ROOT / "myvault" / "ui" / "doc_types.json").read_text("utf-8"))
    phone = json.loads((ROOT / "android_app" / "assets" / "doc_types.json").read_text("utf-8"))
    assert pc == phone, "copy myvault/ui/doc_types.json to android_app/assets/doc_types.json"
    for name, t in pc["types"].items():
        assert set(t["fields"]) <= set(pc["fields"]) and "expires" in t["fields"], name
        assert set(t.get("labels", {})) <= set(t["fields"]), name


def test_documents_reminders_and_sealed_files():
    import json
    import datetime as dt
    import tempfile as tf
    from pathlib import Path as P
    from myvault import docs
    e = Entry(kind="document", title="My passport", fields={"doc_type": "passport", "expires": "2027-03-01",
                                                             "remind": "30,7,abc,7", "number": "P123"})
    plan = docs.schedule([e])
    assert [(r["on"], r["days"]) for r in plan] == [("2027-01-30", 30), ("2027-02-22", 7), ("2027-03-01", 0)]
    assert all("P123" not in str(r) and "My passport" not in str(r) for r in plan)   # nothing private outside the vault
    assert docs.due(plan, dt.date(2027, 1, 29), set()) == []
    first = docs.due(plan, dt.date(2027, 2, 1), set())
    assert [r["days"] for r in first] == [30] and docs.reminder_text(first[0]) == "Passport expires in 1 month."
    late = docs.due(plan, dt.date(2027, 2, 25), {first[0]["key"]})       # MyVault was off for a while: one notice
    assert [r["days"] for r in late] == [7]
    assert docs.due(plan, dt.date(2027, 3, 2), set()) == []               # expired: no more reminders
    e.fields["remind_name"] = "Ahmed's passport"
    assert docs.reminder_text(docs.schedule([e])[-1]) == "Ahmed's passport expires today."

    with tf.TemporaryDirectory() as d:
        saved = docs.files_dir
        docs.files_dir = lambda: P(d)
        try:
            jpg = b"\xff\xd8\xff\xe0" + os.urandom(2000)
            ref = docs.seal(jpg, r"C:\scans\passport.jpg")
            assert ref["mime"] == "image/jpeg" and ref["name"] == "passport.jpg" and docs.open_sealed(ref) == jpg
            assert jpg[100:200] not in (P(d) / f"{ref['id']}.bin").read_bytes()      # stored encrypted
            blob = docs.read_blob(ref["id"])
            try:
                docs.store_blob({**ref, "key": docs.seal(jpg, "x.jpg")["key"]}, blob)   # wrong key: refused
                raise AssertionError("accepted a file that doesn't match its key")
            except ValueError:
                pass
            try:
                docs.seal(b"MZ\x90\x00 not a document", "virus.exe")
                raise AssertionError("accepted a non-document file")
            except ValueError:
                pass
            e.fields["files"] = json.dumps([ref])
            assert docs.cleanup([e]) == 1 and docs.have(ref["id"])               # the stray one went, ours stayed
            e.deleted = True
            assert docs.cleanup([e]) == 1 and not docs.have(ref["id"])
        finally:
            docs.files_dir = saved


def test_pc_reminders_notify_once_while_locked():
    import datetime as dt
    from myvault import app, config, docs
    memory = {}
    saved = config.load, config.save, docs.load_schedule
    config.load, config.save = (lambda: dict(memory)), memory.update
    soon = (dt.date.today() + dt.timedelta(days=7)).isoformat()
    docs.load_schedule = lambda: docs.schedule([Entry(id="p", kind="document", fields={
        "doc_type": "visa", "expires": soon, "remind": "30,7", "remind_name": "Sara's visa"})])
    try:
        api = app.Api()                    # locked: no vault, just the schedule file
        told = []
        api._tell = lambda title, text: told.append(text)
        api._check_reminders()
        api._check_reminders()             # the next check doesn't repeat it
        assert told == ["Sara's visa expires in 1 week."], told
        assert len(memory["reminders_shown"]) == 1
    finally:
        config.load, config.save, docs.load_schedule = saved


class _DocProvider(_Provider):
    """A 0.6 device with its own store of (encrypted) document files."""
    def __init__(self, vault, files=None, sync_files=True):
        super().__init__(vault)
        self.files, self.on = dict(files or {}), sync_files
    def app_version(self): return "0.6.0"
    def platform(self): return "test"
    def file_sync(self): return self.on
    def file_refs(self):
        from myvault import docs
        return {r["id"]: r for e in self.vault.active_entries() if e.kind == "document" for r in docs.refs(e.fields)}
    def has_file(self, i): return i in self.files
    def read_file(self, i): return self.files[i]
    def store_file(self, i, blob):
        from myvault import docs
        docs.open_sealed(self.file_refs()[i], blob)        # must open with the vault's key
        self.files[i] = blob


def test_sync_swaps_document_files_and_respects_the_switch():
    import json
    import tempfile as tf
    from pathlib import Path as P
    from myvault import docs
    with tf.TemporaryDirectory() as d:
        saved = docs.files_dir
        docs.files_dir = lambda: P(d)
        try:
            ref = docs.seal(b"%PDF-1.4 tenancy " + os.urandom(3 * 1024 * 1024), "lease.pdf")   # spans chunks
            blob = docs.read_blob(ref["id"])
        finally:
            docs.files_dir = saved
        for b_on, expect in ((True, 1), (False, 0)):
            va = Vault.create(P(d) / f"a{b_on}.dat", "pw-aaaaaaaa")
            vb = Vault.create(P(d) / f"b{b_on}.dat", "pw-bbbbbbbb")
            va.device_id, vb.device_id = "A", "B"
            va.entries = [Entry(id="doc", kind="document", title="Lease", fields={"files": json.dumps([ref])})]
            pa, pb = _DocProvider(va, {ref["id"]: blob}), _DocProvider(vb, sync_files=b_on)
            session = sync.PairingSession(pa, port=0, ttl=10)
            uri = session.uri.replace(session.uri.split("h=")[1].split("&")[0], "127.0.0.1")
            r = sync.connect_and_sync(uri, pb)
            _wait_done(session)
            assert r.ok and not r.files_error, (r.error, r.files_error)
            assert [e.id for e in vb.entries] == ["doc"]                # the details always sync
            assert r.files_received == expect and (ref["id"] in pb.files) == bool(expect), (b_on, r)
            assert pb.files.get(ref["id"], blob) == blob


def test_arabic_translations_keep_placeholders():
    import json, re
    for f in [ROOT / "myvault" / "ui" / "ar.json", ROOT / "browser-extension" / "_locales" / "ar" / "messages.json"]:
        if not f.exists():
            continue
        table = json.loads(f.read_text("utf-8"))
        for en, ar in table.items():
            if isinstance(ar, dict):          # extension format: {"message": ...}
                continue
            assert ar.strip(), f"empty translation for {en!r}"
            assert sorted(re.findall(r"\{t?\d\}", en)) == sorted(re.findall(r"\{t?\d\}", ar)), (en, ar)


def test_rollback_picks_previous_stable_signed_release():
    import json
    import urllib.error
    from myvault import update
    saved_key, saved_get = update.UPDATE_PUBKEY, update._get
    try:
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            bad = _signed_release(tmp, "0.5.2", {"windows": ("MyVault-Setup-0.5.2.exe", b"a")})  # key replaced below
            good = _signed_release(tmp, "0.5.1", {"windows": ("MyVault-Setup-0.5.1.exe", b"b")})
            assets = {"0.5.2": bad, "0.5.1": good}
            listing = [{"tag_name": "v0.6.0"}, {"tag_name": "v0.5.4"}, {"tag_name": "v0.5.3", "prerelease": True},
                       {"tag_name": "v0.5.2"}, {"tag_name": "v0.5.1"}, {"tag_name": "v0.4.1"}]

            def fake_get(url, limit):
                if url == update.RELEASES_API:
                    return json.dumps(listing).encode()
                for v, (raw, sig) in assets.items():
                    if url.endswith(f"/v{v}/latest.json"):
                        return raw
                    if url.endswith(f"/v{v}/latest.json.sig"):
                        return sig.encode()
                raise urllib.error.HTTPError(url, 404, "Not Found", None, None)   # v0.4.1: no manifest

            update._get = fake_get
            m, _, _ = update.previous_release("0.5.4")
            # newer and pre-release skipped, 0.5.2's signature fails, so 0.5.1
            assert m["version"] == "0.5.1", m
            try:
                update.previous_release("0.5.1")      # only 0.4.1 is older, and it isn't signed
                raise AssertionError("an unsigned release was offered")
            except update.UpdateError:
                pass
    finally:
        update.UPDATE_PUBKEY, update._get = saved_key, saved_get


def test_update_handover_over_sync_and_tamper_rejected():
    from myvault import update
    saved_key = update.UPDATE_PUBKEY
    with tempfile.TemporaryDirectory() as d:
        os.environ["LOCALAPPDATA"] = d
        tmp = Path(d)
        installer = os.urandom(3 * (1 << 20) + 123)           # spans several 1 MB chunks
        raw, sig = _signed_release(tmp, "0.9.0", {"windows": ("MyVault-Setup-0.9.0.exe", installer)})
        pkg = update.Package("windows", "0.9.0", tmp / "MyVault-Setup-0.9.0.exe", raw, sig)
        try:
            # A newer phone hands the PC installer to an older PC during a sync.
            pc = _UpdatingProvider(Vault.create(tmp / "pc.dat", "pc-pass-123"), "0.5.0", "windows")
            phone = _UpdatingProvider(Vault.create(tmp / "ph.dat", "ph-pass-123"), "0.9.0", "android", pkg)
            pc.vault.device_id, phone.vault.device_id = "PC", "PHONE"
            s = sync.PairingSession(pc, port=0, ttl=10)
            uri = s.uri.replace(s.uri.split("h=")[1].split("&")[0], "127.0.0.1")
            r = sync.connect_and_sync(uri, phone)
            _wait_done(s)
            assert r.ok and r.sent == "0.9.0" and r.peer_version == "0.5.0", r
            assert s.result.received == "0.9.0" and s.result.peer_version == "0.9.0", s.result
            assert pc.stored.path.read_bytes() == installer
            assert update.packages()["windows"].version == "0.9.0"

            # A tampered package is refused, and the sync itself still succeeds.
            bad = bytearray(installer); bad[100] ^= 1
            (tmp / "MyVault-Setup-0.9.0.exe").write_bytes(bytes(bad))
            pc2 = _UpdatingProvider(Vault.create(tmp / "pc2.dat", "pc-pass-123"), "0.5.0", "windows")
            s2 = sync.PairingSession(pc2, port=0, ttl=10)
            uri2 = s2.uri.replace(s2.uri.split("h=")[1].split("&")[0], "127.0.0.1")
            assert sync.connect_and_sync(uri2, phone).ok
            _wait_done(s2)
            assert s2.result.ok and not s2.result.received and "fingerprint" in s2.result.update_error

            # An unsigned (wrong-key) manifest is refused outright.
            try:
                update.verify_manifest(raw, base64.b64encode(b"x" * 64).decode())
            except update.UpdateError:
                pass
            else:
                raise AssertionError("bad signature accepted")
            assert update.newer("0.10.0", "0.9.9") and not update.newer("0.5.0", "0.5.0")
        finally:
            update.UPDATE_PUBKEY = saved_key


def test_autostart_follows_windows_startup_switch():
    if sys.platform != "win32":
        return
    import winreg
    from myvault import autostart as a
    name = "MyVault-selftest"                 # never the real entry
    try:
        a.set_enabled(True, name=name, cmd="C:/x/MyVault.exe --minimized")
        assert a.enabled(name)
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, a.APPROVED) as k:   # "Off" in Settings > Startup
            winreg.SetValueEx(k, name, 0, winreg.REG_BINARY, bytes([3] + [0] * 11))
        assert not a.enabled(name)
        a.set_enabled(True, name=name, cmd="x")                            # back on from MyVault
        assert a.enabled(name)
    finally:
        a.set_enabled(False, name=name)
    assert not a.enabled(name)


def test_sync_uri_roundtrip():
    key = os.urandom(32)
    hosts, port, k = sync.parse_uri(sync.make_uri(["192.168.1.5", "10.0.0.2"], 8789, key))
    assert hosts == ["192.168.1.5", "10.0.0.2"] and port == 8789 and k == key
    for bad in ("https://x", "myvault://sync?v=1&h=a&p=1&k=AA"):
        try:
            sync.parse_uri(bad)
        except (ValueError, KeyError):
            pass
        else:
            raise AssertionError(bad)


def test_paper_backup_roundtrip():
    entries = [
        Entry(title="Bank (main)", username="me", password="p)a\\ss(").to_dict(),
        Entry(kind="api", title="Stripe", fields={"client_id": "ci", "client_secret": "cs"}).to_dict(),
        Entry(kind="ssh", title="VPS", fields={"private_key": "-----BEGIN-----\n" + "A" * 3000}).to_dict(),
    ]
    pdf = paper.build_pdf(entries, "backup-password")
    assert pdf.startswith(b"%PDF") and b"Bank" not in pdf and b"Stripe" not in pdf
    got, bad = paper.read_pdf(pdf, "backup-password")
    assert bad == 0 and [g["id"] for g in got] == [e["id"] for e in entries]
    assert got[0]["password"] == entries[0]["password"]
    assert got[1]["fields"]["client_secret"] == "cs"
    assert got[2]["fields"]["private_key"] == entries[2]["fields"]["private_key"]
    try:
        paper.read_pdf(pdf, "wrong-password")
    except paper.BackupError:
        pass
    else:
        raise AssertionError("wrong backup password accepted")
    # Pasted / typed text (lowercase, odd spacing) decodes too.
    text = "\n".join(f"ENTRY 1 / 1\n{b.lower()[:40]}  {b.lower()[40:]}" for b in
                     paper.encrypt_entries(entries[:1], "pw-123456789"))
    assert paper.decrypt_blocks(paper.extract_blocks(text.upper()), "pw-123456789")[0][0]["title"] == "Bank (main)"


def test_entry_kinds_search_and_names():
    e = Entry.from_dict({"kind": "api", "fields": {"service": "OpenWeather", "api_key": "SECRET"}})
    assert e.display_name() == "OpenWeather"
    assert e.matches("openweather") and not e.matches("secret")
    assert Entry.from_dict({"kind": "bogus"}).kind == "login"
    note = Entry(kind="note", title="Backup codes", notes="AAA\nBBB")
    from myvault import app
    assert app._summary(note)["subtitle"] == ""          # never shown in the sidebar
    assert note.matches("backup") and not note.matches("aaa")


def test_connector_signup_save_and_match():
    import json
    import urllib.request
    from myvault import app, server
    with tempfile.TemporaryDirectory() as d:
        api = app.Api()
        api._vault = Vault.create(Path(d) / "v.dat", "pw-12345678")
        conn = server.Connector(app._ConnectorProvider(api), "tok", 0)
        conn.start()
        port = conn._httpd.server_address[1]

        def post(path, body, token="tok"):
            req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", json.dumps(body).encode(),
                                         {"X-MyVault-Token": token, "Content-Type": "application/json"})
            try:
                return json.loads(urllib.request.urlopen(req, timeout=5).read())
            except urllib.error.HTTPError as e:
                return {"status": e.code}
        try:
            assert post("/match", {"domain": "x.com"}, token="wrong") == {"status": 401}
            r = post("/save", {"domain": "shop.example.com", "email": "a@b.c", "password": "Gen-123",
                               "region": "UAE", "extra": {"First name": "Ahmed"}})
            assert r["ok"] and r["action"] == "created"
            e = api._vault.get(r["id"])
            assert (e.website, e.region, e.custom["First name"]) == ("shop.example.com", "UAE", "Ahmed")
            m = post("/match", {"domain": "www.shop.example.com"})
            assert [x["password"] for x in m["matches"]] == ["Gen-123"]
            assert post("/match", {"domain": "evil-shop.example.com.attacker.io"})["matches"] == []
            api._vault = None                          # locked: nothing comes out
            assert post("/match", {"domain": "shop.example.com"}) == {"status": 423}
        finally:
            conn.stop()


def _run_all():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    passed = 0
    for t in tests:
        t()
        print(f"  PASS  {t.__name__}")
        passed += 1
    print(f"\n{passed}/{len(tests)} tests passed.")


if __name__ == "__main__":
    _run_all()
