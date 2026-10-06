"""
The MyVault desktop window.

The UI is plain HTML/CSS/JS (myvault/ui/) shown in a native window by pywebview
(Edge WebView2 on Windows). It is loaded as an inline string, never from a web
server, and its Content-Security-Policy forbids any network access. The page
talks to Python only through the `Api` object below.

The vault itself never touches the network. The browser connector (server.py)
listens only on 127.0.0.1 while unlocked; QR sync (sync.py) listens on the LAN
only while the "Sync with phone" sheet is open.
"""

from __future__ import annotations

import base64
import csv
import ctypes
import ipaddress
import json
import os
import shutil
import subprocess
import sys
import threading
import time
import uuid
import webbrowser
from pathlib import Path

import segno
import webview

from . import STORE, __version__, autostart, autotype, clipboard, config, crypto, docs, export, health, i18n, importer, otp, paper, paths, server, sync, update, webmatch
from .generator import PasswordPolicy, generate, strength_label
from .vault import KINDS, Entry, Vault, email_problem, keep_old_password

AUTO_LOCK_CHOICES = (1, 2, 5, 10, 15, 30, 60)   # minutes; Settings > Auto-lock
CLIPBOARD_CLEAR_SECONDS = 30
# The repo root when run from source; the bundle's _internal folder when installed
# (PyInstaller lays out myvault/ and assets/ the same way).
ROOT = Path(__file__).resolve().parent.parent
UI_DIR = ROOT / "myvault" / "ui"
ICON = ROOT / "assets" / "myvault.ico"
APP_ID = "MyVault.Desktop"   # also set on the installer's shortcuts, so taskbar pins match


def app_dir() -> Path:
    """Where the program lives: the install folder for MyVault.exe, else the repo."""
    return Path(sys.executable).parent if getattr(sys, "frozen", False) else ROOT


# Next to MyVault.exe once installed (easy to pick in "Load unpacked"); the repo's
# own folder when run from source.
EXTENSION_DIR = app_dir() / "browser-extension"
TEXT_FIELDS = ("title", "website", "app", "username", "email", "password",
               "region", "age", "gender", "phone", "notes")


def _str_map(value) -> dict:
    if not isinstance(value, dict):
        return {}
    return {str(k)[:200]: str(v) for k, v in value.items() if str(k).strip()}


def _summary(e: Entry) -> dict:
    if e.kind == "login":
        sub = e.username or e.email or e.website
    elif e.kind == "api":
        sub = e.fields.get("service") or e.fields.get("client_id", "")
    elif e.kind == "ssh":
        user, host = e.fields.get("ssh_user", ""), e.fields.get("host", "")
        sub = f"{user}@{host}" if user and host else (host or user)
    else:
        sub = ""      # a secure note's text is secret: never show it in the list
    return {"id": e.id, "kind": e.kind, "title": e.display_name(), "subtitle": sub,
            "website": e.website, "updated_at": e.updated_at,
            "expires": e.fields.get("expires", "") if e.kind == "document" else "",
            "local_only": e.local_only}


