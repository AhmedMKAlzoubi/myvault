"""Where MyVault stores its data on each operating system.

The vault file lives OUTSIDE the code folder (in your user profile) so that
updating or moving the app never touches your data, and so the file is not
accidentally committed to git.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

APP_DIR_NAME = "MyVault"
VAULT_FILE = "vault.dat"


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


def vault_path() -> Path:
    return data_dir() / VAULT_FILE
