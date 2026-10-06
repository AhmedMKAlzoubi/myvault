"""A copy of a vault as one .zip, to keep somewhere safe or move to another
device: the PC and the phone make and read the same format.

Encrypted copy: myvault.json (its name and sync id), vault.dat and
files/<id>.bin exactly as they are on disk. It opens only with the vault's
master password.

Readable copy: README.txt, entries.json, logins.csv (the usual columns, so
other password managers import it) and the files themselves. Anyone who has
it can read everything."""

import csv
import io
import json
import re
import zipfile
from pathlib import Path

from . import crypto, docs

_MEMBER = re.compile(r"^(myvault\.json|vault\.dat|files/[0-9a-f]{32}\.bin)$")
MAX_COPY = 2 * 1024 ** 3                # what a copy may unpack to (files are 20 MB each at most)

README = """This is a READABLE copy of your MyVault vault "{name}". It is NOT encrypted.

Anyone who opens this file can read every password, key and document in it.
Keep it offline (a USB stick in a drawer, not email or cloud storage), and
delete it, and empty the Recycle Bin, when you no longer need it.

entries.json  everything, as MyVault keeps it
logins.csv    your logins, ready to import into another password manager
files/        the photos and PDFs attached to your entries
"""


def _write(target: Path, fill) -> None:
    tmp = target.with_name(target.name + ".part")
    try:
        with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
            fill(z)
        tmp.replace(target)
    finally:
        tmp.unlink(missing_ok=True)


def save_encrypted(target: Path, vault_file: Path, name: str, vault_id: str, entries) -> None:
    def fill(z):
        z.writestr("myvault.json", json.dumps({"app": "MyVault", "copy": 1, "name": name, "vault_id": vault_id}))
        z.write(vault_file, "vault.dat")
        for e in entries:
            if not e.deleted:
                for r in docs.refs(e.fields):
                    if docs.have(r["id"]):
                        z.writestr(f"files/{r['id']}.bin", docs.read_blob(r["id"]))
    _write(target, fill)


def save_readable(target: Path, name: str, entries) -> None:
    live = [e for e in entries if not e.deleted]
    def fill(z):
        z.writestr("README.txt", README.format(name=name))
        z.writestr("entries.json", json.dumps([e.to_dict() for e in live], ensure_ascii=False, indent=1))
        out = io.StringIO()
        w = csv.writer(out)
        w.writerow(["name", "url", "username", "password", "note"])
        for e in live:
            if e.kind == "login":
                w.writerow([e.title, e.website, e.username or e.email, e.password, e.notes])
        z.writestr("logins.csv", out.getvalue())
        used = set()
        for e in live:
            for r in docs.refs(e.fields):
                if not docs.have(r["id"]):
                    continue
                base = re.sub(r'[\\/:*?"<>|]+', "_", f"{e.title or 'Entry'} - {r.get('name') or 'file'}")[:120]
                n, stem = 2, base
                while base.casefold() in used:
                    base, n = f"{n} {stem}", n + 1
                used.add(base.casefold())
                z.writestr(f"files/{base}", docs.open_sealed(r))
    _write(target, fill)


def read_encrypted(src: Path) -> tuple[dict, zipfile.ZipFile]:
    """Check a copy before adding it. Raises ValueError with a message for people."""
    try:
        z = zipfile.ZipFile(src)
    except (OSError, zipfile.BadZipFile):
        raise ValueError("That isn't a MyVault copy.") from None
    names = z.namelist()
    try:
        if "README.txt" in names and "entries.json" in names:
            raise ValueError("That's a readable copy. Use Import passwords for its logins.csv instead.")
        if "vault.dat" not in names or not all(_MEMBER.match(n) for n in names):
            raise ValueError("That isn't a MyVault copy.")
        if sum(i.file_size for i in z.infolist()) > MAX_COPY:
            raise ValueError("That copy is too big.")
        if json.loads(z.read("vault.dat")).get("magic") != crypto.MAGIC:
            raise ValueError("That isn't a MyVault copy.")
        meta = json.loads(z.read("myvault.json")) if "myvault.json" in names else {}
    except (ValueError, KeyError) as exc:
        z.close()
        if isinstance(exc, ValueError) and not isinstance(exc, json.JSONDecodeError):
            raise
        raise ValueError("That copy is damaged.") from None
    except Exception:
        z.close()
        raise ValueError("That copy is damaged.") from None
    return meta, z


def unpack(z: zipfile.ZipFile, home: Path) -> None:
    home.mkdir(parents=True, exist_ok=True)
    for n in z.namelist():
        if n != "myvault.json":                 # names were checked: no paths outside home
            (home / n).parent.mkdir(exist_ok=True)
            (home / n).write_bytes(z.read(n))
