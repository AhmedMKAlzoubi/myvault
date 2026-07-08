"""
The MyVault desktop window (Tkinter).

Design goals: black-and-white, plain, low memory, keyboard-friendly.
The vault itself never touches the network. The optional browser connector
(see server.py) listens only on 127.0.0.1 and only while the app is unlocked.
"""

from __future__ import annotations

import threading
import time
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog
from pathlib import Path

from . import crypto, paths, config, server, webmatch, sync
from .vault import Vault, Entry
from .generator import PasswordPolicy, generate, strength_label

# ---- black & white palette ----------------------------------------------
BG = "#ffffff"
FG = "#111111"
MUTED = "#666666"
LINE = "#cccccc"
SEL_BG = "#111111"
SEL_FG = "#ffffff"
FONT = ("Segoe UI", 10)
FONT_BOLD = ("Segoe UI", 10, "bold")
FONT_TITLE = ("Segoe UI", 15, "bold")
FONT_MONO = ("Consolas", 10)

CLIPBOARD_CLEAR_SECONDS = 30
AUTO_LOCK_MINUTES = 5

# The ordered, labelled standard fields shown in the form.
STANDARD_FIELDS = [
    ("title", "Title / name"),
    ("website", "Website"),
    ("app", "App name"),
    ("username", "Username"),
    ("email", "Email"),
    ("region", "Region / country"),
    ("age", "Age"),
    ("gender", "Gender"),
    ("phone", "Phone"),
]


def _style(root: tk.Tk) -> None:
    style = ttk.Style(root)
    try:
        style.theme_use("clam")
    except tk.TclError:
        pass
    style.configure(".", background=BG, foreground=FG, font=FONT)
    style.configure("TFrame", background=BG)
    style.configure("TLabel", background=BG, foreground=FG)
    style.configure("Muted.TLabel", background=BG, foreground=MUTED)
    style.configure("Title.TLabel", background=BG, foreground=FG, font=FONT_TITLE)
    style.configure("TEntry", fieldbackground=BG, foreground=FG, bordercolor=LINE)
    style.configure("TButton", background=BG, foreground=FG, bordercolor=FG,
                    focuscolor=BG, padding=(10, 4))
    style.map("TButton",
              background=[("active", "#eeeeee"), ("pressed", "#dddddd")],
              foreground=[("disabled", MUTED)])
    style.configure("Accent.TButton", background=FG, foreground=BG)
    style.map("Accent.TButton",
              background=[("active", "#333333"), ("pressed", "#000000")],
              foreground=[("active", BG)])


# =========================================================================
#  Password generator dialog
# =========================================================================
class GeneratorDialog(tk.Toplevel):
    def __init__(self, parent, policy: PasswordPolicy):
        super().__init__(parent)
        self.title("Generate password")
        self.configure(bg=BG)
        self.resizable(False, False)
        self.transient(parent)
        self.grab_set()
        self.result: str | None = None
        self.result_policy: PasswordPolicy | None = None

        self.length = tk.IntVar(value=policy.length)
        self.use_lower = tk.BooleanVar(value=policy.use_lower)
        self.use_upper = tk.BooleanVar(value=policy.use_upper)
        self.use_digits = tk.BooleanVar(value=policy.use_digits)
        self.use_symbols = tk.BooleanVar(value=policy.use_symbols)
        self.avoid_ambiguous = tk.BooleanVar(value=policy.avoid_ambiguous)
        self.allowed_symbols = tk.StringVar(value=policy.allowed_symbols)
        self.preview = tk.StringVar(value="")

        pad = {"padx": 12, "pady": 4}
        frm = ttk.Frame(self, padding=14)
        frm.grid(sticky="nsew")

        ttk.Label(frm, text="Length").grid(row=0, column=0, sticky="w")
        length_row = ttk.Frame(frm)
        length_row.grid(row=0, column=1, sticky="ew")
        self.length_label = ttk.Label(length_row, text=str(policy.length), width=3)
        self.length_label.pack(side="right")
        scale = ttk.Scale(length_row, from_=6, to=64, variable=self.length,
                          command=lambda _=None: self._on_change())
        scale.pack(side="left", fill="x", expand=True)

        checks = [
            ("Lowercase (a-z)", self.use_lower),
            ("Uppercase (A-Z)", self.use_upper),
            ("Digits (0-9)", self.use_digits),
            ("Symbols", self.use_symbols),
            ("Avoid look-alike characters (l, 1, O, 0...)", self.avoid_ambiguous),
        ]
        for i, (label, var) in enumerate(checks, start=1):
            ttk.Checkbutton(frm, text=label, variable=var,
                            command=self._on_change).grid(row=i, column=0, columnspan=2, sticky="w")

        ttk.Label(frm, text="Allowed symbols").grid(row=6, column=0, sticky="w", pady=(6, 0))
        ttk.Entry(frm, textvariable=self.allowed_symbols, font=FONT_MONO).grid(
            row=6, column=1, sticky="ew", pady=(6, 0))
        self.allowed_symbols.trace_add("write", lambda *_: self._on_change())

        prev = ttk.Frame(frm)
        prev.grid(row=7, column=0, columnspan=2, sticky="ew", pady=(12, 4))
        self.preview_entry = ttk.Entry(prev, textvariable=self.preview, font=FONT_MONO,
                                       state="readonly")
        self.preview_entry.pack(side="left", fill="x", expand=True)
        ttk.Button(prev, text="↻", width=3, command=self._on_change).pack(side="left", padx=(6, 0))

        self.strength = ttk.Label(frm, text="", style="Muted.TLabel")
        self.strength.grid(row=8, column=0, columnspan=2, sticky="w")

        btns = ttk.Frame(frm)
        btns.grid(row=9, column=0, columnspan=2, sticky="e", pady=(12, 0))
        ttk.Button(btns, text="Cancel", command=self._cancel).pack(side="right", padx=(6, 0))
        ttk.Button(btns, text="Use this", style="Accent.TButton",
                   command=self._accept).pack(side="right")

        frm.columnconfigure(1, weight=1)
        self._on_change()
        self.bind("<Return>", lambda _e: self._accept())
        self.bind("<Escape>", lambda _e: self._cancel())

    def _current_policy(self) -> PasswordPolicy:
        return PasswordPolicy(
            length=int(round(self.length.get())),
            use_lower=self.use_lower.get(),
            use_upper=self.use_upper.get(),
            use_digits=self.use_digits.get(),
            use_symbols=self.use_symbols.get(),
            avoid_ambiguous=self.avoid_ambiguous.get(),
            allowed_symbols=self.allowed_symbols.get(),
        )

    def _on_change(self) -> None:
        self.length_label.config(text=str(int(round(self.length.get()))))
        try:
            pw = generate(self._current_policy())
            self.preview.set(pw)
            self.strength.config(text=f"Strength: {strength_label(pw)}")
        except ValueError as exc:
            self.preview.set("")
            self.strength.config(text=str(exc))

    def _accept(self) -> None:
        if not self.preview.get():
            return
        self.result = self.preview.get()
        self.result_policy = self._current_policy()
        self.destroy()

    def _cancel(self) -> None:
        self.result = None
        self.destroy()


