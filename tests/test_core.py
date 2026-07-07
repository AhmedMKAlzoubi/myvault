"""Core logic tests (no GUI). Run:  python -m pytest  (or)  python tests/test_core.py"""

import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from myvault import crypto, webmatch
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