class Api:
    """Every public method is callable from the page as window.pywebview.api.<name>.
    Keep all state in underscore attributes: pywebview exposes public ones."""

    def __init__(self):
        self._vault: Vault | None = None
        self._lock = threading.RLock()
        self._window = None
        self._last_activity = time.time()
        self._connector: server.Connector | None = None
        self._pairing: sync.PairingSession | None = None
        self._upd = {"checking": False, "available": "", "notes": "", "progress": 0, "busy": False, "error": ""}
        self._upd_release = None     # (manifest, raw, sig) of a newer release found online
        self._rollback = None        # (manifest, raw, sig) of the release before this one
        self._quit = None            # really exit (set by the tray, whose X only hides)
        self._tell = None            # show a notification (set by the tray)
        self._reminder_lock = threading.Lock()
        threading.Thread(target=self._reminder_loop, daemon=True).start()
        self._autotype_hwnd = 0      # the window "Type into app" will type into
        self._import_path: Path | None = None   # the CSV being imported
        self._undo: list[dict] = []  # entries the last bulk delete removed (for Undo)
        threading.Thread(target=self._autolock_loop, daemon=True).start()

    # ---- plumbing ----------------------------------------------------------
    def _js(self, code: str) -> None:
        if self._window is not None:
            try:
                self._window.evaluate_js(code)
            except Exception:
                pass

    def _need(self) -> Vault:
        if self._vault is None:
            raise PermissionError("locked")
        self._last_activity = time.time()
        return self._vault

    def _autolock_loop(self) -> None:
        while True:
            time.sleep(10)
            minutes = _autolock_minutes()
            if self._vault is not None and time.time() - self._last_activity > minutes * 60:
                self.lock()
                self._js(f"MV.onLocked('Locked after {minutes} minute{'s' if minutes != 1 else ''} without use.')")

    # ---- unlock / lock -----------------------------------------------------
    def boot(self) -> dict:
        vid = paths.current() if self._vault is not None else _last_vault()
        return {"exists": paths.vault_path(vid).exists(), "unlocked": self._vault is not None,
                "version": __version__, "autolock": _autolock_minutes(),
                "vault": vid, "vaults": self.vaults()}

    # ---- several vaults ----------------------------------------------------
    def vaults(self) -> list[dict]:
        return [{**v, "exists": paths.vault_path(v["id"]).exists()} for v in paths.vaults()]

    def create_vault(self, name: str, password: str) -> dict:
        """A new, empty vault with its own master password (it can be the same as
        another vault's), opened straight away."""
        name = str(name or "").strip()[:40]
        if not name:
            return {"ok": False, "error": "Give the vault a name, such as Work or Home."}
        if name.casefold() in (v["name"].casefold() for v in paths.vaults()):
            return {"ok": False, "error": f"You already have a vault called {name}."}
        if len(password) < 8:
            return {"ok": False, "error": "Use at least 8 characters."}
        self.lock()
        return self.unlock(password, paths.new_vault(name))

    def rename_vault(self, name: str) -> dict:
        self._need()
        name = str(name or "").strip()[:40]
        listed = paths.vaults()
        if not name:
            return {"ok": False, "error": "Give the vault a name, such as Work or Home."}
        if any(v["name"].casefold() == name.casefold() and v["id"] != paths.current() for v in listed):
            return {"ok": False, "error": f"You already have a vault called {name}."}
        paths.save_vaults([{**v, "name": name} if v["id"] == paths.current() else v for v in listed])
        return {"ok": True, "vaults": self.vaults()}

    def delete_vault(self, typed_name: str, password: str) -> dict:
        """Delete the open vault from this PC: its file, files, backups and
        reminders. Only with its exact name typed and its master password."""
        self._need()
        vid = paths.current()
        name = next(v["name"] for v in paths.vaults() if v["id"] == vid)
        if str(typed_name or "").strip() not in (name, i18n.tr(name)):     # as shown, too
            return {"ok": False, "error": "Type the vault's name exactly as it is to delete it."}
        try:
            Vault.open(paths.vault_path(), password)
        except crypto.WrongPasswordError:
            return {"ok": False, "error": "That isn't this vault's master password."}
        except crypto.VaultFormatError as exc:
            return {"ok": False, "error": str(exc)}
        self.lock()
        home = paths.vault_home(vid)
        if vid == paths.DEFAULT:              # the original vault shares its folder with the settings
            for f in (home / paths.VAULT_FILE, home / "reminders.json"):
                f.unlink(missing_ok=True)
            for d in (home / "files", home / "backups"):
                shutil.rmtree(d, ignore_errors=True)
            paths.save_vaults([{**v, "name": "My vault"} if v["id"] == vid else v for v in paths.vaults()])
        else:
            shutil.rmtree(home, ignore_errors=True)
            paths.save_vaults([v for v in paths.vaults() if v["id"] != vid])
        cfg = config.load()
        cfg.pop("last_vault", None)
        config.save(cfg)
        return {"ok": True}

    def language_state(self) -> dict:
        return {"pick": i18n.choice(), "lang": i18n.language()}

    def set_language(self, pick: str) -> dict:
        if pick in i18n.CHOICES:
            cfg = config.load()
            cfg["language"] = pick
            config.save(cfg)
            if self._window is not None:
                self._window.load_html(_page())    # the vault stays as it is (open or locked)
        return self.language_state()

    def autolock_state(self) -> dict:
        return {"minutes": _autolock_minutes(), "choices": list(AUTO_LOCK_CHOICES)}

    def set_autolock(self, minutes: int) -> dict:
        if int(minutes) in AUTO_LOCK_CHOICES:
            cfg = config.load()
            cfg["autolock_minutes"] = int(minutes)
            config.save(cfg)
        return self.autolock_state()

    def unlock(self, password: str, vault: str = "") -> dict:
        vid = str(vault or _last_vault())
        if not any(v["id"] == vid for v in paths.vaults()):
            return {"ok": False, "error": "That vault isn't here any more."}
        if self._vault is not None and paths.current() != vid:
            self.lock()
        paths.select(vid)
        path = paths.vault_path()
        try:
            with self._lock:
                if path.exists():
                    self._vault = Vault.open(path, password)
                else:
                    if len(password) < 8:
                        return {"ok": False, "error": "Use at least 8 characters."}
                    self._vault = Vault.create(path, password)
        except crypto.WrongPasswordError:
            return {"ok": False, "error": "That isn't the master password. Try again."}
        except crypto.VaultFormatError as exc:
            return {"ok": False, "error": str(exc)}
        self._last_activity = time.time()
        cfg = config.load()
        cfg["last_vault"] = vid                    # offered first next time
        config.save(cfg)
        self._vault.on_save = self._saved
        self._saved()
        try:
            docs.cleanup(self._vault.entries)
        except OSError:
            pass
        self._start_connector()
        self.check_updates()
        return {"ok": True}

    def lock(self) -> dict:
        with self._lock:
            self._vault = None
            self._undo = []
        self.sync_cancel()
        self._stop_connector()
        clipboard.wipe_now()
        return {"ok": True}

    def ping(self) -> None:
        """The page calls this on user activity, which keeps auto-lock away."""
        if self._vault is not None:
            self._last_activity = time.time()

    # ---- entries -----------------------------------------------------------
    def entries(self) -> list[dict]:
        v = self._need()
        with self._lock:
            return [_summary(e) for e in v.active_entries()]

    def entry(self, entry_id: str) -> dict | None:
        v = self._need()
        e = v.get(entry_id)
        return e.to_dict() if e and not e.deleted else None

    def save_entry(self, data: dict) -> dict:
        v = self._need()
        kind = data.get("kind", "login")
        if kind not in KINDS:
            return {"ok": False, "error": "Unknown entry type."}
        with self._lock:
            cur = v.get(str(data.get("id", ""))) if data.get("id") else None
            is_new = cur is None or cur.deleted
            # Work on a copy: a refused save must leave the entry as it was.
            e = Entry(kind=kind) if is_new else Entry.from_dict(cur.to_dict())
            old_password = e.password
            e.kind = kind
            for key in TEXT_FIELDS:
                if key in data:
                    setattr(e, key, str(data[key] or "") if key in ("password", "notes")
                            else str(data[key] or "").strip())
            e.custom = _str_map(data.get("custom"))
            e.fields = _str_map(data.get("fields"))
            if "local_only" in data:
                e.local_only = bool(data["local_only"])
            keep_old_password(e, old_password)
            if isinstance(data.get("password_policy"), dict):
                e.password_policy = PasswordPolicy.from_dict(data["password_policy"]).to_dict()
            if e.display_name() == "(untitled)":
                return {"ok": False, "error": "Give it a name first."}
            if email_problem(e):
                return {"ok": False, "error": email_problem(e)}
            if not is_new:
                cur.__dict__.update(e.__dict__)
                e = cur
            try:
                v.add(e) if is_new else v.update(e)
            except OSError as exc:
                return {"ok": False, "error": f"Couldn't write the vault file: {exc}"}
        return {"ok": True, "id": e.id}

    def delete_entry(self, entry_id: str) -> dict:
        v = self._need()
        with self._lock:
            v.delete(entry_id)
        return {"ok": True}

    def delete_entries(self, ids) -> dict:
        """Delete several at once. What was in them is kept in memory, for Undo,
        until it's used or MyVault locks."""
        v = self._need()
        with self._lock:
            found = [e for e in (v.get(str(i)) for i in (ids or [])) if e and not e.deleted]
            self._undo = [e.to_dict() for e in found]
            for e in found:
                e.wipe()
                e.touch()
            v.save()
        return {"ok": True, "count": len(found)}

    def set_local_only(self, ids, on: bool) -> dict:
        """Keep entries on this PC only (never synced), or let them sync again."""
        v = self._need()
        with self._lock:
            found = [e for e in (v.get(str(i)) for i in (ids or [])) if e and not e.deleted]
            for e in found:
                e.local_only = bool(on)
                e.touch()          # so a "sync again" goes out at the next sync
            v.save()
        return {"ok": True, "count": len(found)}

    def undo_delete(self) -> dict:
        """Bring back what the last delete_entries() removed. A restored entry is
        newer than its deletion, so the next sync brings it back elsewhere too."""
        v = self._need()
        with self._lock:
            back, self._undo = self._undo, []
            for d in back:
                restored = Entry.from_dict({**d, "deleted": False})
                restored.touch()
                cur = v.get(restored.id)
                if cur:
                    cur.__dict__.update(restored.__dict__)
                else:
                    v.entries.append(restored)
            if back:
                v.save()
        return {"ok": bool(back), "count": len(back)}

    def read_text_file(self) -> dict:
        """Pick a key file (e.g. ~/.ssh/id_ed25519) and return its text."""
        self._need()
        picked = self._window.create_file_dialog(webview.OPEN_DIALOG, directory=str(Path.home() / ".ssh"))
        if not picked:
            return {"ok": False}
        p = Path(picked[0])
        if p.stat().st_size > 64 * 1024:
            return {"ok": False, "error": "That file is too big to be a key."}
        try:
            return {"ok": True, "name": p.name, "text": p.read_text("utf-8").strip()}
        except (OSError, UnicodeDecodeError):
            return {"ok": False, "error": "That isn't a text key file."}

    # ---- documents ---------------------------------------------------------------
    def doc_add_files(self) -> dict:
        """Pick photos or PDFs. Each is encrypted the moment it's picked; the
        entry keeps the reference (with its key) when you save."""
        self._need()
        picked = self._window.create_file_dialog(
            webview.OPEN_DIALOG, allow_multiple=True,
            file_types=("Photos and PDFs (*.jpg;*.jpeg;*.png;*.webp;*.pdf)", "All files (*.*)"))
        added = []
        for name in picked or ():
            p = Path(name)
            try:
                if p.stat().st_size > docs.MAX_FILE:
                    raise ValueError(f"That file is over {docs.MAX_FILE // (1024 * 1024)} MB.")
                added.append(docs.seal(p.read_bytes(), p.name))
            except (OSError, ValueError) as exc:
                return {"ok": bool(added), "files": added, "error": f"{p.name}: {exc}"}
        return {"ok": bool(added), "files": added}

    def doc_read(self, refs) -> dict:
        """Read a document's details from all its files together (an ID card's
        front and back), on this PC, offline."""
        self._need()
        texts, error = [], ""
        for ref in refs if isinstance(refs, list) else [refs]:
            try:
                texts.append(docs.ocr(docs.open_sealed(ref)))
            except (ValueError, RuntimeError) as exc:
                error = str(exc)          # read what we can; say why one failed
        if not texts:
            return {"ok": False, "error": error or "Add a photo or PDF of the document first."}
        return {"ok": True, "found": docs.read_details(texts)}

    def doc_preview(self, ref: dict) -> dict:
        """The file as an image the page can show (a PDF's first page)."""
        self._need()
        try:
            data = docs.open_sealed(ref)
            if docs.sniff_mime(data) == "application/pdf":
                data, mime = docs.preview_png(data), "image/png"
            else:
                mime = docs.sniff_mime(data)
        except (ValueError, RuntimeError) as exc:
            return {"ok": False, "error": str(exc)}
        return {"ok": True, "src": f"data:{mime};base64," + base64.b64encode(data).decode()}

    def doc_save_copy(self, ref: dict) -> dict:
        """Save the file, decrypted, wherever you choose."""
        self._need()
        try:
            data = docs.open_sealed(ref)
        except ValueError as exc:
            return {"ok": False, "error": str(exc)}
        picked = self._window.create_file_dialog(webview.SAVE_DIALOG, save_filename=str(ref.get("name") or "document"))
        if not picked:
            return {"ok": False}
        target = Path(picked if isinstance(picked, str) else picked[0])
        target.write_bytes(data)
        return {"ok": True, "path": str(target)}

    def doc_export(self, refs, fmt: str, name: str = "") -> dict:
        """Save files, decrypted, as one PDF or Word document (all of them, like a
        photocopy) or as PNG/JPEG (the first), wherever you choose."""
        self._need()
        if fmt not in export.FORMATS:
            return {"ok": False, "error": "Unknown format."}
        refs = refs if isinstance(refs, list) else [refs]
        try:
            out = export.export([docs.open_sealed(r) for r in refs], fmt)
        except (ValueError, RuntimeError) as exc:
            return {"ok": False, "error": str(exc)}
        ext, _ = export.FORMATS[fmt]
        base = Path(str(name or (refs[0].get("name") if refs else "") or "document")).stem[:80] or "document"
        picked = self._window.create_file_dialog(webview.SAVE_DIALOG, save_filename=f"{base}.{ext}")
        if not picked:
            return {"ok": False}
        target = Path(picked if isinstance(picked, str) else picked[0])
        target.write_bytes(out)
        return {"ok": True, "path": str(target)}

    def doc_settings(self) -> dict:
        cfg = config.load()
        return {"sync_files": cfg.get("sync_files", True), "presets": list(docs.REMIND_PRESETS)}

    def set_doc_sync(self, on: bool) -> dict:
        cfg = config.load()
        cfg["sync_files"] = bool(on)
        config.save(cfg)
        return self.doc_settings()

    def doc_test_notification(self) -> dict:
        """Show a sample reminder, so you can check Windows lets MyVault notify you."""
        if self._tell is None:
            return {"ok": False, "error": "Notifications come from the installed MyVault while it runs by the clock."}
        self._tell("MyVault", i18n.tr("This is how a document reminder looks."))
        return {"ok": True}

    def _documents_changed(self) -> None:
        try:
            if self._vault is not None:
                docs.save_schedule(self._vault.entries)
        except OSError:
            return
        # A document due today (or overdue) is announced now, not at the next check.
        threading.Thread(target=self._safe_check, daemon=True).start()

    def _safe_check(self) -> None:
        try:
            with self._reminder_lock:
                self._check_reminders()
        except Exception:
            pass

    def _reminder_loop(self) -> None:
        """Every 5 minutes (soon after start, and right after each save): notify about documents that are
        due. Works while locked, from the schedule file (type + your label only)."""
        time.sleep(20)
        while True:
            self._safe_check()      # (it never lets a bad file stop reminders for good)
            time.sleep(300)

    def _check_reminders(self) -> None:
        import datetime as dt
        plan = docs.load_schedule()
        cfg = config.load()
        shown = set(cfg.get("reminders_shown", []))
        if self._tell is None:
            return
        for r in docs.due(plan, dt.date.today(), shown):
            self._tell("MyVault", docs.reminder_text(r, i18n.tr))
            shown.add(r["key"])
        keys = {r["key"] for r in plan}
        cfg["reminders_shown"] = sorted(shown & keys)          # forget reminders that no longer exist
        config.save(cfg)

    # ---- clipboard / generator --------------------------------------------
    def copy(self, text: str) -> dict:
        self._need()
        ok = clipboard.copy_secret(str(text), CLIPBOARD_CLEAR_SECONDS)
        return {"ok": ok, "clears_in": CLIPBOARD_CLEAR_SECONDS}

    def generate(self, policy: dict | None = None) -> dict:
        try:
            pw = generate(PasswordPolicy.from_dict(policy))
        except (ValueError, TypeError) as exc:
            return {"ok": False, "error": str(exc)}
        return {"ok": True, "password": pw, "strength": strength_label(pw)}

    def strength(self, password: str) -> str:
        return strength_label(str(password))

    # ---- settings ----------------------------------------------------------
    def change_master(self, current: str, new: str) -> dict:
        v = self._need()
        if current != v._password:
            return {"ok": False, "error": "The current master password is wrong."}
        if len(new) < 8:
            return {"ok": False, "error": "Use at least 8 characters."}
        with self._lock:
            v.change_password(new)
        return {"ok": True}

    def vault_info(self) -> dict:
        return {"path": str(paths.vault_path())}

    def connector_info(self) -> dict:
        cfg = config.load()
        return {"running": bool(self._connector and self._connector.running),
                "port": cfg["port"], "token": cfg["token"], "extension_dir": str(EXTENSION_DIR)}

    def regen_token(self) -> dict:
        config.regenerate_token()
        self._stop_connector()
        if self._vault is not None:
            self._start_connector()
        return self.connector_info()

    # ---- auto-type into other programs --------------------------------------
    def autotype_target(self) -> dict:
        """Name the program MyVault would type into (the window right behind it)."""
        self._need()
        if not autotype.available():
            return {"ok": False, "error": "Auto-type works on Windows only."}
        t = autotype.target_window()
        if not t:
            return {"ok": False, "error": "Click into the other program's login box first, then come back here."}
        self._autotype_hwnd = t[0]
        return {"ok": True, "title": t[1]}

    def autotype(self, entry_id: str, mode: str = "both") -> dict:
        v = self._need()
        e = v.get(entry_id)
        if e is None or e.deleted or e.kind != "login":
            return {"ok": False, "error": "That entry isn't there any more."}
        hwnd, self._autotype_hwnd = self._autotype_hwnd, 0
        if not hwnd:
            return {"ok": False, "error": "Choose Type into app again."}
        login = e.username or e.email
        parts = [e.password] if mode == "password" or not login else [login, e.password]
        err = autotype.type_into(hwnd, parts, self._window.minimize)
        return {"ok": not err, "error": err}

    def autostart_state(self) -> dict:
        return {"available": autostart.available(), "enabled": autostart.enabled()}

    def set_autostart(self, on: bool) -> dict:
        if not autostart.available():
            return {"available": False, "enabled": False}
        autostart.set_enabled(bool(on))
        return self.autostart_state()

    def folders(self) -> dict:
        return {"data": str(paths.data_dir()), "app": str(app_dir()), "extension": str(EXTENSION_DIR)}

    def open_doc(self, name: str) -> dict:
        """Open one of MyVault's published documents in the browser (fixed list, never a free URL)."""
        if name not in ("PRIVACY.md", "TERMS.md", "SECURITY.md", "CHANGELOG.md"):
            return {"ok": False}
        webbrowser.open(f"https://github.com/{update.REPO}/blob/main/{name}")
        return {"ok": True}

    def open_folder(self, which: str) -> dict:
        """Open one of MyVault's own folders in Explorer (paths found at runtime,
        so they're right on any machine). Nothing outside these."""
        target = {"data": paths.data_dir(), "app": app_dir(), "extension": EXTENSION_DIR,
                  "backups": _backups_dir()}.get(which)
        if target is None or not target.is_dir():
            return {"ok": False, "error": "That folder isn't there."}
        vault = paths.vault_path()
        if which == "data" and vault.exists() and os.name == "nt":
            subprocess.Popen(["explorer", f"/select,{vault}"])   # highlights vault.dat
        elif os.name == "nt":
            os.startfile(target)
        else:
            subprocess.Popen(["xdg-open" if sys.platform != "darwin" else "open", str(target)])
        return {"ok": True, "path": str(target)}

    def copy_plain(self, text: str) -> dict:
        """Non-secret copy (token, folder path): no auto-clear."""
        return {"ok": clipboard.copy_secret(str(text), clear_after=0)}

    # ---- QR sync -----------------------------------------------------------
    def sync_start(self, only=None) -> dict:
        """Show a sync code. With [only] (entry ids), just those take part."""
        self._need()
        self.sync_cancel()
        try:
            self._pairing = sync.PairingSession(_SyncProvider(self, only if isinstance(only, list) else None))
        except OSError as exc:
            return {"ok": False, "error": f"Couldn't open the sync port: {exc}"}
        qr = segno.make(self._pairing.uri, error="m")
        # Pure black on white with the full 4-module quiet zone: easiest for phone cameras.
        svg = qr.svg_inline(scale=8, border=4, dark="#000000", light="#FFFFFF", omitsize=True)  # viewBox, so CSS scales it instead of cropping
        hosts = sync.parse_uri(self._pairing.uri)[0]
        return {"ok": True, "svg": svg, "uri": self._pairing.uri, "ttl": sync.PAIRING_TTL,
                "hosts": hosts, "public": _network_is_public(hosts[0])}

    def sync_status(self) -> dict:
        s = self._pairing
        if s is None:
            return {"state": "idle"}
        r = s.result
        out = {"state": s.state, "seconds_left": max(0, int(s.expires_at - time.time())),
               "changed": r.added_or_updated if r else 0,
               "rejected": s.failed_attempts, "error": s.last_error, "version": __version__}
        if r:
            out.update(peer_version=r.peer_version, received=r.received, sent=r.sent,
                       update_error=r.update_error, files_received=r.files_received, files_error=r.files_error)
        return out

    def sync_cancel(self) -> dict:
        if self._pairing is not None:
            self._pairing.cancel()
            self._pairing = None
        return {"ok": True}

    # ---- updates ------------------------------------------------------------
    def update_state(self) -> dict:
        cfg = config.load()
        ready = update.ready_installer()
        return {"current": __version__, "ask": cfg.get("update_check") is None and not STORE, "store": STORE,
                "enabled": bool(cfg.get("update_check")), "ready": ready.version if ready else "",
                "last_check": cfg.get("last_update_check", 0), **self._upd}

    def set_update_check(self, on: bool) -> dict:
        cfg = config.load()
        cfg["update_check"] = bool(on)
        config.save(cfg)
        if on:
            self.check_updates(force=True)
        return self.update_state()

    def check_updates(self, force: bool = False) -> dict:
        """Online check, in the background: only if the user said yes, and at
        most once a day unless they press "Check now"."""
        cfg = config.load()
        if STORE or not cfg.get("update_check") or self._upd["checking"]:
            return self.update_state()
        if not force and time.time() - cfg.get("last_update_check", 0) < 24 * 3600:
            return self.update_state()

        def work():
            self._upd.update(checking=True, error="")
            try:
                m, raw, sig = update.check_online()
                c = config.load()
                c["last_update_check"] = time.time()
                config.save(c)
                if update.newer(m["version"], __version__):
                    self._upd_release = (m, raw, sig)
                    self._upd.update(available=m["version"], notes=str(m.get("notes", ""))[:500])
                else:
                    self._upd.update(available="", notes="")
            except Exception as exc:   # offline, GitHub down, no release yet...
                self._upd["error"] = _friendly_update_error(exc)
            finally:
                self._upd["checking"] = False
                self._js("MV.updates()")
        threading.Thread(target=work, daemon=True).start()
        return self.update_state()

    def update_now(self) -> dict:
        """Download (if needed), verify, and run the newer installer."""
        if self._upd["busy"]:
            return self.update_state()

        def work():
            self._upd.update(busy=True, error="", progress=0)
            try:
                if not update.ready_installer() and self._upd_release:
                    m, raw, sig = self._upd_release
                    update.download(m, raw, sig, update.PLATFORM,
                                    progress=lambda got, total: self._upd.update(progress=int(got * 100 / total)))
                    if "android" in m.get("files", {}):   # so this PC can hand it to your phone
                        try:
                            update.download(m, raw, sig, "android")
                        except Exception:
                            pass
                self.install_update()
            except Exception as exc:
                self._upd["error"] = _friendly_update_error(exc)
            finally:
                self._upd["busy"] = False
                self._js("MV.updates()")
        threading.Thread(target=work, daemon=True).start()
        return self.update_state()

    def install_update(self) -> dict:
        pkg = update.ready_installer()
        if pkg is None:
            return {"ok": False, "error": "No verified update is waiting."}
        return self._run_installer(pkg)

    # ---- going back to the previous release ----------------------------------
    def rollback_info(self) -> dict:
        if STORE:
            return {"ok": False, "error": "Updates come from the Microsoft Store."}
        try:
            self._rollback = update.previous_release()
        except update.UpdateError as exc:
            return {"ok": False, "error": str(exc)}
        except (OSError, ValueError):
            return {"ok": False, "error": "Couldn't reach GitHub. Check your internet connection and try again."}
        return {"ok": True, "version": self._rollback[0]["version"], "current": __version__,
                "backup": f"vault-before-rollback-{__version__}.dat"}

    def rollback(self) -> dict:
        """Copy the vault, then download, verify and run the earlier installer."""
        if self._rollback is None:
            return {"ok": False, "error": "Look for the previous version first."}
        m, raw, sig = self._rollback
        try:
            pkg = update.download(m, raw, sig, update.PLATFORM)     # signature + fingerprint checked
        except update.UpdateError as exc:
            return {"ok": False, "error": str(exc)}
        except OSError:
            return {"ok": False, "error": "The download failed. Check your internet connection and try again."}
        vault = paths.vault_path()
        if vault.exists():
            shutil.copy2(vault, paths.data_dir() / f"vault-before-rollback-{__version__}.dat")
        return self._run_installer(pkg)

    def _run_installer(self, pkg) -> dict:
        # The installer replaces the program files, keeps the vault, and
        # starts MyVault again when it's done.
        subprocess.Popen([str(pkg.path), "/SILENT", "/SUPPRESSMSGBOXES", "/NORESTART"],
                         creationflags=getattr(subprocess, "DETACHED_PROCESS", 0))
        self.lock()
        if self._quit is not None:
            self._quit()             # the tray's Quit: the X would only hide MyVault, leaving its files in use
        elif self._window is not None:
            self._window.destroy()
        return {"ok": True}

    # ---- automatic backups: a copy of the (encrypted) vault file a day -------
    def _saved(self) -> None:
        try:
            _daily_backup()
        except OSError:
            pass       # a full or read-only disk mustn't stop the vault itself
        self._documents_changed()

    def backups(self) -> dict:
        self._need()
        d = _backups_dir()
        files = sorted(d.glob("vault-*.dat"), reverse=True) if d.exists() else []
        return {"folder": str(d), "keep": BACKUP_DAYS,
                "list": [{"name": f.name, "date": f.stem[6:], "size": f.stat().st_size} for f in files]}

    def backup_restore(self, name: str, password: str) -> dict:
        """Bring back what a daily backup has: deleted entries return, and a
        backup copy newer than yours replaces it; nothing newer is lost."""
        v = self._need()
        path = _backups_dir() / Path(str(name)).name           # only a file in the backups folder
        if not path.is_file():
            return {"ok": False, "error": "That backup isn't there any more."}
        try:
            old = Vault.open(path, password)
        except crypto.WrongPasswordError:
            return {"ok": False, "error": "That isn't the master password this backup was saved with."}
        except crypto.VaultFormatError as exc:
            return {"ok": False, "error": str(exc)}
        with self._lock:
            merged, counts = sync.restore_entries(
                [e.to_dict() for e in v.entries], [e.to_dict() for e in old.active_entries()], time.time())
            v.entries = [Entry.from_dict(d) for d in merged]
            v.save()
        self._js("MV.refresh()")
        return {"ok": True, **counts}

    # ---- password health, 2FA codes, importing -----------------------------
    def health(self) -> dict:
        v = self._need()
        with self._lock:
            return health.report(v.entries)

    def leak_check(self) -> dict:
        """Only when asked: see health.py for what is sent (5 characters of a hash)."""
        v = self._need()
        with self._lock:
            logins = [(e.id, e.password) for e in v.active_entries() if e.kind == "login" and e.password]
        try:
            found = health.leaks(pw for _, pw in logins)
        except OSError:
            return {"ok": False, "error": "Couldn't reach the leak check service. Check your internet connection."}
        return {"ok": True, "checked": len(logins),
                "leaked": {i: found[pw] for i, pw in logins if found[pw]}}

    def totp_code(self, entry_id: str) -> dict:
        v = self._need()
        e = v.get(entry_id)
        try:
            c, left = otp.code((e.fields.get("totp") or "") if e else "")
        except ValueError as exc:
            return {"ok": False, "error": str(exc)}
        return {"ok": True, "code": c, "left": left}

    def totp_check(self, text: str) -> dict:
        try:
            s = otp.parse(text)
        except ValueError as exc:
            return {"ok": False, "error": str(exc)}
        return {"ok": True, "issuer": s["issuer"], "account": s["account"]}

    def import_csv(self, commit: bool = False) -> dict:
        """Pick a CSV export; first call counts what's new, the second (commit) adds it."""
        v = self._need()
        if not commit or not self._import_path:
            picked = self._window.create_file_dialog(webview.OPEN_DIALOG, file_types=("CSV (*.csv)",))
            if not picked:
                return {"ok": False}
            self._import_path = Path(picked[0])
        try:
            text = self._import_path.read_bytes().decode("utf-8-sig", "replace")
            with self._lock:
                new, skipped = importer.read_csv(text, v.entries)
                if commit:
                    v.entries.extend(new)
                    v.save()
        except (OSError, ValueError, csv.Error) as exc:
            return {"ok": False, "error": str(exc)}
        if commit:
            self._import_path = None
            self._js("MV.refresh()")
        return {"ok": True, "new": len(new), "skipped": skipped, "file": self._import_path.name if not commit else ""}

    # ---- paper backup ------------------------------------------------------
    def backup_export(self, password: str) -> dict:
        v = self._need()
        if len(password) < 8:
            return {"ok": False, "error": "Use at least 8 characters for the backup password."}
        picked = self._window.create_file_dialog(
            webview.SAVE_DIALOG, save_filename=f"MyVault backup {time.strftime('%Y-%m-%d')}.pdf",
            file_types=("PDF (*.pdf)",))
        if not picked:
            return {"ok": False}
        target = Path(picked if isinstance(picked, str) else picked[0])
        with self._lock:
            entries = [e.to_dict() for e in v.active_entries()]
        target.write_bytes(paper.build_pdf(entries, password))
        return {"ok": True, "path": str(target), "count": len(entries)}

    def backup_import(self, password: str) -> dict:
        v = self._need()
        picked = self._window.create_file_dialog(webview.OPEN_DIALOG, file_types=("PDF (*.pdf)",))
        if not picked:
            return {"ok": False}
        try:
            got, bad = paper.read_pdf(Path(picked[0]).read_bytes(), password)
        except paper.BackupError as exc:
            return {"ok": False, "error": str(exc)}
        with self._lock:
            merged, counts = sync.restore_entries(
                [e.to_dict() for e in v.entries], [Entry.from_dict(d).to_dict() for d in got], time.time())
            v.entries = [Entry.from_dict(d) for d in merged]
            v.save()
        self._js("MV.refresh()")
        return {"ok": True, "found": len(got), "unreadable": bad, **counts}

    # ---- browser connector -------------------------------------------------
    def _start_connector(self) -> None:
        cfg = config.load()
        if not cfg.get("enabled", True):
            return
        try:
            self._connector = server.Connector(_ConnectorProvider(self), cfg["token"], int(cfg["port"]))
            self._connector.start()
        except OSError:
            self._connector = None   # port busy: auto-fill unavailable, app still works

    def _stop_connector(self) -> None:
        if self._connector is not None:
            self._connector.stop()
            self._connector = None

    def _shutdown(self) -> None:
        self.lock()