# =========================================================================
#  Custom (extra) fields editor
# =========================================================================
class CustomFields(ttk.Frame):
    """A little editor for arbitrary key/value pairs."""

    def __init__(self, parent):
        super().__init__(parent)
        self.rows: list[tuple[ttk.Entry, ttk.Entry, ttk.Frame]] = []
        self.body = ttk.Frame(self)
        self.body.pack(fill="x")
        ttk.Button(self, text="+ Add extra field", command=self.add_row).pack(anchor="w", pady=(4, 0))

    def add_row(self, key: str = "", value: str = "") -> None:
        row = ttk.Frame(self.body)
        row.pack(fill="x", pady=2)
        k = ttk.Entry(row, width=18)
        k.insert(0, key)
        k.pack(side="left")
        v = ttk.Entry(row)
        v.insert(0, value)
        v.pack(side="left", fill="x", expand=True, padx=(6, 6))
        ttk.Button(row, text="✕", width=3,
                   command=lambda: self._remove(row)).pack(side="left")
        self.rows.append((k, v, row))

    def _remove(self, row: ttk.Frame) -> None:
        self.rows = [r for r in self.rows if r[2] is not row]
        row.destroy()

    def load(self, data: dict) -> None:
        for _, _, row in self.rows:
            row.destroy()
        self.rows.clear()
        for key, value in (data or {}).items():
            self.add_row(str(key), str(value))

    def dump(self) -> dict:
        out = {}
        for k, v, _ in self.rows:
            key = k.get().strip()
            if key:
                out[key] = v.get()
        return out


# =========================================================================
#  Login / create-master-password screen
# =========================================================================
class LockScreen(ttk.Frame):
    def __init__(self, parent, vault_exists: bool, on_unlock):
        super().__init__(parent, padding=40)
        self.on_unlock = on_unlock
        self.vault_exists = vault_exists

        ttk.Label(self, text="MyVault", style="Title.TLabel").pack(pady=(0, 4))
        sub = "Enter your master password" if vault_exists else "Create your master password"
        ttk.Label(self, text=sub, style="Muted.TLabel").pack(pady=(0, 16))

        self.pw1 = tk.StringVar()
        self.pw2 = tk.StringVar()

        self.e1 = ttk.Entry(self, textvariable=self.pw1, show="•", width=32, font=FONT)
        self.e1.pack(pady=4)
        self.e1.focus_set()

        if not vault_exists:
            self.e2 = ttk.Entry(self, textvariable=self.pw2, show="•", width=32, font=FONT)
            self.e2.pack(pady=4)
            ttk.Label(self, text="Confirm master password", style="Muted.TLabel").pack()
            warn = ("Write this password down somewhere safe. There is NO way to "
                    "recover your vault if you forget it — that is what keeps it secure.")
            ttk.Label(self, text=warn, style="Muted.TLabel", wraplength=340,
                      justify="center").pack(pady=(10, 0))

        self.msg = ttk.Label(self, text="", foreground="#a00000", background=BG)
        self.msg.pack(pady=(8, 0))

        btn_text = "Unlock" if vault_exists else "Create vault"
        ttk.Button(self, text=btn_text, style="Accent.TButton",
                   command=self._submit).pack(pady=(14, 0))

        self.bind_all("<Return>", lambda _e: self._submit())

    def _submit(self) -> None:
        pw = self.pw1.get()
        if not pw:
            self.msg.config(text="Please enter a password.")
            return
        if not self.vault_exists:
            if len(pw) < 8:
                self.msg.config(text="Use at least 8 characters.")
                return
            if pw != self.pw2.get():
                self.msg.config(text="The two passwords do not match.")
                return
        self.unbind_all("<Return>")
        self.on_unlock(pw)

    def show_error(self, text: str) -> None:
        self.msg.config(text=text)
        self.bind_all("<Return>", lambda _e: self._submit())


