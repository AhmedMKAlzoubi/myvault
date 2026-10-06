"""
Password health: weak and reused passwords, and (only when asked) leaked ones.

The leak check uses Have I Been Pwned's range API (k-anonymity): only the first
5 characters of each password's SHA-1 hash are sent, and the matching happens
here. The password, and even its full hash, never leave this PC. The phone
does the same (lib/health.dart).
"""

from __future__ import annotations

import hashlib
import urllib.request
from collections import defaultdict

from .generator import strength_label

RANGE_URL = "https://api.pwnedpasswords.com/range/"


def report(entries) -> dict:
    """{"total": logins with a password, "weak": [ids], "reused": [[ids], ...]}."""
    logins = [e for e in entries if not e.deleted and e.kind == "login" and e.password]
    same = defaultdict(list)
    for e in logins:
        same[e.password].append(e.id)
    return {"total": len(logins),
            "weak": [e.id for e in logins if strength_label(e.password) == "Weak"],
            "reused": [ids for ids in same.values() if len(ids) > 1]}


def _fetch(prefix: str) -> str:
    req = urllib.request.Request(RANGE_URL + prefix, headers={"Add-Padding": "true", "User-Agent": "MyVault"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return r.read().decode("utf-8", "replace")


def leaks(passwords, fetch=_fetch) -> dict[str, int]:
    """How many times each password appears in known leaks (0 = not found)."""
    out = {}
    for pw in set(passwords):
        # SHA-1 because that's what the service's range API uses, not for security
        h = hashlib.sha1(pw.encode("utf-8"), usedforsecurity=False).hexdigest().upper()
        counts = {}
        for line in fetch(h[:5]).splitlines():
            suffix, _, n = line.strip().partition(":")
            counts[suffix] = int(n or 0)
        out[pw] = counts.get(h[5:], 0)
    return out