class _SyncProvider:
    """What sync.py needs (runs on the pairing thread). With [only], just those
    of this PC's entries take part; new entries from the phone still arrive.
    Entries kept on this PC (local_only) never take part."""

    def __init__(self, api: Api, only=None):
        self.api = api
        self.only = None if only is None else {str(i) for i in only}

    def _held(self, e: Entry) -> bool:
        return e.local_only or (self.only is not None and e.id not in self.only)

    def vault_identity(self) -> tuple[str, str]:
        v = self.api._need()
        if not v.vault_id:                       # its first sync: the phone will adopt this
            with self.api._lock:
                v.vault_id = uuid.uuid4().hex
                v.save()
        name = next((x["name"] for x in paths.vaults() if x["id"] == paths.current()), "My vault")
        return v.vault_id, name

    def adopt_vault_id(self, vid: str) -> None:
        v = self.api._need()
        with self.api._lock:
            v.vault_id = vid

    # -- version + update hand-over --
    def app_version(self) -> str:
        return __version__

    def platform(self) -> str:
        return update.PLATFORM

    def offers(self) -> dict:
        return update.offers()

    def package_for(self, platform: str):
        return update.packages().get(platform)

    def receive_package(self, platform: str, manifest: bytes, sig: str, tmp) -> str:
        if STORE or platform != update.PLATFORM:
            raise update.UpdateError("Not a package for this PC.")
        pkg = update.store(manifest, sig, platform, tmp)
        self.api._js("MV.updates()")
        return pkg.version

    def device_id(self) -> str:
        return self.api._vault.device_id if self.api._vault else ""

    def get_entries(self) -> list[dict]:
        with self.api._lock:
            return [e.to_dict() for e in self.api._need().entries if not self._held(e)]

    # -- document files --
    def file_sync(self) -> bool:
        return bool(config.load().get("sync_files", True))

    def file_refs(self) -> dict:
        v = self.api._need()
        return {r["id"]: r for e in v.active_entries() for r in docs.refs(e.fields)}

    def has_file(self, file_id: str) -> bool:
        return docs.have(file_id)

    def read_file(self, file_id: str) -> bytes:
        return docs.read_blob(file_id)

    def store_file(self, file_id: str, blob: bytes) -> None:
        docs.store_blob(self.file_refs()[file_id], blob)

    def apply_merged(self, merged: list[dict]) -> int:
        with self.api._lock:
            v = self.api._need()
            by_id = {e.id: e for e in v.entries}
            changed = 0
            for d in merged:
                cur = by_id.get(d["id"])
                if cur is not None and self._held(cur):
                    continue                     # kept as it is on this PC
                if cur is None or float(d.get("updated_at", 0)) > cur.updated_at:
                    by_id[d["id"]] = Entry.from_dict(d)
                    changed += 1
            v.entries = list(by_id.values())
            v.save()
        self.api._js("MV.refresh()")
        return changed