# =========================================================================
#  Browser connector setup dialog
# =========================================================================
class BrowserConnectDialog(tk.Toplevel):
    def __init__(self, parent):
        super().__init__(parent)
        self.parent = parent
        self.title("Browser auto-fill")
        self.configure(bg=BG)
        self.resizable(False, False)
        self.transient(parent)
        self.grab_set()

        cfg = config.load()
        running = bool(parent.connector and parent.connector.running)
        ext_path = Path(__file__).resolve().parent.parent / "browser-extension"

        frm = ttk.Frame(self, padding=16)
        frm.grid(sticky="nsew")

        ttk.Label(frm, text="Browser auto-fill", style="Title.TLabel").grid(
            row=0, column=0, columnspan=2, sticky="w")
        status = "● Connector running" if running else "● Connector NOT running"
        color = "#0a7d00" if running else "#a00000"
        ttk.Label(frm, text=f"{status}  (127.0.0.1 : {cfg['port']})",
                  foreground=color, background=BG).grid(
            row=1, column=0, columnspan=2, sticky="w", pady=(2, 12))

        steps = (
            "One-time setup:\n"
            "1. Open your browser and go to the Extensions page\n"
            "     (Comet/Chrome: menu → Extensions → Manage Extensions).\n"
            "2. Turn ON “Developer mode” (top-right).\n"
            "3. Click “Load unpacked” and choose the folder shown below.\n"
            "4. Open the MyVault extension's Options and paste the pairing\n"
            "     token below, then click “Save & test”.\n\n"
            "After that: on any login page, the extension offers to fill from\n"
            "MyVault, and offers to save new logins you type. Auto-fill only\n"
            "works while this app is open and unlocked."
        )
        ttk.Label(frm, text=steps, style="Muted.TLabel", justify="left").grid(
            row=2, column=0, columnspan=2, sticky="w")

        ttk.Label(frm, text="Extension folder", style="Muted.TLabel").grid(
            row=3, column=0, sticky="w", pady=(12, 0))
        path_var = tk.StringVar(value=str(ext_path))
        ttk.Entry(frm, textvariable=path_var, font=FONT_MONO, state="readonly",
                  width=54).grid(row=4, column=0, sticky="ew")
        ttk.Button(frm, text="Copy", width=6,
                   command=lambda: self._copy(str(ext_path))).grid(row=4, column=1, padx=(6, 0))

        ttk.Label(frm, text="Pairing token", style="Muted.TLabel").grid(
            row=5, column=0, sticky="w", pady=(10, 0))
        self.tok_var = tk.StringVar(value=cfg["token"])
        ttk.Entry(frm, textvariable=self.tok_var, font=FONT_MONO, state="readonly",
                  width=54).grid(row=6, column=0, sticky="ew")
        ttk.Button(frm, text="Copy", width=6,
                   command=lambda: self._copy(cfg["token"])).grid(row=6, column=1, padx=(6, 0))

        btns = ttk.Frame(frm)
        btns.grid(row=7, column=0, columnspan=2, sticky="e", pady=(16, 0))
        ttk.Button(btns, text="Regenerate token", command=self._regen).pack(side="left")
        ttk.Button(btns, text="Close", style="Accent.TButton",
                   command=self.destroy).pack(side="left", padx=(6, 0))

        self.status = ttk.Label(frm, text="", style="Muted.TLabel")
        self.status.grid(row=8, column=0, columnspan=2, sticky="w", pady=(8, 0))
        frm.columnconfigure(0, weight=1)
        self.bind("<Escape>", lambda _e: self.destroy())

    def _copy(self, value: str) -> None:
        self.clipboard_clear()
        self.clipboard_append(value)
        self.status.config(text="Copied to clipboard.")

    def _regen(self) -> None:
        if not messagebox.askyesno(
                "Regenerate token",
                "Make a new pairing token? You'll need to paste the new token into\n"
                "the browser extension again. Do this if you think the token leaked.",
                parent=self):
            return
        cfg = config.regenerate_token()
        self.tok_var.set(cfg["token"])
        # Restart connector with the new token.
        self.parent._stop_connector()
        self.parent._start_connector()
        self.status.config(text="New token generated. Re-paste it into the extension.")


