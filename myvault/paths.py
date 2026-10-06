"""Where MyVault stores its data on each operating system.

The vault file lives OUTSIDE the code folder (in your user profile) so that
updating or moving the app never touches your data, and so the file is not
accidentally committed to git.

You can keep several vaults ("Work", "Home"...), each an encrypted file with
its own master password, files, backups and reminders. The first one is the
original vault.dat in the data folder; the others live in vaults/<id>/.
vaults.json lists their names, so the lock screen can offer them.
"""

from __future__ import annotations

import json
import os
import re
import sys
import uuid
from pathlib import Path

APP_DIR_NAME = "MyVault"
VAULT_FILE = "vault.dat"
REGISTRY = "vaults.json"
DEFAULT = "default"                # the original vault's id
_ID = re.compile(r"^(default|[0-9a-f]{32})$")
_current = DEFAULT


def data_dir() -> Path:
    if os.name == "nt":  # Windows
        base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
    elif sys.platform == "darwin":  # macOS
        base = os.path.expanduser("~/Library/Application Support")
    else:  # Linux and others
        base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    d = Path(base) / APP_DIR_NAME
    d.mkdir(parents=True, exist_ok=True)
    return d


# ---- several vaults ------------------------------------------------------------------
def vaults() -> list[dict]:
    """[{"id", "name"}], the original vault first. Names aren't secret: the lock screen shows them."""
    try:
        listed = json.loads((data_dir() / REGISTRY).read_text("utf-8"))
        out = [v for v in listed if isinstance(v, dict) and _ID.match(str(v.get("id", "")))]
    except (OSError, ValueError):
        out = []
    if not any(v["id"] == DEFAULT for v in out):
        out.insert(0, {"id": DEFAULT, "name": "My vault"})
    return [{"id": v["id"], "name": str(v.get("name") or "My vault")[:40]} for v in out]


def save_vaults(listed: list[dict]) -> None:
    p = data_dir() / REGISTRY
    tmp = p.with_suffix(".part")
    tmp.write_text(json.dumps([{"id": v["id"], "name": v["name"]} for v in listed], ensure_ascii=False), "utf-8")
    os.replace(tmp, p)


def new_vault(name: str) -> str:
    vid = uuid.uuid4().hex
    save_vaults([*vaults(), {"id": vid, "name": name.strip()[:40] or "Vault"}])
    return vid


def vault_home(vid: str | None = None) -> Path:
    """The folder that holds one vault with its files, backups and reminders."""
    vid = vid or _current
    if not _ID.match(vid):
        raise ValueError("bad vault id")
    if vid == DEFAULT:
        return data_dir()
    return data_dir() / "vaults" / vid           # made when something is first saved there


def vault_path(vid: str | None = None) -> Path:
    return vault_home(vid) / VAULT_FILE


def select(vid: str) -> None:
    """The vault the app works with from now on (the one being unlocked)."""
    global _current
    if not _ID.match(vid):
        raise ValueError("bad vault id")
    _current = vid


def current() -> str:
    return _current
