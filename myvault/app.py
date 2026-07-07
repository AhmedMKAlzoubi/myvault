"""
The MyVault desktop window (Tkinter).

Design goals: black-and-white, plain, low memory, keyboard-friendly.
Nothing here talks to the network. The only file touched is your encrypted vault.
"""

from __future__ import annotations

import tkinter as tk
from tkinter import ttk, messagebox, simpledialog
from pathlib import Path

from . import crypto, paths
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

    def _build_menu(self) -> None:
        menubar = tk.Menu(self)
        m = tk.Menu(menubar, tearoff=0)
        m.add_command(label="Change master password", command=self._change_master)
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
        self.destroy()


def run() -> None:
    app = MyVaultApp()
    app.mainloop()