# =========================================================================
#  LAN sync dialog
# =========================================================================
class LanSyncDialog(tk.Toplevel):
    def __init__(self, parent):
        super().__init__(parent)
        self.parent = parent
        self.title("LAN sync")
        self.configure(bg=BG)
        self.resizable(False, False)
        self.transient(parent)
        self.grab_set()

        running = parent.sync_service is not None
        ip = sync.local_ip()

        frm = ttk.Frame(self, padding=16)
        frm.grid(sticky="nsew")
        ttk.Label(frm, text="Sync over your WiFi", style="Title.TLabel").grid(
            row=0, column=0, columnspan=2, sticky="w")
        status = "● Sync running" if running else "● Sync NOT running"
        ttk.Label(frm, text=f"{status}   —   this PC is {ip} : {sync.SYNC_PORT}",
                  foreground=("#0a7d00" if running else "#a00000"), background=BG).grid(
            row=1, column=0, columnspan=2, sticky="w", pady=(2, 12))

        info = (
            "How it works:\n"
            "• Open MyVault on BOTH devices, on the SAME home WiFi, each unlocked\n"
            "   with the SAME master password.\n"
            "• They find each other automatically and merge — newest change to\n"
            "   each entry wins, and deletions carry across. Nothing leaves your\n"
            "   network; the exchange is encrypted with your master password.\n\n"
            "If they don't find each other automatically (some routers block that),\n"
            "type the other device's address below and sync manually."
        )
        ttk.Label(frm, text=info, style="Muted.TLabel", justify="left").grid(
            row=2, column=0, columnspan=2, sticky="w")

        ttk.Label(frm, text="Other device address (optional)", style="Muted.TLabel").grid(
            row=3, column=0, sticky="w", pady=(12, 0))
        self.host_var = tk.StringVar()
        ttk.Entry(frm, textvariable=self.host_var, font=FONT_MONO, width=28).grid(
            row=4, column=0, sticky="ew")
        ttk.Button(frm, text="Sync with address",
                   command=lambda: self._sync_now(self.host_var.get().strip())).grid(
            row=4, column=1, padx=(6, 0))

        btns = ttk.Frame(frm)
        btns.grid(row=5, column=0, columnspan=2, sticky="ew", pady=(16, 0))
        ttk.Button(btns, text="Sync now (auto-find)", style="Accent.TButton",
                   command=lambda: self._sync_now(None)).pack(side="left")
        ttk.Button(btns, text="Close", command=self.destroy).pack(side="right")

        self.status = ttk.Label(frm, text=self._last_text(), style="Muted.TLabel",
                                wraplength=360, justify="left")
        self.status.grid(row=6, column=0, columnspan=2, sticky="w", pady=(12, 0))
        frm.columnconfigure(0, weight=1)
        self.bind("<Escape>", lambda _e: self.destroy())

    def _last_text(self) -> str:
        r = self.parent._last_sync
        if not r:
            return "No sync yet this session."
        if r.ok:
            return f"Last sync ✓ with {r.peer}: {r.added_or_updated} entries updated."
        return f"Last attempt: {r.error}"

    def _sync_now(self, host: str | None) -> None:
        if self.parent.sync_service is None:
            self.status.config(text="Sync is turned off or the port is busy.")
            return
        self.status.config(text="Syncing…")

        def work():
            res = self.parent.sync_service.sync_now(host or None)
            self.parent.after(0, self._after_sync)

        threading.Thread(target=work, daemon=True).start()

    def _after_sync(self) -> None:
        if self.winfo_exists():
            self.status.config(text=self._last_text())