class _ConnectorProvider:
    """What server.py needs (runs on the connector thread)."""

    def __init__(self, api: Api):
        self.api = api

    def is_unlocked(self) -> bool:
        return self.api._vault is not None

    def match(self, domain: str) -> list[dict]:
        v = self.api._vault
        if v is None:
            return []
        return [{"id": e.id, "title": e.display_name(), "username": e.username,
                 "email": e.email, "password": e.password}
                for e in v.active_entries()
                if e.kind == "login"
                and any(webmatch.hosts_match(domain, h) for h in webmatch.entry_hosts(e))]

    def save(self, cred: dict) -> dict:
        v = self.api._vault
        if v is None:
            return {"ok": False, "error": "locked"}
        domain = webmatch.normalize_host(cred.get("domain") or cred.get("url") or "")
        login = (cred.get("username") or cred.get("email") or "").strip()
        password = cred.get("password") or ""
        if not password:
            return {"ok": False, "error": "no password"}
        profile = ("username", "email", "phone", "region", "age", "gender")

        with self.api._lock:
            target = None
            for e in v.active_entries():
                if e.kind != "login":
                    continue
                same_site = any(webmatch.hosts_match(domain, h) for h in webmatch.entry_hosts(e))
                if same_site and (not login or login in (e.username, e.email)):
                    target = e
                    break
            if target is None:
                entry = Entry(title=domain or login, website=domain, password=password,
                              **{f: str(cred.get(f) or "") for f in profile})
                _apply_extra(entry, cred)
                v.add(entry)
                action, entry_id = "created", entry.id
            elif target.password != password or _has_new_details(target, cred, profile):
                old, target.password = target.password, password
                keep_old_password(target, old)
                for f in profile:
                    if cred.get(f) and not getattr(target, f):
                        setattr(target, f, str(cred[f]))
                _apply_extra(target, cred)
                v.update(target)
                action, entry_id = "updated", target.id
            else:
                action, entry_id = "unchanged", target.id
        self.api._js("MV.refresh()")
        return {"ok": True, "action": action, "id": entry_id}

    def generate(self, policy: dict | None) -> str:
        try:
            return generate(PasswordPolicy.from_dict(policy))
        except (ValueError, TypeError):
            return generate(PasswordPolicy())


