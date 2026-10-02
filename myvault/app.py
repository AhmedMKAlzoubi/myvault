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

import ctypes
import ipaddress
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

import segno
import webview

from . import __version__, autostart, clipboard, config, crypto, paper, paths, server, sync, update, webmatch
from .generator import PasswordPolicy, generate, strength_label
from .vault import KINDS, Entry, Vault

AUTO_LOCK_MINUTES = 5
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
        sub = (e.notes or "").split("\n", 1)[0][:60]
    return {"id": e.id, "kind": e.kind, "title": e.display_name(), "subtitle": sub,
            "website": e.website, "updated_at": e.updated_at}


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
            if self._vault is not None and time.time() - self._last_activity > AUTO_LOCK_MINUTES * 60:
                self.lock()
                self._js("MV.onLocked('Locked after 5 minutes of inactivity.')")

    # ---- unlock / lock -----------------------------------------------------
    def boot(self) -> dict:
        return {"exists": paths.vault_path().exists(), "unlocked": self._vault is not None,
                "version": __version__, "autolock": AUTO_LOCK_MINUTES}

    def unlock(self, password: str) -> dict:
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
        self._start_connector()
        self.check_updates()
        return {"ok": True}

    def lock(self) -> dict:
        with self._lock:
            self._vault = None
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
            e = v.get(str(data.get("id", ""))) if data.get("id") else None
            is_new = e is None or e.deleted
            if is_new:
                e = Entry(kind=kind)
            e.kind = kind
            for key in TEXT_FIELDS:
                if key in data:
                    setattr(e, key, str(data[key] or "") if key in ("password", "notes")
                            else str(data[key] or "").strip())
            e.custom = _str_map(data.get("custom"))
            e.fields = _str_map(data.get("fields"))
            if isinstance(data.get("password_policy"), dict):
                e.password_policy = PasswordPolicy.from_dict(data["password_policy"]).to_dict()
            if e.display_name() == "(untitled)":
                return {"ok": False, "error": "Give it a name first."}
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

    def autostart_state(self) -> dict:
        return {"available": autostart.available(), "enabled": autostart.enabled()}

    def set_autostart(self, on: bool) -> dict:
        if not autostart.available():
            return {"available": False, "enabled": False}
        autostart.set_enabled(bool(on))
        return self.autostart_state()

    def folders(self) -> dict:
        return {"data": str(paths.data_dir()), "app": str(app_dir()), "extension": str(EXTENSION_DIR)}

    def open_folder(self, which: str) -> dict:
        """Open one of MyVault's own folders in Explorer (paths found at runtime,
        so they're right on any machine). Nothing outside these three."""
        target = {"data": paths.data_dir(), "app": app_dir(), "extension": EXTENSION_DIR}.get(which)
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
    def sync_start(self) -> dict:
        self._need()
        self.sync_cancel()
        try:
            self._pairing = sync.PairingSession(_SyncProvider(self))
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
                       update_error=r.update_error)
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
        return {"current": __version__, "ask": cfg.get("update_check") is None,
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
        if not cfg.get("update_check") or self._upd["checking"]:
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
        # The installer replaces the program files, keeps the vault, and
        # starts MyVault again when it's done.
        subprocess.Popen([str(pkg.path), "/SILENT", "/SUPPRESSMSGBOXES", "/NORESTART"],
                         creationflags=getattr(subprocess, "DETACHED_PROCESS", 0))
        self.lock()
        if self._window is not None:
            self._window.destroy()
        return {"ok": True}

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
    """What sync.py needs (runs on the pairing thread)."""

    def __init__(self, api: Api):
        self.api = api

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
        if platform != update.PLATFORM:
            raise update.UpdateError("Not a package for this PC.")
        pkg = update.store(manifest, sig, platform, tmp)
        self.api._js("MV.updates()")
        return pkg.version

    def device_id(self) -> str:
        return self.api._vault.device_id if self.api._vault else ""

    def get_entries(self) -> list[dict]:
        with self.api._lock:
            return [e.to_dict() for e in self.api._need().entries]

    def apply_merged(self, merged: list[dict]) -> int:
        with self.api._lock:
            v = self.api._need()
            before = {e.id: e.updated_at for e in v.entries}
            v.entries = [Entry.from_dict(d) for d in merged]
            v.save()
            changed = sum(1 for e in v.entries
                          if before.get(e.id) is None or e.updated_at > before[e.id])
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
                target.password = password
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
    return html.replace("/*__CSS__*/", css).replace("//__JS__", js)


_mutex = None


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


def run() -> None:
    if _focus_running_copy():
        return
    if os.name == "nt":   # own taskbar identity and icon, not Python's
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(APP_ID)
    api = Api()
    window = webview.create_window(
        "MyVault", html=_page(), js_api=api, width=1100, height=720,
        min_size=(820, 560), background_color="#F4F5F7", text_select=True,
        minimized="--minimized" in sys.argv)   # started at sign-in: wait in the taskbar, locked
    api._window = window
    window.events.closed += api._shutdown
    webview.start(private_mode=True, icon=str(ICON) if ICON.exists() else None)
