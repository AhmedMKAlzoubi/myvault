"""
The vault: your list of accounts and the file it lives in.

An Entry holds everything a site might ask at registration/sign-in. Beyond the
common fields there is a free-form `custom` dictionary so you can store anything
(security questions, membership numbers, PINs, recovery codes...).

`kind` says what the entry is: a website/app "login", an "api" credential
(client id, client secret, API key, token), an "ssh" key, or a secure "note".
Kind-specific values live in `fields` (key -> text); which keys exist and which
are secret is defined by the UI templates (ui/app.js, android lib/kinds.dart).

Each entry carries `updated_at` and a `deleted` tombstone. Those are unused by
the desktop app's day-to-day features but are the foundation for the future
LAN auto-sync: two devices can merge by keeping, per entry id, whichever copy
has the newer `updated_at` (last-write-wins). Designing them in now means the
Android app can sync without ever changing the file format.
"""

from __future__ import annotations

import json
import re
import time
import uuid
from dataclasses import dataclass, field, asdict
from pathlib import Path

from . import crypto
from .generator import PasswordPolicy

VAULT_CONTENT_VERSION = 2

KINDS = ("login", "api", "ssh", "note", "document")

# Values in `fields` that are safe to search on (never a secret).
SEARCHABLE_FIELDS = ("service", "client_id", "endpoint", "host", "ssh_user", "fingerprint", "holder", "country")


def _now() -> float:
    return round(time.time(), 3)


@dataclass
class Entry:
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    kind: str = "login"        # login | api | ssh | note | document
    title: str = ""            # what you call it, e.g. "Netflix"
    website: str = ""          # e.g. netflix.com
    app: str = ""              # app name, if it's an app rather than a website
    username: str = ""
    email: str = ""
    password: str = ""
    region: str = ""
    age: str = ""
    gender: str = ""
    phone: str = ""
    notes: str = ""
    custom: dict = field(default_factory=dict)     # anything else, key -> value
    fields: dict = field(default_factory=dict)     # kind-specific values, key -> value
    password_policy: dict = field(default_factory=lambda: PasswordPolicy().to_dict())
    created_at: float = field(default_factory=_now)
    updated_at: float = field(default_factory=_now)
    deleted: bool = False      # tombstone for sync; hidden from the list

    def touch(self) -> None:
        self.updated_at = _now()

    def matches(self, query: str) -> bool:
        q = query.strip().lower()
        if not q:
            return True
        haystack = " ".join(
            str(v) for v in (
                self.title, self.website, self.app, self.username,
                self.email, "" if self.kind == "note" else self.notes,   # a note's body is secret
            )
        ).lower()
        haystack += " " + " ".join(str(k) + " " + str(v) for k, v in self.custom.items()).lower()
        haystack += " " + " ".join(str(self.fields.get(k, "")) for k in SEARCHABLE_FIELDS).lower()
        return q in haystack

    def display_name(self) -> str:
        return (self.title or self.website or self.app or self.fields.get("service", "")
                or self.fields.get("host", "") or self.username or self.email or "(untitled)")

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> "Entry":
        known = {f for f in cls.__dataclass_fields__}
        e = cls(**{k: v for k, v in data.items() if k in known})
        if e.kind not in KINDS:
            e.kind = "login"
        if e.deleted:
            e.wipe()        # also cleans deletion markers made by older versions
        return e

    def wipe(self) -> None:
        """A deleted entry's marker keeps only what sync needs to pass the deletion
        on (id, kind, dates): nothing of what was in it."""
        blank = Entry(id=self.id, kind=self.kind, created_at=self.created_at,
                      updated_at=self.updated_at, deleted=True)
        self.__dict__.update(blank.__dict__)


HISTORY_KEEP = 10

# An email address with a name, an @ and a full domain (gmail.com, not gmail).
EMAIL = re.compile(r"[^@\s]+@[^@\s.]+(\.[^@\s.]+)*\.[^@\s.]{2,}")


def email_problem(e: "Entry") -> str:
    """Why the entry's email address can't be right, or "" (same rule as the phone)."""
    for value in (e.email, e.fields.get("email", "")):
        if value and not EMAIL.fullmatch(value.strip()):
            return f"“{value.strip()}” isn't a complete email address. It needs a name, @ and the full domain, such as name@gmail.com."
    return ""


def keep_old_password(e: Entry, old: str) -> None:
    """When a login's password changes, the old one goes into its history
    (fields["password_history"], newest first). Same as keepOldPassword() on the phone."""
    if not old or old == e.password:
        return
    try:
        past = json.loads(e.fields.get("password_history") or "[]")
    except ValueError:
        past = []
    e.fields["password_history"] = json.dumps([{"password": old, "until": _now()}, *past][:HISTORY_KEEP])


class Vault:
    """In-memory vault plus load/save to an encrypted file."""

    def __init__(self, path: Path, password: str):
        self.path = Path(path)
        self._password = password
        self.entries: list[Entry] = []
        self.device_id: str = str(uuid.uuid4())
        self.updated_at: float = _now()
        # The same vault on your PC and phone shares this id (set at their first
        # sync), so a sync never mixes two different vaults.
        self.vault_id: str = ""
        self.on_save = None       # called after every save (the app refreshes reminders)

    # ---- persistence -----------------------------------------------------
    @classmethod
    def create(cls, path: Path, password: str) -> "Vault":
        v = cls(path, password)
        v.save()
        return v

    @classmethod
    def open(cls, path: Path, password: str) -> "Vault":
        file_bytes = Path(path).read_bytes()
        plaintext = crypto.decrypt(file_bytes, password)   # may raise WrongPasswordError
        data = json.loads(plaintext.decode("utf-8"))
        v = cls(path, password)
        v.device_id = data.get("device_id", v.device_id)
        v.updated_at = data.get("updated_at", _now())
        v.vault_id = str(data.get("vault_id", ""))
        v.entries = [Entry.from_dict(e) for e in data.get("entries", [])]
        return v

    def save(self) -> None:
        self.updated_at = _now()
        payload = {
            "content_version": VAULT_CONTENT_VERSION,
            "device_id": self.device_id,
            "updated_at": self.updated_at,
            "vault_id": self.vault_id,
            "entries": [e.to_dict() for e in self.entries],
        }
        plaintext = json.dumps(payload).encode("utf-8")
        file_bytes = crypto.encrypt(plaintext, self._password)

        # Write atomically: write to a temp file then replace, so a crash mid-write
        # can never corrupt your only copy of the vault.
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(self.path.suffix + ".tmp")
        tmp.write_bytes(file_bytes)
        tmp.replace(self.path)
        if self.on_save:
            self.on_save()

    def change_password(self, new_password: str) -> None:
        self._password = new_password
        self.save()

    # ---- entry operations ------------------------------------------------
    def active_entries(self) -> list[Entry]:
        return [e for e in self.entries if not e.deleted]

    def search(self, query: str) -> list[Entry]:
        items = [e for e in self.active_entries() if e.matches(query)]
        return sorted(items, key=lambda e: e.display_name().lower())

    def get(self, entry_id: str) -> Entry | None:
        return next((e for e in self.entries if e.id == entry_id), None)

    def add(self, entry: Entry) -> Entry:
        self.entries.append(entry)
        self.save()
        return entry

    def update(self, entry: Entry) -> None:
        entry.touch()
        self.save()

    def delete(self, entry_id: str) -> None:
        entry = self.get(entry_id)
        if entry:
            # Soft-delete (tombstone) so a future sync can propagate the deletion.
            entry.wipe()
            entry.touch()
            self.save()
