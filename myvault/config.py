"""Small persistent settings for the browser connector (NOT the vault).

Holds the loopback port and the pairing token the browser extension must send.
This file contains NO passwords and NO vault data — only the connector token,
which is useless on its own (the vault stays encrypted and the server only
serves data while the app is unlocked). Stored next to the vault, in your
user profile.
"""

from __future__ import annotations

import json
import secrets
from pathlib import Path

from . import paths

CONNECTOR_FILE = "connector.json"
DEFAULT_PORT = 8787


def _config_path() -> Path:
    return paths.data_dir() / CONNECTOR_FILE


def load() -> dict:
    path = _config_path()
    data = {}
    if path.exists():
        try:
            data = json.loads(path.read_text("utf-8"))
        except (ValueError, OSError):
            data = {}
    changed = False
    if not data.get("token"):
        data["token"] = secrets.token_urlsafe(24)
        changed = True
    if not data.get("port"):
        data["port"] = DEFAULT_PORT
        changed = True
    if "enabled" not in data:
        data["enabled"] = True
        changed = True
    if changed:
        save(data)
    return data


def save(data: dict) -> None:
    _config_path().write_text(json.dumps(data, indent=2), "utf-8")


def regenerate_token() -> dict:
    data = load()
    data["token"] = secrets.token_urlsafe(24)
    save(data)
    return data
