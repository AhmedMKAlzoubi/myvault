"""
Import logins from another password manager's CSV export: Chrome, Edge,
Firefox, Bitwarden, LastPass, 1Password, KeePass, Proton Pass and most others.
Columns are recognised by name; rows already in the vault are skipped.
"""

from __future__ import annotations

import csv
import io

from . import otp
from .vault import Entry
from .webmatch import normalize_host

# column name (lowercase) -> what it holds
_COLUMNS = {
    "title": ("name", "title", "account", "item name"),
    "website": ("url", "login_uri", "website", "web site", "uri", "login url", "urls", "hostname"),
    "username": ("username", "login_username", "user name", "login", "user", "login name"),
    "email": ("email", "e-mail", "email address"),
    "password": ("password", "login_password"),
    "notes": ("note", "notes", "extra", "comments"),
    "totp": ("totp", "login_totp", "otpauth", "one-time password", "otp", "2fa"),
    "type": ("type",),
}


def read_csv(text: str, existing=()) -> tuple[list[Entry], int]:
    """(new entries, rows skipped because they're already in the vault)."""
    rows = list(csv.reader(io.StringIO(text.lstrip("﻿"))))
    if not rows:
        return [], 0
    head = [h.strip().lower() for h in rows[0]]
    col = {what: next((head.index(n) for n in names if n in head), None) for what, names in _COLUMNS.items()}
    if col["password"] is None:
        raise ValueError("That file has no password column. Export your passwords as CSV and try again.")
    seen = {(normalize_host(e.website), e.username or e.email, e.password)
            for e in existing if not e.deleted and e.kind == "login"}
    out, skipped = [], 0
    for row in rows[1:]:
        get = lambda what: (row[col[what]].strip() if col[what] is not None and col[what] < len(row) else "")
        password, login = get("password"), get("username") or get("email")
        if get("type") and get("type").lower() not in ("login", "1"):      # Bitwarden's notes, cards…
            continue
        if not password and not login:
            continue
        url = get("website").split(",")[0].strip()
        host = normalize_host(url)
        key = (host, login, password)
        if key in seen:
            skipped += 1
            continue
        seen.add(key)
        e = Entry(kind="login", title=get("title") or host or login, website=host or url,
                  password=password, notes=get("notes"))
        e.username, e.email = get("username"), get("email")
        if not e.email and "@" in e.username:          # most exports put the email in "username"
            e.email, e.username = e.username, ""
        try:
            if get("totp"):
                otp.parse(get("totp"))
                e.fields["totp"] = get("totp")
        except ValueError:
            pass
        out.append(e)
    return out, skipped
