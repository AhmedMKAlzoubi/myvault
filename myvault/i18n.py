"""Interface language. English is written in the code; ui/ar.json maps each
English string to Arabic. Keys with {0}, {1}... match strings built from
templates, and a {t0} group is translated as well (see t() in ui/app.js)."""

from __future__ import annotations

import ctypes
import json
import locale
import os
from functools import lru_cache
from pathlib import Path

from . import config

CHOICES = ("auto", "en", "ar")        # auto = follow Windows
AR_FILE = Path(__file__).resolve().parent / "ui" / "ar.json"


def system_language() -> str:
    try:
        if os.name == "nt":
            return "ar" if ctypes.windll.kernel32.GetUserDefaultUILanguage() & 0x3FF == 0x01 else "en"
        return "ar" if (locale.getlocale()[0] or "").lower().startswith("ar") else "en"
    except Exception:
        return "en"


def choice() -> str:
    pick = config.load().get("language", "auto")
    return pick if pick in CHOICES else "auto"


def language() -> str:
    pick = choice()
    return system_language() if pick == "auto" else pick


@lru_cache(maxsize=1)
def arabic() -> dict[str, str]:
    return json.loads(AR_FILE.read_text("utf-8"))


def tr(s: str) -> str:
    """For the few strings Python shows itself (tray menu and its notice)."""
    return arabic().get(s, s) if language() == "ar" else s