# =========================================================================
#  Main application
# =========================================================================
class MyVaultApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("MyVault")
        self.geometry("900x600")
        self.minsize(760, 500)
        self.configure(bg=BG)
        _style(self)

        self.vault: Vault | None = None
        self.current: Entry | None = None
        self._clip_value: str | None = None
        self._dirty = False
        self._last_activity = 0.0

        # Browser connector (started on unlock). Guards vault writes so the
        # connector thread and the UI never save at the same time.
        self.connector: server.Connector | None = None
        self._vault_lock = threading.Lock()
        self._pending_refresh = threading.Event()

        # LAN sync (started on unlock).
        self.sync_service: sync.SyncService | None = None
        self._last_sync: sync.SyncResult | None = None

        self.container = ttk.Frame(self)
        self.container.pack(fill="both", expand=True)
        self._show_lock()

        self.protocol("WM_DELETE_WINDOW", self._on_close)

    # ---- screen switching ------------------------------------------------
    def _clear_container(self) -> None:
        for child in self.container.winfo_children():
            child.destroy()

    def _show_lock(self) -> None:
        self.vault = None
        self.current = None
        self._clear_container()
        exists = paths.vault_path().exists()
        self.lock = LockScreen(self.container, exists, self._try_unlock)
        self.lock.pack(fill="both", expand=True)

    def _try_unlock(self, password: str) -> None:
        path = paths.vault_path()
        try:
            if path.exists():
                self.vault = Vault.open(path, password)
            else:
                self.vault = Vault.create(path, password)
        except crypto.WrongPasswordError:
            self.lock.show_error("Wrong master password. Try again.")
            return
        except crypto.VaultFormatError as exc:
            self.lock.show_error(str(exc))
            return
        self._show_main()

    # ---- main layout -----------------------------------------------------
    def _show_main(self) -> None:
        self._clear_container()
        self._build_menu()

        outer = ttk.Frame(self.container)
        outer.pack(fill="both", expand=True)

        # top bar
        top = ttk.Frame(outer, padding=(10, 8))
        top.pack(fill="x")
        self.search_var = tk.StringVar()
        self.search_var.trace_add("write", lambda *_: self._refresh_list())
        search = ttk.Entry(top, textvariable=self.search_var, font=FONT)
        search.pack(side="left", fill="x", expand=True)
        search.insert(0, "")
        ttk.Button(top, text="+ New", style="Accent.TButton",
                   command=self._new_entry).pack(side="left", padx=(8, 0))
        ttk.Button(top, text="Lock", command=self._lock_now).pack(side="left", padx=(6, 0))

        sep = tk.Frame(outer, height=1, bg=LINE)
        sep.pack(fill="x")

        body = ttk.Frame(outer)
        body.pack(fill="both", expand=True)

        # left: entry list
        left = ttk.Frame(body, padding=(8, 8))
        left.pack(side="left", fill="y")
        self.listbox = tk.Listbox(left, width=28, font=FONT, activestyle="none",
                                  bg=BG, fg=FG, highlightthickness=1,
                                  highlightbackground=LINE, selectbackground=SEL_BG,
                                  selectforeground=SEL_FG, borderwidth=0)
        self.listbox.pack(fill="y", expand=True)
        self.listbox.bind("<<ListboxSelect>>", self._on_select)

        vsep = tk.Frame(body, width=1, bg=LINE)
        vsep.pack(side="left", fill="y")

        # right: detail form (scrollable)
        right = ttk.Frame(body)
        right.pack(side="left", fill="both", expand=True)
        self._build_form(right)

        self._entry_index: list[Entry] = []
        self._refresh_list()
        self._show_empty_form()

        # activity tracking for auto-lock
        for seq in ("<Key>", "<Button>", "<Motion>"):
            self.bind_all(seq, self._mark_activity)
        self._mark_activity()
        self._schedule_autolock()
        self._start_connector()
        self._start_sync()
        self._poll_connector()

    def _build_menu(self) -> None:
        menubar = tk.Menu(self)
        m = tk.Menu(menubar, tearoff=0)
        m.add_command(label="Change master password", command=self._change_master)
        m.add_command(label="Browser auto-fill…", command=self._browser_dialog)
        m.add_command(label="LAN sync…", command=self._sync_dialog)
        m.add_command(label="Lock", command=self._lock_now)
        m.add_separator()
        m.add_command(label="Where is my vault file?", command=self._show_location)
        m.add_command(label="About MyVault", command=self._about)
        m.add_separator()
        m.add_command(label="Quit", command=self._on_close)
        menubar.add_cascade(label="Menu", menu=m)
        self.config(menu=menubar)

    def _build_form(self, parent) -> None:
        canvas = tk.Canvas(parent, bg=BG, highlightthickness=0)
        scroll = ttk.Scrollbar(parent, orient="vertical", command=canvas.yview)
        self.form = ttk.Frame(canvas, padding=(16, 12))
        self.form.bind("<Configure>",
                       lambda _e: canvas.configure(scrollregion=canvas.bbox("all")))
        window = canvas.create_window((0, 0), window=self.form, anchor="nw")
        canvas.bind("<Configure>", lambda e: canvas.itemconfig(window, width=e.width))
        canvas.configure(yscrollcommand=scroll.set)
        canvas.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")
        canvas.bind_all("<MouseWheel>",
                        lambda e: canvas.yview_scroll(int(-e.delta / 120), "units"))

        self.vars: dict[str, tk.StringVar] = {}
        row = 0
        for key, label in STANDARD_FIELDS:
            ttk.Label(self.form, text=label, style="Muted.TLabel").grid(
                row=row, column=0, sticky="w", pady=(6, 0))
            var = tk.StringVar()
            self.vars[key] = var
            entry = ttk.Entry(self.form, textvariable=var, font=FONT)
            entry.grid(row=row + 1, column=0, columnspan=3, sticky="ew")
            row += 2

        # password row (special: show/hide, copy, generate)
        ttk.Label(self.form, text="Password", style="Muted.TLabel").grid(
            row=row, column=0, sticky="w", pady=(6, 0))
        self.pw_strength = ttk.Label(self.form, text="", style="Muted.TLabel")
        self.pw_strength.grid(row=row, column=2, sticky="e")
        row += 1
        self.pw_var = tk.StringVar()
        self.pw_var.trace_add("write", lambda *_: self._update_pw_strength())
        self.pw_entry = ttk.Entry(self.form, textvariable=self.pw_var, show="•", font=FONT_MONO)
        self.pw_entry.grid(row=row, column=0, sticky="ew")
        self._pw_shown = False
        ttk.Button(self.form, text="Show", width=6,
                   command=self._toggle_pw).grid(row=row, column=1, padx=(6, 0))
        ttk.Button(self.form, text="Generate", width=9,
                   command=self._generate_pw).grid(row=row, column=2, padx=(6, 0))
        row += 1

        # notes
        ttk.Label(self.form, text="Notes", style="Muted.TLabel").grid(
            row=row, column=0, sticky="w", pady=(6, 0))
        row += 1
        self.notes = tk.Text(self.form, height=4, font=FONT, bg=BG, fg=FG,
                             highlightthickness=1, highlightbackground=LINE,
                             borderwidth=0, wrap="word")
        self.notes.grid(row=row, column=0, columnspan=3, sticky="ew")
        row += 1

        # custom fields
        ttk.Label(self.form, text="Extra fields", style="Muted.TLabel").grid(
            row=row, column=0, sticky="w", pady=(10, 0))
        row += 1
        self.custom = CustomFields(self.form)
        self.custom.grid(row=row, column=0, columnspan=3, sticky="ew")
        row += 1

        # copy buttons
        copy_row = ttk.Frame(self.form)
        copy_row.grid(row=row, column=0, columnspan=3, sticky="w", pady=(12, 0))
        ttk.Button(copy_row, text="Copy username",
                   command=lambda: self._copy(self.vars["username"].get(), "Username")).pack(side="left")
        ttk.Button(copy_row, text="Copy email",
                   command=lambda: self._copy(self.vars["email"].get(), "Email")).pack(side="left", padx=(6, 0))
        ttk.Button(copy_row, text="Copy password",
                   command=lambda: self._copy(self.pw_var.get(), "Password")).pack(side="left", padx=(6, 0))
        row += 1

        # save / delete
        action_row = ttk.Frame(self.form)
        action_row.grid(row=row, column=0, columnspan=3, sticky="ew", pady=(16, 0))
        self.save_btn = ttk.Button(action_row, text="Save", style="Accent.TButton",
                                   command=self._save_entry)
        self.save_btn.pack(side="left")
        self.delete_btn = ttk.Button(action_row, text="Delete", command=self._delete_entry)
        self.delete_btn.pack(side="left", padx=(6, 0))
        self.status = ttk.Label(action_row, text="", style="Muted.TLabel")
        self.status.pack(side="left", padx=(12, 0))

        self.form.columnconfigure(0, weight=1)

    # ---- list ------------------------------------------------------------
    def _refresh_list(self) -> None:
        if not self.vault:
            return
        query = self.search_var.get() if hasattr(self, "search_var") else ""
        self._entry_index = self.vault.search(query)
        self.listbox.delete(0, tk.END)
        for e in self._entry_index:
            self.listbox.insert(tk.END, "  " + e.display_name())
        if not self._entry_index:
            self.listbox.insert(tk.END, "  (no entries)")

    def _on_select(self, _event=None) -> None:
        sel = self.listbox.curselection()
        if not sel or not self._entry_index:
            return
        idx = sel[0]
        if idx >= len(self._entry_index):
            return
        self._load_entry(self._entry_index[idx])

    # ---- form <-> entry --------------------------------------------------
    def _show_empty_form(self) -> None:
        self.current = None
        for var in self.vars.values():
            var.set("")
        self.pw_var.set("")
        self.notes.delete("1.0", tk.END)
        self.custom.load({})
        self.status.config(text="Select an entry, or click “+ New”.")
        self.delete_btn.state(["disabled"])

    def _load_entry(self, entry: Entry) -> None:
        self.current = entry
        for key in self.vars:
            self.vars[key].set(getattr(entry, key, "") or "")
        self.pw_var.set(entry.password or "")
        self.notes.delete("1.0", tk.END)
        self.notes.insert("1.0", entry.notes or "")
        self.custom.load(entry.custom)
        self.status.config(text="")
        self.delete_btn.state(["!disabled"])
        if self._pw_shown:
            self._toggle_pw()

    def _collect(self, entry: Entry) -> None:
        for key, var in self.vars.items():
            setattr(entry, key, var.get().strip())
        entry.password = self.pw_var.get()
        entry.notes = self.notes.get("1.0", tk.END).strip()
        entry.custom = self.custom.dump()

    def _new_entry(self) -> None:
        self._show_empty_form()
        self.current = Entry()
        self.delete_btn.state(["disabled"])
        self.status.config(text="New entry — fill it in and click Save.")
        self.vars["title"].set("")

    def _save_entry(self) -> None:
        if self.current is None:
            self.current = Entry()
        is_new = self.vault.get(self.current.id) is None
        self._collect(self.current)
        if not self.current.display_name() or self.current.display_name() == "(untitled)":
            messagebox.showwarning("Nothing to save",
                                   "Give the entry at least a title, website, or username.")
            return
        try:
            with self._vault_lock:
                if is_new:
                    self.vault.add(self.current)
                else:
                    self.vault.update(self.current)
        except OSError as exc:
            messagebox.showerror("Could not save", f"Failed to write the vault file:\n{exc}")
            return
        self._refresh_list()
        self.status.config(text="Saved ✓")

    def _delete_entry(self) -> None:
        if not self.current or self.vault.get(self.current.id) is None:
            return
        if not messagebox.askyesno("Delete entry",
                                   f"Delete “{self.current.display_name()}”?\nThis cannot be undone."):
            return
        with self._vault_lock:
            self.vault.delete(self.current.id)
        self._refresh_list()
        self._show_empty_form()

    # ---- password helpers ------------------------------------------------
    def _toggle_pw(self) -> None:
        self._pw_shown = not self._pw_shown
        self.pw_entry.config(show="" if self._pw_shown else "•")

    def _update_pw_strength(self) -> None:
        self.pw_strength.config(text=strength_label(self.pw_var.get()))

    def _generate_pw(self) -> None:
        policy = PasswordPolicy.from_dict(
            self.current.password_policy if self.current else None)
        dlg = GeneratorDialog(self, policy)
        self.wait_window(dlg)
        if dlg.result:
            self.pw_var.set(dlg.result)
            if self.current and dlg.result_policy:
                self.current.password_policy = dlg.result_policy.to_dict()
            if not self._pw_shown:
                self._toggle_pw()

    # ---- clipboard -------------------------------------------------------
    def _copy(self, value: str, label: str) -> None:
        if not value:
            self.status.config(text=f"{label} is empty.")
            return
        self.clipboard_clear()
        self.clipboard_append(value)
        self._clip_value = value
        self.status.config(text=f"{label} copied — clears in {CLIPBOARD_CLEAR_SECONDS}s.")
        self.after(CLIPBOARD_CLEAR_SECONDS * 1000, lambda: self._clear_clip(value))

    def _clear_clip(self, value: str) -> None:
        # Only clear if the clipboard still holds what we put there.
        try:
            if self.clipboard_get() == value and self._clip_value == value:
                self.clipboard_clear()
                self.clipboard_append("")
        except tk.TclError:
            pass

    # ---- auto-lock -------------------------------------------------------
    def _mark_activity(self, _event=None) -> None:
        import time
        self._last_activity = time.time()

    def _schedule_autolock(self) -> None:
        self.after(20000, self._check_autolock)

    def _check_autolock(self) -> None:
        import time
        if self.vault is None:
            return
        if time.time() - self._last_activity > AUTO_LOCK_MINUTES * 60:
            self._lock_now()
            return
        self._schedule_autolock()

    def _lock_now(self) -> None:
        self._stop_connector()
        self._stop_sync()
        self.config(menu=tk.Menu(self))
        self._show_lock()

    # ---- menu actions ----------------------------------------------------
    def _change_master(self) -> None:
        new = simpledialog.askstring("Change master password",
                                     "New master password (min 8 chars):", show="•", parent=self)
        if new is None:
            return
        if len(new) < 8:
            messagebox.showwarning("Too short", "Use at least 8 characters.")
            return
        confirm = simpledialog.askstring("Change master password",
                                         "Type it again to confirm:", show="•", parent=self)
        if confirm != new:
            messagebox.showwarning("Mismatch", "The passwords did not match.")
            return
        with self._vault_lock:
            self.vault.change_password(new)
        messagebox.showinfo("Done", "Master password changed.")

    def _show_location(self) -> None:
        messagebox.showinfo("Vault location",
                            f"Your encrypted vault file is:\n\n{paths.vault_path()}\n\n"
                            "Back this file up. It is useless to anyone without your master password.")

    def _about(self) -> None:
        messagebox.showinfo(
            "About MyVault",
            "MyVault — your own offline password manager.\n\n"
            "• 100% local. Nothing is sent anywhere.\n"
            "• Encrypted with scrypt + AES-256-GCM.\n"
            "• Only your master password can open it.\n\n"
            "Keep a backup of your vault file and never forget your master password.")

    def _on_close(self) -> None:
        self._stop_connector()
        self._stop_sync()
        self.destroy()

    # ---- LAN sync --------------------------------------------------------
    def _start_sync(self) -> None:
        cfg = config.load()
        if not cfg.get("sync_enabled", True):
            return
        try:
            self.sync_service = sync.SyncService(self, on_result=self._on_sync_result)
            self.sync_service.start()
        except OSError:
            self.sync_service = None   # port busy; sync just unavailable

    def _stop_sync(self) -> None:
        if self.sync_service is not None:
            self.sync_service.stop()
            self.sync_service = None

    def _on_sync_result(self, result: sync.SyncResult) -> None:
        # Called from a sync thread. Record it and ask the UI to refresh the list.
        self._last_sync = result
        if result.ok and result.added_or_updated:
            self._pending_refresh.set()

    # -- SyncProvider API (called from sync threads) --
    def get_password(self) -> str:
        return self.vault._password if self.vault else ""

    def get_entries(self) -> list[dict]:
        if self.vault is None:
            return []
        with self._vault_lock:
            return [e.to_dict() for e in self.vault.entries]

    def apply_merged(self, merged: list[dict]) -> int:
        if self.vault is None:
            return 0
        with self._vault_lock:
            before = {e.id: e.updated_at for e in self.vault.entries}
            self.vault.entries = [Entry.from_dict(d) for d in merged]
            self.vault.save()
            return sum(1 for e in self.vault.entries
                       if before.get(e.id) is None or e.updated_at > before[e.id])

    def device_id(self) -> str:
        return self.vault.device_id if self.vault else ""

    def _sync_dialog(self) -> None:
        LanSyncDialog(self)

    # ---- browser connector ----------------------------------------------
    def _start_connector(self) -> None:
        cfg = config.load()
        if not cfg.get("enabled", True):
            return
        try:
            self.connector = server.Connector(self, cfg["token"], int(cfg["port"]))
            self.connector.start()
        except OSError:
            # Port busy or blocked — auto-fill just won't be available; the app
            # keeps working normally. Surfaced in the Browser auto-fill dialog.
            self.connector = None

    def _stop_connector(self) -> None:
        if self.connector is not None:
            self.connector.stop()
            self.connector = None

    def _poll_connector(self) -> None:
        # The connector runs in another thread; it flags when it changed the
        # vault so the main thread can safely refresh the list.
        if self.vault is None:
            return
        if self._pending_refresh.is_set():
            self._pending_refresh.clear()
            self._refresh_list()
        self.after(700, self._poll_connector)

    # -- provider API called by server.py (from the connector thread) --
    def is_unlocked(self) -> bool:
        return self.vault is not None

    def match(self, domain: str) -> list[dict]:
        if self.vault is None:
            return []
        out = []
        for e in self.vault.active_entries():
            if any(webmatch.hosts_match(domain, h) for h in webmatch.entry_hosts(e)):
                out.append({
                    "id": e.id,
                    "title": e.display_name(),
                    "username": e.username,
                    "email": e.email,
                    "password": e.password,
                })
        return out

    def save(self, cred: dict) -> dict:
        if self.vault is None:
            return {"ok": False, "error": "locked"}
        domain = webmatch.normalize_host(cred.get("domain") or cred.get("url") or "")
        login = (cred.get("username") or cred.get("email") or "").strip()
        password = cred.get("password") or ""
        if not password:
            return {"ok": False, "error": "no password"}

        with self._vault_lock:
            # Find an existing entry for this site + same login to update.
            target = None
            for e in self.vault.active_entries():
                same_site = any(webmatch.hosts_match(domain, h) for h in webmatch.entry_hosts(e))
                same_login = login and login in (e.username, e.email)
                if same_site and (same_login or not login):
                    target = e
                    break

            if target is None:
                entry = Entry(
                    title=domain or cred.get("title") or login,
                    website=domain,
                    username=cred.get("username", "") or "",
                    email=cred.get("email", "") or "",
                    password=password,
                    phone=cred.get("phone", "") or "",
                )
                self._apply_extra(entry, cred)
                self.vault.add(entry)
                action, entry_id = "created", entry.id
            elif (target.password != password
                  or self._has_new_details(target, cred)):
                target.password = password
                # Fill in any fields the entry didn't already have.
                for field in ("username", "email", "phone"):
                    if cred.get(field) and not getattr(target, field):
                        setattr(target, field, cred[field])
                self._apply_extra(target, cred)
                self.vault.update(target)
                action, entry_id = "updated", target.id
            else:
                action, entry_id = "unchanged", target.id

        self._pending_refresh.set()
        return {"ok": True, "action": action, "id": entry_id}

    @staticmethod
    def _apply_extra(entry: Entry, cred: dict) -> None:
        """Merge any extra captured key/values (e.g. from a signup form) into the
        entry's custom fields, without clobbering ones the user already set."""
        extra = cred.get("extra") or {}
        for key, value in extra.items():
            if value and key and key not in entry.custom:
                entry.custom[str(key)] = str(value)

    @staticmethod
    def _has_new_details(target: Entry, cred: dict) -> bool:
        for field in ("username", "email", "phone"):
            if cred.get(field) and not getattr(target, field):
                return True
        extra = cred.get("extra") or {}
        return any(v and k not in target.custom for k, v in extra.items())

    def generate(self, policy: dict | None) -> str:
        try:
            return generate(PasswordPolicy.from_dict(policy))
        except ValueError:
            return generate(PasswordPolicy())

    def _browser_dialog(self) -> None:
        BrowserConnectDialog(self)


def run() -> None:
    app = MyVaultApp()
    app.mainloop()