BACKUP_DAYS = 14


def _backups_dir() -> Path:
    return paths.vault_path().parent / "backups"


def _daily_backup() -> None:
    """The vault file as it was when first opened or saved each day, for the
    last BACKUP_DAYS days. It's the encrypted file itself: nothing is readable."""
    src, d = paths.vault_path(), _backups_dir()
    target = d / f"vault-{time.strftime('%Y-%m-%d')}.dat"
    if target.exists() or not src.exists():
        return
    d.mkdir(exist_ok=True)
    shutil.copy2(src, target)
    for old in sorted(d.glob("vault-*.dat"))[:-BACKUP_DAYS]:
        old.unlink()


def _last_vault() -> str:
    """The vault opened last (the lock screen offers it first)."""
    last = config.load().get("last_vault")
    return last if any(v["id"] == last for v in paths.vaults()) else paths.DEFAULT


def _autolock_minutes() -> int:
    m = config.load().get("autolock_minutes", 5)
    return m if m in AUTO_LOCK_CHOICES else 5


def _friendly_update_error(exc: Exception) -> str:
    import urllib.error
    if isinstance(exc, urllib.error.HTTPError) and exc.code == 404:
        return "No release has been published yet."
    if isinstance(exc, (urllib.error.URLError, OSError, TimeoutError)):
        return "Couldn't reach GitHub. Check your internet connection."
    return str(exc)


