"""Interface language. English is written in the code; ui/ar.json maps each
English string to Arabic. Keys with {0}, {1}... match strings built from
templates, and a {t0} group is translated as well (see t() in ui/app.js)."""

from __future__ import annotations

import ctypes
import json
import locale
import os
import re
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


@lru_cache(maxsize=1)
def _patterns() -> list:
    out = []
    for k in sorted((k for k in arabic() if re.search(r"\{t?\d\}", k)), key=len, reverse=True):
        names = re.findall(r"\{(t?\d)\}", k)
        body = "".join(r"([\s\S]+?)" if re.fullmatch(r"\{t?\d\}", part) else re.escape(part)
                       for part in re.split(r"(\{t?\d\})", k))
        out.append((re.compile(f"^{body}$"), names, arabic()[k]))
    return out


def translate(s: str) -> str:
    """Arabic for an English string, the same way as t() in ui/app.js."""
    table, core = arabic(), s.strip()
    if not core:
        return s
    if core in table:
        return s.replace(core, table[core])
    for rx, names, out in _patterns():
        m = rx.match(core)
        if m:
            def fill(g):
                v = m.group(names.index(g.group(1)) + 1)
                return translate(v) if g.group(1).startswith("t") else v
            return s.replace(core, re.sub(r"\{(t?\d)\}", fill, out))
    return s


def tr(s: str) -> str:
    """For the strings Python shows itself (tray menu, notifications)."""
    return translate(s) if language() == "ar" else s