def _network_is_public(ip: str) -> bool:
    """True when Windows files this WiFi as a Public network. Its firewall then
    drops the phone's sync connection without telling anyone, so the UI warns."""
    if os.name != "nt":
        return False
    try:
        out = subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             f"(Get-NetIPAddress -IPAddress '{ipaddress.ip_address(ip)}' -ErrorAction SilentlyContinue"
             " | Get-NetConnectionProfile).NetworkCategory"],
            capture_output=True, text=True, timeout=6, creationflags=subprocess.CREATE_NO_WINDOW)
        return out.stdout.strip() == "Public"
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return False


def _apply_extra(entry: Entry, cred: dict) -> None:
    """Merge extra captured sign-up details into custom fields, never clobbering."""
    for key, value in (cred.get("extra") or {}).items():
        if value and key and str(key) not in entry.custom:
            entry.custom[str(key)[:80]] = str(value)[:500]


def _has_new_details(target: Entry, cred: dict, profile) -> bool:
    if any(cred.get(f) and not getattr(target, f) for f in profile):
        return True
    return any(v and k not in target.custom for k, v in (cred.get("extra") or {}).items())


def _page() -> str:
    html = (UI_DIR / "index.html").read_text("utf-8")
    css = (UI_DIR / "app.css").read_text("utf-8")
    js = (UI_DIR / "app.js").read_text("utf-8")
    lang = i18n.language()
    html = html.replace('<html lang="en">', f'<html lang="{lang}" dir="{"rtl" if lang == "ar" else "ltr"}">')
    words = json.dumps(i18n.arabic() if lang == "ar" else {}, ensure_ascii=False).replace("</", "<\\/")
    types = (UI_DIR / "doc_types.json").read_text("utf-8").replace("</", "<\\/")
    countries = json.dumps(docs.countries(), ensure_ascii=False).replace("</", "<\\/")
    return html.replace("/*__CSS__*/", css).replace(
        "//__JS__", f"window.I18N = {words};\nwindow.DOC_SCHEMA = {types};\nwindow.COUNTRIES = {countries};\n{js}")


_mutex = None


def _guard_window(window) -> None:
    """Only MyVault's own page may load in its window. pywebview gives every page
    that loads there the vault's API, so a link or a file dropped onto the window
    (or any other way out) must never open: those navigations are cancelled."""
    try:
        from System import Action      # pythonnet: WebView2 lives on the window's UI thread
    except ImportError:
        return
    def ours(uri: str) -> bool:
        return uri.startswith("data:") or uri == "about:blank"     # load_html() pages
    def setup():
        view = window.native.browser.webview
        try:
            view.AllowExternalDrop = False
        except Exception:
            pass            # an older WebView2: the guard below still stops a drop
        def starting(_sender, args):
            if not ours(str(args.Uri)):
                args.Cancel = True
        view.CoreWebView2.NavigationStarting += starting
    try:
        window.native.Invoke(Action(setup))
    except Exception:
        pass                # not WebView2 (another platform): nothing to guard here


def _focus_running_copy() -> bool:
    """One MyVault at a time (two would fight over the connector port). If one
    is already open, bring its window forward and return True."""
    global _mutex
    if os.name != "nt":
        return False
    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    _mutex = k32.CreateMutexW(None, False, r"Local\MyVault.SingleInstance")
    if ctypes.get_last_error() != 183:          # ERROR_ALREADY_EXISTS
        return False
    u32 = ctypes.windll.user32
    found = []
    proc = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)

    def visit(hwnd, _):
        title, cls = ctypes.create_unicode_buffer(64), ctypes.create_unicode_buffer(64)
        u32.GetWindowTextW(hwnd, title, 64)
        u32.GetClassNameW(hwnd, cls, 64)
        if title.value == "MyVault" and cls.value.startswith("WindowsForms"):
            found.append(hwnd)
        return True
    u32.EnumWindows(proc(visit), 0)
    for hwnd in found:
        u32.ShowWindow(hwnd, 9)                 # SW_RESTORE
        u32.SetForegroundWindow(hwnd)
    return True


def _run_in_tray(window, api: Api) -> None:
    """Windows: the X button hides MyVault to the notification area instead of
    quitting, so the browser extension keeps working with no taskbar button.
    "Quit MyVault" in the tray menu really exits; so does signing out or shutting down."""
    from System.Windows.Forms import CloseReason, FormWindowState
    from webview.platforms.winforms import BrowserView

    from . import tray

    form = BrowserView.instances[window.uid]
    state = {"quitting": False, "told": False}

    def lock():
        api.lock()
        api._js("MV.onLocked('Locked from the tray.')")

    def quit_():
        state["quitting"] = True
        icon.remove()
        window.destroy()

    icon = tray.Tray(str(ICON), window.show, lock, quit_)
    api._quit = quit_
    api._tell = icon.tell

    def closing(sender, args):
        if args.CloseReason != CloseReason.UserClosing or state["quitting"]:
            return
        args.Cancel = True
        if sender.WindowState == FormWindowState.Minimized:
            sender.WindowState = FormWindowState.Normal   # so "Open" brings it back full size
        sender.Hide()
        if not state["told"]:
            state["told"] = True
            icon.tell(i18n.tr("MyVault is still running"),
                      i18n.tr("It's by the clock, so browser fill keeps working. Right-click the icon to lock or quit."))

    form.FormClosing += closing
    window.events.closed += icon.remove


def run() -> None:
    if _focus_running_copy():
        return
    tray_ok = os.name == "nt" and ICON.exists()
    if os.name == "nt":   # own taskbar identity and icon, not Python's
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(APP_ID)
    api = Api()
    background = "--minimized" in sys.argv     # started at sign-in: wait in the tray (or taskbar), locked
    window = webview.create_window(
        "MyVault", html=_page(), js_api=api, width=1100, height=720,
        min_size=(820, 560), background_color="#F4F5F7", text_select=True,
        hidden=background and tray_ok, minimized=background and not tray_ok)
    api._window = window
    guarded = []
    def guard_once():
        if not guarded:
            guarded.append(True)
            _guard_window(window)
    window.events.loaded += guard_once
    if tray_ok:
        def start_tray():
            try:
                _run_in_tray(window, api)
            except Exception:
                window.show()      # no tray: never leave MyVault invisible
        window.events.before_show += start_tray
    window.events.closed += api._shutdown
    webview.start(private_mode=True, icon=str(ICON) if ICON.exists() else None)
