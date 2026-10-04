"use strict";
// MyVault desktop UI. Talks to Python only through window.pywebview.api.
// Entry data is user/website-supplied: it is only ever set with textContent,
// never innerHTML. innerHTML is used solely for the constant icon strings below.

(() => {
  const $ = (s, r = document) => r.querySelector(s);

  // ---- icons (one stroke family, 24px grid) --------------------------------
  const P = (d) => `<svg viewBox="0 0 24 24">${d}</svg>`;
  const ICONS = {
    login: P('<circle cx="8" cy="15" r="4"/><path d="M11 12l9-9M17 6l3 3M15 8l2 2"/>'),
    api: P('<path d="M8 6l-6 6 6 6M16 6l6 6-6 6M13.5 4l-3 16"/>'),
    ssh: P('<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 10l3 2.5L7 15M12.5 15H17"/>'),
    note: P('<path d="M6 3h9l4 4v14H6z"/><path d="M14 3v5h5M9 13h7M9 17h5"/>'),
    search: P('<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2"/>'),
    plus: P('<path d="M12 5v14M5 12h14"/>'),
    lock: P('<rect x="5" y="10.5" width="14" height="10" rx="2"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/>'),
    eye: P('<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>'),
    eyeoff: P('<path d="M4 4l16 16M9.9 5.8A9.6 9.6 0 0 1 12 5.5c6 0 9.5 6.5 9.5 6.5a16 16 0 0 1-3 3.7M6.3 7.4A16 16 0 0 0 2.5 12S6 18.5 12 18.5a9 9 0 0 0 4-.9M10 10a3 3 0 0 0 4 4"/>'),
    copy: P('<rect x="8.5" y="8.5" width="11.5" height="11.5" rx="2"/><path d="M15.5 8.5V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v7.5a2 2 0 0 0 2 2h2.5"/>'),
    refresh: P('<path d="M20 11a8 8 0 1 0-2.3 5.7M20 4.5V11h-6.5"/>'),
    dice: P('<rect x="4" y="4" width="16" height="16" rx="3"/><circle cx="9" cy="9" r=".6"/><circle cx="15" cy="15" r=".6"/><circle cx="15" cy="9" r=".6"/><circle cx="9" cy="15" r=".6"/>'),
    phone: P('<rect x="7" y="2.5" width="10" height="19" rx="2.5"/><path d="M11 18.5h2"/>'),
    printer: P('<path d="M7 9V3.5h10V9M7 17.5H4.5v-7a1.5 1.5 0 0 1 1.5-1.5h12a1.5 1.5 0 0 1 1.5 1.5v7H17"/><rect x="7" y="14" width="10" height="7"/>'),
    globe: P('<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.7 3.6 5.7 3.6 9s-1.1 6.3-3.6 9c-2.5-2.7-3.6-5.7-3.6-9S9.5 5.7 12 3z"/>'),
    gear: P('<circle cx="12" cy="12" r="3"/><path d="M12 2.5v3M12 18.5v3M4.2 7l2.6 1.5M17.2 15.5 19.8 17M4.2 17l2.6-1.5M17.2 8.5 19.8 7"/><circle cx="12" cy="12" r="6.5"/>'),
    sliders: P('<path d="M4 7h10M18 7h2M4 17h4M12 17h8"/><circle cx="16" cy="7" r="2"/><circle cx="10" cy="17" r="2"/>'),
    edit: P('<path d="M4 20h4L19 9a2.8 2.8 0 0 0-4-4L4 16z"/><path d="M13.5 6.5l4 4"/>'),
    trash: P('<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>'),
    x: P('<path d="M6 6l12 12M18 6L6 18"/>'),
    chev: P('<path d="M9 6l6 6-6 6"/>'),
    file: P('<path d="M6 3h8l4 4v14H6z"/><path d="M13 3v5h5M12 11v6M9.5 14.5 12 17l2.5-2.5"/>'),
    shield: P('<path d="M12 3l7.5 3v5.5c0 4.6-3.2 8.3-7.5 9.5-4.3-1.2-7.5-4.9-7.5-9.5V6z"/><path d="M9 12l2 2 4-4"/>'),
    wifi: P('<path d="M2.5 9a14 14 0 0 1 19 0M5.5 12.5a9.5 9.5 0 0 1 13 0M8.5 16a5 5 0 0 1 7 0"/><circle cx="12" cy="19.2" r=".7"/>'),
    paper: P('<path d="M6 3h12v18H6z"/><path d="M9 7h6M9 11h6M9 15h3"/>'),
    check: P('<path d="M5 12.5l4.5 4.5L19 7.5"/>'),
    keyboard: P('<rect x="2.5" y="6" width="19" height="12" rx="2"/><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M7 14h10"/>'),
    caps: P('<path d="M12 4l7 7.5h-3.8V15H8.8v-3.5H5z"/><path d="M8.8 19.5h6.4"/>'),
    folder: P('<path d="M3 7a2 2 0 0 1 2-2h4l2 2.5h8a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>'),
  };
  const MARK = '<svg viewBox="0 0 30 22" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"><rect x="1" y="1" width="28" height="20" rx="2.5"/><path d="M1.5 2l13.5 10L28.5 2"/><path d="M6 17h8" stroke-width="1.2" stroke-dasharray="1.2 1.6"/></svg>';

  function icon(name) {
    const s = document.createElement("span");
    s.className = "ic";
    s.setAttribute("aria-hidden", "true");
    s.innerHTML = ICONS[name] || "";
    return s;
  }
  function mark() {
    const s = document.createElement("span");
    s.className = "mark";
    s.setAttribute("aria-hidden", "true");
    s.innerHTML = MARK;
    return s;
  }
  // ---- language --------------------------------------------------------------
  // The interface is written in English. When it's shown in Arabic, Python
  // passes window.I18N (myvault/ui/ar.json: English -> Arabic), and every
  // string h() puts on screen goes through t(). Keys with {0}, {1}... match
  // strings built from templates; a {t0} group is translated too (field names).
  // Vault data must never be translated: show it with raw().
  const I18N = window.I18N || {};
  const PATTERNS = Object.keys(I18N).filter((k) => /\{t?\d\}/.test(k))
    .sort((a, b) => b.length - a.length)
    .map((k) => {
      const names = [];
      const body = k.split(/(\{t?\d\})/).map((part) => {
        const m = /^\{(t?\d)\}$/.exec(part);
        if (!m) return part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        names.push(m[1]);
        return "([\\s\\S]+?)";
      }).join("");
      return [new RegExp("^" + body + "$"), names, I18N[k]];
    });
  const ENGLISH = !Object.keys(I18N).length;
  const LOWER = Object.fromEntries(Object.entries(I18N).map(([k, v]) => [k.toLowerCase(), v]));
  const word = (v) => { const x = t(v); return x !== v ? x : LOWER[v.toLowerCase()] ?? v; };   // labels are lowercased in sentences
  const LOCALE = ENGLISH ? undefined : "ar-u-nu-latn";      // Arabic month names, the same digits as the rest of the app
  function t(s) {
    if (typeof s !== "string") return s;
    const core = s.trim();
    if (!core || ENGLISH) return s;
    if (Object.hasOwn(I18N, core)) return s.replace(core, I18N[core]);
    for (const [rx, names, out] of PATTERNS) {
      const m = rx.exec(core);
      if (m) return s.replace(core, out.replace(/\{(t?\d)\}/g, (_, n) => {
        const v = m[names.indexOf(n) + 1];
        return n[0] === "t" ? word(v) : v;
      }));
    }
    return s;
  }
  const raw = (v) => h("bdi", {}, document.createTextNode(v == null ? "" : String(v)));   // data: shown as is

  function h(tag, props, ...kids) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(props || {})) {
      if (v == null || v === false) continue;
      if (k === "class") el.className = v;
      else if (k.startsWith("on") && typeof v === "function") el.addEventListener(k.slice(2), v);
      else if (k === "value" || k === "checked" || k === "disabled") el[k] = v;
      else el.setAttribute(k, v === true ? "" : k === "title" || k === "aria-label" || k === "placeholder" ? t(String(v)) : String(v));
    }
    if ((tag === "input" || tag === "textarea") && !el.dir) el.dir = "auto";   // Arabic or English, each the right way round
    for (const kid of kids.flat(Infinity)) {
      if (kid == null || kid === false) continue;
      el.append(kid instanceof Node ? kid : document.createTextNode(t(String(kid))));
    }
    return el;
  }
  const btn = (label, onclick, cls = "", ic = null, extra = {}) =>
    h("button", { type: "button", class: "btn " + cls, onclick, ...extra }, ic && icon(ic), label);
  const iconBtn = (ic, label, onclick, cls = "") =>
    h("button", { type: "button", class: "btn icon ghost sm " + cls, onclick, title: label, "aria-label": label }, icon(ic));

  // ---- bridge --------------------------------------------------------------
  async function call(name, ...args) {
    try {
      return await window.pywebview.api[name](...args);
    } catch (err) {
      if (String(err && (err.message || err)).includes("locked")) onLocked();
      throw err;
    }
  }

  let toastTimer;
  function toast(msg, bad = false) {
    const el = $("#toast");
    el.textContent = t(msg);
    el.classList.toggle("bad", bad);
    el.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove("show"), 2600);
  }
  async function copy(value, what) {
    if (!value) return toast(`${what} is empty.`);
    const r = await call("copy", value);
    toast(r.ok ? `${what} copied. It clears from the clipboard in ${r.clears_in} s.` : "Couldn't reach the clipboard. Try again.", !r.ok);
  }

  // ---- entry kinds ------------------------------------------------------------
  const F = (key, label, o = {}) => ({ key, label, ...o });
  const KINDS = {
    login: {
      label: "Login", plural: "Logins", desc: "A website or app sign-in.",
      fields: [F("website", "Website", { top: 1, ph: "example.com" }), F("username", "Username", { top: 1 }),
        F("email", "Email", { top: 1, type: "email" }), F("password", "Password", { top: 1, secret: 1, gen: 1 })],
      more: [F("app", "App name", { top: 1 }), F("phone", "Phone", { top: 1, type: "tel" }),
        F("region", "Region / country", { top: 1 }), F("age", "Age", { top: 1 }), F("gender", "Gender", { top: 1 })],
    },
    api: {
      label: "API key", plural: "API keys", desc: "Client IDs, client secrets, API keys and tokens.",
      fields: [F("service", "Service", { ph: "e.g. Google Cloud, Stripe" }), F("endpoint", "Endpoint / URL"),
        F("client_id", "Client ID", { mono: 1 }), F("client_secret", "Client secret", { secret: 1 }),
        F("api_key", "API key", { secret: 1 }), F("token", "Access token", { secret: 1, multi: 1 })],
    },
    ssh: {
      label: "SSH key", plural: "SSH keys", desc: "A private key, its passphrase and the server it opens.",
      fields: [F("host", "Host", { ph: "server.example.com" }), F("port", "Port", { ph: "22" }), F("ssh_user", "User"),
        F("private_key", "Private key", { secret: 1, multi: 1, file: 1 }), F("passphrase", "Passphrase", { secret: 1 }),
        F("public_key", "Public key", { multi: 1, mono: 1, file: 1 }), F("fingerprint", "Fingerprint", { mono: 1 })],
    },
    note: {
      label: "Secure note", plural: "Notes", desc: "Recovery codes, PINs, anything private.",
      fields: [F("notes", "Note", { top: 1, secret: 1, multi: 1 })],
    },
  };
  const getVal = (e, f) => (f.top ? e[f.key] : (e.fields || {})[f.key]) || "";

  // ---- state ----------------------------------------------------------------
  const S = { list: [], filter: "all", query: "", selected: null, view: "home", dirty: false,
    pending: null, exists: true, syncTimer: null, version: "" };

  // ---- lock screen ---------------------------------------------------------
  function renderLock(exists, msg = "") {
    stopSync();
    S.exists = exists;
    S.selected = null;
    const app = $("#app");
    const pw1 = h("input", { class: "inp", type: "password", id: "pw1", autocomplete: "current-password",
      "aria-label": exists ? "Master password" : "New master password", placeholder: exists ? "Master password" : "Choose a master password" });
    const pw2 = !exists && h("input", { class: "inp", type: "password", id: "pw2", "aria-label": "Type it again",
      placeholder: "Type it again" });
    const meter = !exists && strengthLine();
    const err = h("p", { class: "err", role: "alert" }, msg);
    const go = h("button", { class: "btn primary", type: "submit" }, exists ? "Unlock" : "Create my vault");
    if (meter) pw1.addEventListener("input", () => meter.set(pw1.value));

    const form = h("form", { class: "window", autocomplete: "off" },
      h("div", { class: "brand" }, mark(), h("h1", {}, "MyVault")),
      h("p", { class: "lede" }, exists
        ? "Your vault is sealed. Enter your master password to open it."
        : "Choose the one password that opens your vault. It's the only one you'll need to remember."),
      pw1, pw2, meter,
      !exists && h("p", { class: "warn" }, "There's no reset. If this password is forgotten, nobody can open the vault, not even you. Write it down and keep it somewhere safe."),
      err, go);
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      err.textContent = "";
      if (!pw1.value) return (err.textContent = t("Enter your master password."));
      if (!exists) {
        if (pw1.value.length < 8) return (err.textContent = t("Use at least 8 characters. A short sentence works well."));
        if (pw1.value !== pw2.value) return (err.textContent = t("The two passwords don't match."));
      }
      go.disabled = true;
      go.textContent = t(exists ? "Opening…" : "Creating…");
      const r = await call("unlock", pw1.value);
      if (r.ok) return enterMain();
      go.disabled = false;
      go.textContent = t(exists ? "Unlock" : "Create my vault");
      err.textContent = t(r.error);
      pw1.select();
    });
    app.replaceChildren(h("div", { class: "lock" },
      h("div", { class: "tint-field", "aria-hidden": "true" }), h("div", { class: "lock-seal" }), form,
      h("p", { class: "lock-foot" }, h("span", {}, "Encrypted, and stored only on this computer"))));
    app.removeAttribute("aria-busy");
    setTimeout(() => pw1.focus(), 30);
  }

  function onLocked(msg = "") {
    if ($(".lock")) return;
    call("lock").catch(() => {});
    renderLock(true, msg);
  }

  // ---- shell --------------------------------------------------------------
  const TOOLS = [
    ["generator", "Password generator", "dice"],
    ["sync", "Sync with phone", "phone"],
    ["backup", "Paper backup", "printer"],
    ["browser", "Browser auto-fill", "globe"],
    ["settings", "Settings", "gear"],
  ];

  async function enterMain() {
    const search = h("input", { class: "inp", type: "search", id: "search", placeholder: "Search", "aria-label": "Search entries",
      oninput: (e) => { S.query = e.target.value; renderList(); },
      onkeydown: (e) => {
        if (e.key === "ArrowDown") { e.preventDefault(); moveSel(1); }
        if (e.key === "Enter") { const first = visible()[0]; if (first) openEntry(first.id); }
        if (e.key === "Escape") { e.target.value = ""; S.query = ""; renderList(); }
      } });
    const shell = h("div", { class: "shell" },
      h("aside", { class: "rail", "aria-label": "Vault" },
        h("div", { class: "rail-head" }, mark(), h("b", {}, "MyVault"),
          iconBtn("lock", "Lock now (Ctrl+L)", () => onLocked())),
        h("div", { class: "search" }, icon("search"), search, h("kbd", {}, "Ctrl F")),
        h("div", { class: "filters", role: "tablist", "aria-label": "Filter by type", id: "filters" }),
        h("ul", { class: "list", id: "list", role: "listbox", "aria-label": "Entries", tabindex: "0",
          onkeydown: (e) => {
            if (e.key === "ArrowDown" || e.key === "ArrowUp") { e.preventDefault(); moveSel(e.key === "ArrowDown" ? 1 : -1); }
          } }),
        h("div", { class: "rail-new" }, btn("New entry", () => guard(() => showNew()), "primary", "plus")),
        h("div", { id: "updbox", "aria-live": "polite" }),
        h("nav", { class: "tools", id: "tools", "aria-label": "Tools" },
          TOOLS.map(([id, label, ic]) => h("button", { type: "button", class: "tool", "data-tool": id,
            onclick: () => guard(() => showTool(id)) }, icon(ic), label)))),
      h("main", { class: "sheet", id: "sheet", tabindex: "-1" }));
    $("#app").replaceChildren(shell);
    $("#app").removeAttribute("aria-busy");
    await refresh();
    showHome();
    search.focus();
    refreshUpdates();
  }

  // ---- updates ------------------------------------------------------------------
  let updTimer = null;
  async function refreshUpdates() {
    const box = $("#updbox");
    if (!box) return;
    const u = await call("update_state");
    clearTimeout(updTimer);
    if (u.checking || u.busy) updTimer = setTimeout(refreshUpdates, 700);
    let card = null;
    if (u.ask) {
      card = h("div", { class: "updcard" },
        h("b", {}, "Check for updates online?"),
        h("p", {}, "New versions come out now and then. To spot them, MyVault checks a small file on GitHub, at most once a day. Nothing from your vault is sent."),
        h("div", { class: "updrow" },
          btn("Yes, let me know", async () => { await call("set_update_check", true); refreshUpdates(); }, "primary sm"),
          btn("No thanks", async () => { await call("set_update_check", false); refreshUpdates(); }, "sm")));
    } else if (u.busy) {
      card = h("div", { class: "updcard" }, h("b", {}, "Updating MyVault…"),
        h("p", {}, u.progress ? `Downloading ${u.progress}%` : "Checking the update's signature…"),
        h("div", { class: "countdown" }, h("i", { style: `transform:scaleX(${(u.progress || 0) / 100})` })));
    } else if (u.ready || u.available) {
      const v = u.ready || u.available;
      card = h("div", { class: "updcard" },
        h("b", {}, `MyVault ${v} is ${u.ready ? "ready to install" : "available"}`),
        h("p", {}, u.ready ? `It's verified and waiting. You have ${u.current}. Your vault stays as it is.`
          : `You have ${u.current}. Updating keeps your vault exactly as it is.`),
        u.error && h("p", { class: "err" }, u.error),
        h("div", { class: "updrow" },
          btn(u.ready ? "Install now" : "Update now", async () => {
            await call(u.ready ? "install_update" : "update_now"); refreshUpdates();
          }, "primary sm"),
          btn("Later", () => box.replaceChildren(), "sm")));
    }
    box.replaceChildren(...(card ? [card] : []));
  }

  async function refresh() {
    if (!$("#list")) return;
    try { S.list = await call("entries"); } catch { return; }
    renderFilters();
    renderList();
    if (S.view === "home") showHome();
  }

  const byKind = (k) => S.list.filter((e) => k === "all" || e.kind === k);
  function visible() {
    const q = S.query.trim().toLowerCase();
    return byKind(S.filter)
      .filter((e) => !q || [e.title, e.subtitle, e.website].join(" ").toLowerCase().includes(q))
      .sort((a, b) => a.title.localeCompare(b.title, undefined, { sensitivity: "base" }));
  }

  function renderFilters() {
    const box = $("#filters");
    const opts = [["all", "All"], ...Object.entries(KINDS).map(([k, v]) => [k, v.plural])]
      .filter(([k]) => k === "all" || byKind(k).length);
    if (!opts.some(([k]) => k === S.filter)) S.filter = "all";
    box.replaceChildren(...opts.map(([k, label]) => h("button", { type: "button", class: "chip", role: "tab",
      "aria-selected": String(S.filter === k), onclick: () => { S.filter = k; renderFilters(); renderList(); } },
    label, h("span", { class: "n" }, byKind(k).length))));
  }

  function renderList() {
    const ul = $("#list");
    if (!ul) return;
    const items = visible();
    if (!items.length) {
      ul.replaceChildren(h("li", { class: "list-empty" }, S.list.length
        ? `Nothing matches “${S.query}”.` : "No entries yet. Add your first one below."));
      return;
    }
    ul.replaceChildren(...items.map((e) => h("li", { class: "item", role: "option", "data-id": e.id,
      "aria-selected": String(S.selected === e.id), onclick: () => guard(() => openEntry(e.id)) },
    h("span", { class: "glyph" }, icon(e.kind)),
    h("span", { style: "min-width:0" }, h("div", { class: "t" }, raw(e.title)), e.subtitle && h("div", { class: "sub" }, raw(e.subtitle))))));
  }

  function moveSel(d) {
    const items = visible();
    if (!items.length) return;
    let i = items.findIndex((e) => e.id === S.selected);
    i = Math.max(0, Math.min(items.length - 1, i < 0 ? 0 : i + d));
    guard(() => openEntry(items[i].id, true));
  }

  function markTool(id) {
    document.querySelectorAll(".tool").forEach((b) => b.toggleAttribute("aria-current", b.dataset.tool === id));
    document.querySelectorAll(".tool[aria-current]").forEach((b) => b.setAttribute("aria-current", "page"));
  }
  function sheet(...kids) {
    stopSync();
    const s = $("#sheet");
    s.replaceChildren(...kids);
    s.scrollTop = 0;
    return s;
  }

  // Unsaved-changes guard: ask before leaving an edited form.
  function guard(next) {
    if (!S.dirty) return next();
    S.pending = next;
    if ($(".banner")) return;
    const bar = h("div", { class: "banner", role: "alert" }, icon("edit"), "You have unsaved changes.",
      h("span", { class: "spacer" }),
      btn("Discard", () => { S.dirty = false; bar.remove(); const n = S.pending; S.pending = null; n && n(); }, "sm"),
      btn("Keep editing", () => { bar.remove(); S.pending = null; }, "sm primary"));
    $("#sheet").prepend(bar);
  }

  // ---- home --------------------------------------------------------------
  function showHome() {
    S.view = "home";
    S.selected = null;
    markTool(null);
    renderList();
    const empty = !S.list.length;
    sheet(h("section", { class: "home" }, h("div", { class: "tint-field", "aria-hidden": "true" }),
      h("div", { class: "home-card" },
        h("h2", {}, empty ? "Your vault is empty" : `${S.list.length} ${S.list.length === 1 ? "entry" : "entries"}, sealed`),
        h("p", { class: "prose" }, empty
          ? "Start with the account you use most. MyVault keeps logins, API keys, SSH keys and private notes, all encrypted on this computer."
          : "Pick one on the left, or search. Secret values stay covered until you reveal them."),
        empty ? btn("Add your first entry", () => showNew(), "primary", "plus") : null,
        h("div", { class: "keys" },
          h("span", {}, h("kbd", { class: "k" }, "Ctrl"), " ", h("kbd", { class: "k" }, "F"), " search"),
          h("span", {}, h("kbd", { class: "k" }, "Ctrl"), " ", h("kbd", { class: "k" }, "N"), " new login"),
          h("span", {}, h("kbd", { class: "k" }, "Ctrl"), " ", h("kbd", { class: "k" }, "L"), " lock")))));
  }

  // ---- view an entry -----------------------------------------------------
  function secretView(value, multi) {
    const text = h(multi ? "pre" : "span", { class: "secret-text" });
    const veil = h("span", { class: "veil", "aria-hidden": "true" });
    const box = h("span", { class: "secret" + (multi ? " multi" : ""), "data-state": "sealed",
      role: "img", "aria-label": "Hidden value" }, text, veil);
    let timer;
    box.open = () => {
      text.replaceChildren(...colorize(value));
      box.dataset.state = "open";
      box.removeAttribute("role");
      box.removeAttribute("aria-label");
      clearTimeout(timer);
      timer = setTimeout(box.seal, 20000);
    };
    box.seal = () => {
      box.dataset.state = "sealed";
      box.setAttribute("role", "img");
      box.setAttribute("aria-label", "Hidden value");
      clearTimeout(timer);
      setTimeout(() => { if (box.dataset.state === "sealed") text.textContent = ""; }, 240);
      box.onseal && box.onseal();
    };
    return box;
  }
  function colorize(pw) {
    // digits in envelope blue, symbols bold: easier to read back character by character
    // (text nodes made here, never strings through h(): a secret must never be translated)
    const ch = (c) => document.createTextNode(c);
    return [...pw].map((c) => /[0-9]/.test(c) ? h("span", { class: "digit" }, ch(c))
      : /[^A-Za-z0-9\s]/.test(c) ? h("span", { class: "sym" }, ch(c)) : ch(c));
  }

  function fieldRow(f, value) {
    const multi = !!f.multi;
    let valEl, revealBtn;
    if (f.secret) {
      valEl = secretView(value, multi);
      revealBtn = h("button", { type: "button", class: "btn icon ghost sm", "aria-pressed": "false", title: `Show ${f.label.toLowerCase()}`,
        "aria-label": `Show ${f.label.toLowerCase()}` }, icon("eye"));
      const sync = (open) => {
        revealBtn.setAttribute("aria-pressed", String(open));
        revealBtn.replaceChildren(icon(open ? "eyeoff" : "eye"));
      };
      valEl.onseal = () => sync(false);
      revealBtn.addEventListener("click", () => {
        if (valEl.dataset.state === "open") valEl.seal(); else { valEl.open(); sync(true); }
      });
    } else {
      valEl = h(multi ? "pre" : "span", { class: "val-plain" + (f.mono || (multi && !f.prose) ? " mono" : "") }, raw(value));
      if (multi) valEl.style.margin = "0";
    }
    return h("div", { class: "row" + (multi ? " multi" : "") },
      h("dt", {}, f.label), h("dd", {}, valEl),
      h("div", { class: "acts" }, revealBtn, iconBtn("copy", `Copy ${f.label.toLowerCase()}`, () => copy(value, f.label))));
  }

  async function openEntry(id, keepFocus = false) {
    const e = await call("entry", id);
    if (!e) { await refresh(); return showHome(); }
    S.view = "entry";
    S.selected = id;
    markTool(null);
    renderList();
    const sel = document.querySelector(`.item[data-id="${CSS.escape(id)}"]`);
    if (sel) sel.scrollIntoView({ block: "nearest" });
    if (keepFocus) $("#list").focus();
    renderView(e);
  }

  // Auto-type: name the program first, then type only after the user confirms.
  async function askAutotype(e, box) {
    const t = await call("autotype_target");
    if (!t.ok) {
      box.replaceChildren(h("div", { class: "result bad" }, t.error,
        h("p", { class: "hint", style: "margin:6px 0 0" }, "How it works: click the username box in the other program, switch back to MyVault, then choose Type into app.")));
      return;
    }
    const go = async (mode) => {
      box.replaceChildren(h("div", { class: "result" }, "Typing…"));
      const r = await call("autotype", e.id, mode);
      box.replaceChildren(h("div", { class: "result" + (r.ok ? "" : " bad") },
        r.ok ? `Typed into “${t.title}”. Press Enter there to sign in.` : r.error));
    };
    box.replaceChildren(h("div", { class: "panel", style: "margin-top:14px" },
      h("p", { class: "prose", style: "margin:0" }, "Type into ", h("b", {}, raw(t.title)), "?"),
      h("p", { class: "hint" }, "MyVault will step aside and type into the box you last clicked there. Make sure that's the username box."),
      h("div", { class: "updrow", style: "display:flex;gap:8px;flex-wrap:wrap" },
        btn("Username + password", () => go("both"), "primary sm"),
        btn("Password only", () => go("password"), "sm"),
        btn("Cancel", () => box.replaceChildren(), "sm"))));
  }

  function renderView(e) {
    const typeBox = h("div", { "aria-live": "polite" });
    const K = KINDS[e.kind] || KINDS.login;
    const rows = [...K.fields, ...(K.more || [])].map((f) => [f, getVal(e, f)]).filter(([, v]) => v);
    const custom = Object.entries(e.custom || {});
    const where = e.kind === "login" ? e.website : e.fields?.service;
    sheet(h("article", { class: "page" },
      h("header", { class: "page-head" }, h("span", { class: "glyph" }, icon(e.kind)),
        h("div", { class: "ttl" }, h("h2", {}, e.title ? raw(e.title) : "(untitled)"), h("p", { class: "byline" }, K.label, where && [" · ", raw(where)])),
        h("div", { class: "head-acts" },
          e.kind === "login" && e.password && btn("Type into app", () => askAutotype(e, typeBox), "", "keyboard"),
          btn("Edit", () => renderEdit(e), "", "edit"))),
      typeBox,
      rows.length || e.notes ? h("dl", { class: "fields" }, rows.map(([f, v]) => fieldRow(f, v)),
        e.kind !== "note" && !!e.notes && fieldRow(F("notes", "Notes", { multi: 1, prose: 1 }), e.notes))
        : h("p", { class: "prose" }, "Nothing stored here yet. Choose Edit to add details."),
      custom.length > 0 && [h("p", { class: "section-t" }, "Extra fields"),
        h("dl", { class: "fields", style: "margin-top:8px" }, custom.map(([k, v]) => fieldRow(F(k, k), v)))],
      h("p", { class: "meta" }, `Last changed ${fmtDate(e.updated_at)} · Created ${fmtDate(e.created_at)}`)));
  }
  const fmtDate = (t) => new Date(t * 1000).toLocaleDateString(LOCALE, { day: "numeric", month: "short", year: "numeric" });

  // ---- new / edit --------------------------------------------------------------
  function showNew() {
    S.view = "new";
    S.selected = null;
    markTool(null);
    renderList();
    sheet(h("section", { class: "page" },
      h("h2", {}, "What are you adding?"),
      h("div", { class: "kinds" }, Object.entries(KINDS).map(([k, v]) =>
        h("button", { type: "button", class: "kind-card", onclick: () => renderEdit({ kind: k, fields: {}, custom: {} }) },
          h("span", { class: "glyph" }, icon(k)), h("span", {}, h("b", {}, v.label), h("span", { class: "d" }, v.desc)))))));
  }

  function strengthLine() {
    const meter = h("span", { class: "meter", "data-level": "0" }, h("i"), h("i"), h("i"), h("i"));
    const label = h("span", {});
    const box = h("div", { class: "strength", "aria-live": "polite" }, meter, label);
    const LV = { "": 0, Weak: 1, Okay: 2, Strong: 3, "Very strong": 4 };
    let n = 0;
    box.set = async (pw) => {
      const mine = ++n;
      const s = pw ? await call("strength", pw) : "";
      if (mine !== n) return;
      meter.dataset.level = String(LV[s] || 0);
      label.textContent = s ? t(`Strength: ${s}`) : "";
    };
    return box;
  }

  function secretInput(f, value, onChange) {
    const multi = !!f.multi;
    const inp = multi
      ? h("textarea", { class: "inp mono concealed", rows: 5, spellcheck: "false", "aria-label": f.label })
      : h("input", { class: "inp mono", type: "password", spellcheck: "false", autocomplete: "off", "aria-label": f.label });
    inp.value = value;
    inp.addEventListener("input", onChange);
    const eye = h("button", { type: "button", class: "btn icon sm", "aria-pressed": "false", title: "Show", "aria-label": `Show ${f.label.toLowerCase()}` }, icon("eye"));
    eye.addEventListener("click", () => {
      const show = eye.getAttribute("aria-pressed") !== "true";
      eye.setAttribute("aria-pressed", String(show));
      eye.replaceChildren(icon(show ? "eyeoff" : "eye"));
      if (multi) inp.classList.toggle("concealed", !show); else inp.type = show ? "text" : "password";
    });
    eye.show = () => { if (eye.getAttribute("aria-pressed") !== "true") eye.click(); };
    return { inp, eye };
  }

  function renderEdit(e) {
    const isNew = !e.id;
    const K = KINDS[e.kind] || KINDS.login;
    S.view = "edit";
    S.dirty = false;
    const dirty = () => { S.dirty = true; };
    const inputs = [];          // [fieldDef, element]
    let policy = { ...(e.password_policy || {}) };

    const title = h("input", { class: "inp", value: e.title || "", oninput: dirty, "aria-label": "Name",
      placeholder: e.kind === "login" ? "e.g. Netflix" : e.kind === "api" ? "e.g. Weather app production key" : e.kind === "ssh" ? "e.g. Home server" : "e.g. Bank recovery codes" });

    function control(f) {
      const value = getVal(e, f);
      if (f.secret) {
        const { inp, eye } = secretInput(f, value, dirty);
        inputs.push([f, inp]);
        const parts = [inp, eye];
        let meter = null, genBox = null;
        if (f.gen) {
          // A password already in the box is never one stray click from being
          // replaced: "Generate" only shows while the box is empty. Otherwise
          // "Change password" asks first, and a saved one can be put back.
          const saved = value;
          let choice = null;
          const strength = strengthLine();
          const close = () => { genBox?.remove(); choice?.remove(); genBox = choice = null; };
          const openGen = () => {
            close();
            genBox = generatorPanel(policy, {
              onUse: (pw, pol) => { inp.value = pw; policy = pol; eye.show(); dirty(); close(); sync(); },
            });
            wrap.append(genBox);
          };
          const genBtn = btn("Generate", () => (genBox ? close() : openGen()), "sm", "dice");
          const changeBtn = btn("Change password", () => {
            if (choice) return close();
            close();
            choice = h("div", { class: "result bad", role: "alert", style: "margin-top:10px;display:grid;gap:10px" },
              h("span", {}, h("b", {}, "Replace this password? "), saved
                ? "Once you save, the old one is gone for good. Change it on the website or app as well, or you could lock yourself out."
                : "The password in the box will be replaced."),
              h("div", { class: "inp-row", style: "flex-wrap:wrap" },
                btn("Type a new one", () => { close(); inp.readOnly = false; inp.value = ""; dirty(); sync(); inp.focus(); }, "sm", "edit"),
                btn("Generate one", openGen, "sm", "dice"),
                btn("Keep it", close, "sm")));
            wrap.append(choice);
          }, "sm", "refresh");
          const undo = btn("Keep the old password", () => {
            close(); inp.value = saved; inp.readOnly = true; sync(); toast("The saved password is back.");
          }, "sm", "x");
          function sync() {
            strength.set(inp.value);
            genBtn.hidden = inp.value !== "";
            changeBtn.hidden = inp.value === "";
            undo.hidden = !saved || inp.value === saved;
          }
          inp.readOnly = !!saved;      // the saved password can be viewed and copied, not edited by accident
          inp.addEventListener("input", sync);
          parts.push(genBtn, changeBtn);
          meter = h("div", {}, strength, h("div", { style: "margin-top:8px" }, undo));
          sync();
        }
        if (f.file) parts.push(fileBtn(inp));
        const wrap = h("div", { class: "field" }, h("label", {}, f.label),
          h("div", { class: "inp-row", style: f.multi ? "align-items:start" : "" }, parts), meter);
        return wrap;
      }
      const inp = f.multi
        ? h("textarea", { class: "inp mono", rows: 4, spellcheck: "false", oninput: dirty, "aria-label": f.label })
        : h("input", { class: "inp" + (f.mono ? " mono" : ""), type: f.type || "text", placeholder: f.ph || "", oninput: dirty,
          spellcheck: "false", "aria-label": f.label });
      inp.value = value;
      inputs.push([f, inp]);
      return h("div", { class: "field" }, h("label", {}, f.label),
        f.file ? h("div", { class: "inp-row", style: "align-items:start" }, inp, fileBtn(inp)) : inp);
    }
    function fileBtn(target) {
      return btn("From file…", async () => {
        const r = await call("read_text_file");
        if (r.ok) { target.value = r.text; dirty(); toast(`Loaded ${r.name}.`); } else if (r.error) toast(r.error, true);
      }, "sm", "file");
    }

    const extraBox = h("div", { class: "form", style: "margin-top:0;gap:8px" });
    const addExtra = (k = "", v = "") => {
      const row = h("div", { class: "extra-row" },
        h("input", { class: "inp", value: k, placeholder: "Label", oninput: dirty, "aria-label": "Extra field label" }),
        h("input", { class: "inp", value: v, placeholder: "Value", oninput: dirty, "aria-label": "Extra field value" }),
        iconBtn("x", "Remove field", () => { row.remove(); dirty(); }));
      extraBox.append(row);
    };
    Object.entries(e.custom || {}).forEach(([k, v]) => addExtra(k, v));

    const notes = e.kind !== "note" && h("textarea", { class: "inp", rows: 3, oninput: dirty, "aria-label": "Notes" });
    if (notes) notes.value = e.notes || "";
    const moreFilled = (K.more || []).some((f) => getVal(e, f));
    const err = h("p", { class: "err", role: "alert" });

    async function save() {
      const out = { id: e.id || "", kind: e.kind, title: title.value, custom: {}, fields: { ...(e.fields || {}) }, password_policy: policy };
      for (const [f, el] of inputs) {
        if (f.top) out[f.key] = el.value; else out.fields[f.key] = el.value;
      }
      for (const k of Object.keys(out.fields)) if (!out.fields[k]) delete out.fields[k];
      if (notes) out.notes = notes.value;
      extraBox.querySelectorAll(".extra-row").forEach((r) => {
        const [k, v] = r.querySelectorAll("input");
        if (k.value.trim()) out.custom[k.value.trim()] = v.value;
      });
      const r = await call("save_entry", out);
      if (!r.ok) { err.textContent = t(r.error); return; }
      S.dirty = false;
      toast(isNew ? "Saved to your vault." : "Changes saved.");
      await refresh();
      openEntry(r.id);
    }
    function cancel() {
      S.dirty = false;
      if (isNew) showHome(); else openEntry(e.id);
    }

    const del = !isNew && h("div", { class: "confirm" });
    const showDelete = () => {
      del.replaceChildren(btn("Delete", () => {
        del.replaceChildren(h("span", {}, "Delete for good?"),
          btn("Delete", async () => { await call("delete_entry", e.id); S.dirty = false; toast("Deleted."); await refresh(); showHome(); }, "danger solid sm"),
          btn("Keep it", showDelete, "sm"));
      }, "danger", "trash"));
    };
    if (del) showDelete();

    const page = h("form", { class: "page", onsubmit: (ev) => { ev.preventDefault(); save(); } },
      h("header", { class: "page-head" }, h("span", { class: "glyph" }, icon(e.kind)),
        h("div", { class: "ttl" }, h("h2", {}, isNew ? `New ${K.label.toLowerCase()}` : `Edit ${e.title || K.label.toLowerCase()}`),
          h("p", { class: "byline" }, K.desc))),
      h("div", { class: "form" },
        h("div", { class: "field" }, h("label", {}, "Name"), title),
        K.fields.map(control),
        K.more && h("details", { class: "more", open: moreFilled || null },
          h("summary", {}, icon("chev"), "Profile details (app, phone, region, age, gender)"),
          h("div", { class: "form two" }, K.more.map(control))),
        notes && h("div", { class: "field" }, h("label", {}, "Notes"), notes),
        h("div", { class: "field" }, h("span", { class: "lbl" }, "Extra fields"),
          h("p", { class: "hint" }, "Security questions, PINs, membership numbers, anything else."),
          extraBox, h("div", {}, btn("Add field", () => { addExtra(); dirty(); }, "sm", "plus")))),
      err,
      h("div", { class: "actionbar" },
        h("button", { type: "submit", class: "btn primary" }, icon("check"), "Save"),
        btn("Cancel", cancel), h("span", { class: "spacer" }), del));
    page.addEventListener("keydown", (ev) => {
      if (ev.key === "Escape" && !S.dirty) { ev.preventDefault(); cancel(); }
    });
    page.save = save;
    sheet(page);
    title.focus();
    if (isNew) title.select();
  }

  // ---- generator ------------------------------------------------------------
  const DEFAULT_POLICY = { length: 20, use_upper: true, use_lower: true, use_digits: true, use_symbols: true,
    avoid_ambiguous: true, allowed_symbols: "!@#$%^&*-_=+?" };

  function generatorPanel(initial, { onUse, big = false } = {}) {
    const p = { ...DEFAULT_POLICY, ...initial };
    const out = h("span", { class: "pw", "aria-live": "polite" });
    const meter = strengthLine();
    let current = "";
    async function regen() {
      const r = await call("generate", p);
      if (!r.ok) {
        current = "";
        out.textContent = t("Turn on at least one kind of character.");
        meter.set("");
        return;
      }
      current = r.password;
      out.replaceChildren(...colorize(current));
      meter.set(current);
    }
    const num = h("input", { class: "inp", type: "number", min: 6, max: 128, value: p.length, "aria-label": "Length" });
    const range = h("input", { type: "range", min: 6, max: 128, value: p.length, "aria-label": "Password length" });
    const paint = () => range.style.setProperty("--fill", `${((p.length - 6) / 122) * 100}%`);
    const setLen = (v) => { p.length = Math.max(6, Math.min(128, parseInt(v, 10) || 6)); range.value = p.length; num.value = p.length; paint(); regen(); };
    range.addEventListener("input", () => setLen(range.value));
    num.addEventListener("change", () => setLen(num.value));
    paint();
    const sw = (key, label, sub) => {
      const inp = h("input", { type: "checkbox", role: "switch", checked: !!p[key] });
      inp.addEventListener("change", () => { p[key] = inp.checked; regen(); });
      return h("label", { class: "switch" }, inp, h("span", { class: "sw-text" }, h("span", {}, label), sub && h("span", { class: "sw-sub" }, sub)));
    };
    const syms = h("input", { class: "inp mono", value: p.allowed_symbols, "aria-label": "Allowed symbols", style: "height:32px" });
    syms.addEventListener("input", () => { p.allowed_symbols = syms.value; regen(); });
    const box = h("div", { class: "gen" + (big ? " big" : "") },
      h("div", { class: "gen-out" }, out,
        iconBtn("refresh", "New password", regen),
        iconBtn("copy", "Copy password", () => copy(current, "Password"))),
      meter,
      h("div", { class: "len" }, h("span", { class: "lbl" }, "Length"), range, num),
      h("div", { class: "toggles" },
        sw("use_upper", "Uppercase letters", "A–Z"), sw("use_lower", "Lowercase letters", "a–z"),
        sw("use_digits", "Numbers", "0–9"), sw("use_symbols", "Symbols", "! @ # $ …"),
        sw("avoid_ambiguous", "Avoid look-alikes", "No l, 1, O, 0, I")),
      h("div", { class: "field" }, h("label", {}, "Symbols to use"), syms),
      onUse && h("div", {}, btn("Use this password", () => current && onUse(current, { ...p }), "primary sm", "check")));
    regen();
    return box;
  }

  // ---- tools -------------------------------------------------------------------
  function showTool(id) {
    S.view = "tool";
    S.selected = null;
    renderList();
    markTool(id);
    ({ generator: toolGenerator, sync: toolSync, backup: toolBackup, browser: toolBrowser, settings: toolSettings })[id]();
  }
  const toolHead = (ic, t, lede) => h("header", { class: "page-head" }, h("span", { class: "glyph" }, icon(ic)),
    h("div", { class: "ttl" }, h("h2", {}, t), lede && h("p", { class: "byline" }, lede)));

  function toolGenerator() {
    sheet(h("section", { class: "page" },
      toolHead("dice", "Password generator", "Random, from this computer's secure random source. Nothing is saved unless you copy or use it."),
      h("div", { style: "margin-top:22px" }, generatorPanel({}, { big: true }))));
  }

  function stopSync() {
    if (S.syncTimer) { clearInterval(S.syncTimer); S.syncTimer = null; call("sync_cancel").catch(() => {}); }
  }

  function toolSync() {
    const area = h("div", { class: "panel" });
    sheet(h("section", { class: "page" },
      toolHead("phone", "Sync with phone", "Your PC and phone swap changes directly over your WiFi. No cloud is involved."),
      h("ol", { class: "steps", style: "margin-top:18px" },
        h("li", {}, "Open MyVault on your phone and unlock it."),
        h("li", {}, "Tap the sync button, then scan the code below."),
        h("li", {}, "Both devices end up with the newest version of every entry.")),
      area,
      h("ul", { class: "facts", style: "margin-top:22px" },
        h("li", {}, icon("shield"), h("span", {}, h("b", {}, "The code is the key. "), "It holds a one-time random key that only travels through the camera, so nobody else on the WiFi can read the sync.")),
        h("li", {}, icon("wifi"), h("span", {}, h("b", {}, "Same WiFi only. "), "The PC listens only while this code is showing, for 2 minutes at most, then stops.")),
        h("li", {}, icon("gear"), h("span", {}, h("b", {}, "On Windows: "), "your home WiFi must be set to Private (Settings › Network & internet › Wi‑Fi). If Windows asks whether MyVault may use the network, allow it on private networks.")))));
    idle();

    function versionNote(s) {
      const older = (a, b) => cmpVer(a, b) < 0;
      if (!s.peer_version) return [" Your phone runs an older MyVault (before 0.5) that can't take updates over sync. ",
        "Install the new phone app once from the MyVault folder (Settings › Folders › MyVault program › packages)."];
      if (s.received) return ` Your phone had a newer MyVault (${s.received}) and passed it to this PC. Install it from the card on the left.`;
      if (older(s.version, s.peer_version)) return [` Your phone has MyVault ${s.peer_version}; this PC has ${s.version}.`,
        s.update_error ? ` The update couldn't be passed over: ${s.update_error}` : " Update this PC when you can."];
      if (s.sent) return ` Your phone had MyVault ${s.peer_version}, so this PC sent it ${s.sent}. Tap Install on the phone.`;
      if (older(s.peer_version, s.version)) return ` Your phone runs MyVault ${s.peer_version} (this PC has ${s.version}). Update the phone when you can.`;
      return "";
    }

    function idle(msg, bad = false) {
      area.replaceChildren(h("div", { style: "display:grid;gap:12px" },      // h() drops an empty msg; replaceChildren would print "undefined"
        msg && h("div", { class: "result" + (bad ? " bad" : "") }, msg),
        h("div", {}, btn(msg ? "Show a new code" : "Show sync code", start, "primary", "phone"))));
    }
    async function start() {
      const r = await call("sync_start");
      if (!r.ok) return idle(r.error, true);
      const qr = h("div", { class: "qr", role: "img", "aria-label": "Sync code" });
      qr.innerHTML = r.svg;          // generated by segno in Python from our own URI
      const bar = h("i", {});
      const status = h("div", { class: "status" }, h("span", { class: "dot wait" }), "Waiting for your phone…");
      const left = h("p", { class: "hint" });
      area.replaceChildren(...[r.public && h("div", { class: "result bad", role: "alert" },
        h("b", {}, "Windows is blocking your phone. "),
        "It treats this WiFi as a Public network, so it drops the phone's connection. On your home WiFi, open ",
        h("b", {}, "Settings › Network & internet › Wi‑Fi › (your network)"), " and set ",
        h("b", {}, "Network profile type"), " to ", h("b", {}, "Private"), ", then show a new code. ",
        "Keep café and airport WiFi on Public: there, blocking is what you want."),
      h("div", { class: "qr-window" }, qr,
        h("div", { style: "display:grid;gap:10px" }, status, left, h("div", { class: "countdown" }, bar),
          h("p", { class: "hint" }, `This PC: ${r.hosts.join(", ")}`),
          h("div", {}, btn("Cancel", () => { stopSync(); idle(); }, "sm"))))].filter(Boolean));
      S.syncTimer = setInterval(async () => {
        const s = await call("sync_status");
        if (s.state === "waiting") {
          left.textContent = t(`Code expires in ${Math.floor(s.seconds_left / 60)}:${String(s.seconds_left % 60).padStart(2, "0")}`);
          bar.style.transform = `scaleX(${s.seconds_left / r.ttl})`;
          return;
        }
        clearInterval(S.syncTimer);
        S.syncTimer = null;
        if (s.state === "done") {
          await refresh();
          idle([`Synced. ${s.changed} ${s.changed === 1 ? "entry" : "entries"} updated on this PC. Your phone has the rest.`,
            versionNote(s)]);
          refreshUpdates();
        } else {
          idle("The code expired before a phone connected. Show a new one when you're ready.", true);
        }
      }, 1000);
    }
  }

  function pwPair(label1, label2) {
    const a = h("input", { class: "inp", type: "password", "aria-label": label1, placeholder: label1 });
    const b = label2 && h("input", { class: "inp", type: "password", "aria-label": label2, placeholder: label2 });
    return [a, b];
  }

  function toolBackup() {
    const [e1, e2] = pwPair("Backup password", "Type it again");
    const eErr = h("div");
    const [r1] = pwPair("Backup password");
    const rErr = h("div");
    sheet(h("section", { class: "page" },
      toolHead("printer", "Paper backup", "A printable PDF of your whole vault where nothing can be read, not even the site names."),
      h("div", { class: "panel" },
        h("h3", {}, "Make a backup PDF"),
        h("p", { class: "prose", style: "margin:0" }, "Every entry is printed as a block of encrypted text and a QR code. Print it and keep it somewhere safe. Only the backup password can open it, so keep that password away from the paper."),
        h("div", { class: "two form", style: "margin:0" }, e1, e2),
        eErr,
        h("div", {}, btn("Save PDF…", async () => {
          eErr.replaceChildren();
          if (e1.value.length < 8) return eErr.append(h("p", { class: "err" }, "Use at least 8 characters for the backup password."));
          if (e1.value !== e2.value) return eErr.append(h("p", { class: "err" }, "The two passwords don't match."));
          const r = await call("backup_export", e1.value);
          if (r.ok) { e1.value = e2.value = ""; eErr.append(h("div", { class: "result" }, `Saved ${r.count} entries to ${r.path}. Print it, then delete the file if you only want the paper copy.`)); }
          else if (r.error) eErr.append(h("p", { class: "err" }, r.error));
        }, "primary", "printer"))),
      h("div", { class: "panel" },
        h("h3", {}, "Restore from a backup PDF"),
        h("p", { class: "prose", style: "margin:0" }, "Entries from the backup are merged into this vault. If an entry exists in both, the newer version is kept. To restore from paper only, use the phone app: Restore from paper, then scan each code."),
        h("div", { style: "max-width:340px" }, r1),
        rErr,
        h("div", {}, btn("Choose PDF…", async () => {
          rErr.replaceChildren();
          if (!r1.value) return rErr.append(h("p", { class: "err" }, "Enter the backup password first."));
          const r = await call("backup_import", r1.value);
          if (r.ok) {
            r1.value = "";
            await refresh();
            const changed = r.added || r.restored || r.updated;
            rErr.append(h("div", { class: "result" }, [
              `Entries read from the backup: ${r.found}.`,
              r.added && ` Added: ${r.added}.`,
              r.restored && ` Brought back after being deleted: ${r.restored}.`,
              r.updated && ` Updated to the backup's newer copy: ${r.updated}.`,
              !changed && " Everything in it was already in your vault, so nothing changed.",
              changed && r.unchanged && ` Already up to date: ${r.unchanged}.`,
              r.unreadable && ` Blocks that couldn't be read: ${r.unreadable}.`]));
          } else if (r.error) rErr.append(h("div", { class: "result bad" }, r.error));
        }, "", "file")))));
  }

  async function toolBrowser() {
    const info = await call("connector_info");
    const token = secretView(info.token, false);
    const eye = h("button", { type: "button", class: "btn icon ghost sm", "aria-label": "Show token", title: "Show token" }, icon("eye"));
    eye.addEventListener("click", () => token.dataset.state === "open" ? token.seal() : token.open());
    const regenBox = h("div");
    const askRegen = () => regenBox.replaceChildren(btn("New pairing token", () => {
      regenBox.replaceChildren(h("div", { class: "confirm" }, h("span", {}, "The extension stops working until you paste the new token."),
        btn("Make new token", async () => { await call("regen_token"); toast("New token made. Paste it into the extension."); toolBrowser(); }, "danger solid sm"),
        btn("Cancel", askRegen, "sm")));
    }, "sm"));
    askRegen();
    sheet(h("section", { class: "page" },
      toolHead("globe", "Browser auto-fill", "Fill logins with one click and save new ones as you sign up. Works in Chrome, Edge, Brave and Comet."),
      h("div", { class: "panel" },
        h("div", { class: "status" }, h("span", { class: "dot " + (info.running ? "on" : "off") }),
          info.running ? `Connector running on this computer only (127.0.0.1:${info.port})` : "Connector not running. Another app may be using its port."),
        h("ol", { class: "steps" },
          h("li", {}, "In your browser, open the Extensions page (type chrome://extensions, or comet://extensions in Comet) and turn on Developer mode."),
          h("li", {}, "Copy the extension folder path below. Choose “Load unpacked”, paste the path into the folder box at the top of the window, press Enter, then choose Select Folder. It's the folder with manifest.json inside."),
          h("li", {}, "Open the MyVault extension's settings, paste the pairing token, then choose Save & test.")),
        h("div", { class: "field" }, h("span", { class: "lbl" }, "Extension folder"),
          h("div", { class: "inp-row" }, h("span", { class: "pathline" }, raw(info.extension_dir)),
            btn("Open folder", () => openFolder("extension"), "sm", "folder"),
            iconBtn("copy", "Copy folder path", async () => { await call("copy_plain", info.extension_dir); toast("Folder path copied."); }))),
        h("div", { class: "field" }, h("span", { class: "lbl" }, "Pairing token"),
          h("div", { class: "inp-row" }, token, eye,
            iconBtn("copy", "Copy token", () => copy(info.token, "Token")))),
        regenBox),
      h("ul", { class: "facts", style: "margin-top:22px" },
        h("li", {}, icon("shield"), h("span", {}, h("b", {}, "Fills only when you click. "), "Click a login box and pick the account. Nothing is filled on its own.")),
        h("li", {}, icon("dice"), h("span", {}, h("b", {}, "Sign-up help. "), "On a registration form, click the password box to get a strong suggested password, then save the new account when you submit.")),
        h("li", {}, icon("lock"), h("span", {}, h("b", {}, "Only while unlocked. "), "When MyVault is locked or closed, the extension can't read anything.")))));
  }

  async function openFolder(which) {
    const r = await call("open_folder", which);
    if (!r.ok) toast(r.error, true);
  }
  function folderRow(title, about, which, path) {
    return h("div", { class: "field folder-row" },
      h("span", { class: "lbl" }, title),
      h("p", { class: "hint" }, about),
      h("div", { class: "inp-row" }, h("span", { class: "pathline" }, raw(path)),
        btn("Open folder", () => openFolder(which), "sm", "folder"),
        iconBtn("copy", `Copy ${title.toLowerCase()} path`, async () => { await call("copy_plain", path); toast("Path copied."); })));
  }

  function languagePanel() {
    const panel = h("div", { class: "panel" }, h("h3", {}, "Language"));
    (async () => {
      const l = await call("language_state");
      // Each language is named in itself, so it can be found whichever one is showing.
      const sel = h("select", { class: "inp", "aria-label": "Language", style: "max-width:220px" },
        [["auto", "Same as Windows"], ["en", "English"], ["ar", "العربية"]]
          .map(([v, name]) => h("option", { value: v, selected: v === l.pick || null }, name)));
      sel.addEventListener("change", () => call("set_language", sel.value));
      panel.append(sel, h("p", { class: "hint" }, "The phone app and the browser extension have their own language settings."));
    })();
    return panel;
  }

  function autolockPanel() {
    const panel = h("div", { class: "panel" }, h("h3", {}, "Auto-lock"));
    (async () => {
      const a = await call("autolock_state");
      const sel = h("select", { class: "inp", "aria-label": "Lock after", style: "max-width:220px" },
        a.choices.map((m) => h("option", { value: m, selected: m === a.minutes || null }, m === 60 ? "1 hour" : `${m} minute${m === 1 ? "" : "s"}`)));
      sel.addEventListener("change", async () => {
        const r = await call("set_autolock", Number(sel.value));
        toast(`MyVault will lock after ${r.minutes === 60 ? "1 hour" : `${r.minutes} minute${r.minutes === 1 ? "" : "s"}`} without use.`);
      });
      panel.append(h("p", { class: "prose", style: "margin:0" }, "Lock MyVault when it hasn't been used for:"), sel,
        h("p", { class: "hint" }, "Shorter is safer, especially on a shared computer. The X button keeps MyVault running by the clock (so browser fill works); the timer still locks it, and you can lock or quit from the icon there."));
    })();
    return panel;
  }

  function startupPanel() {
    const panel = h("div", { class: "panel" }, h("h3", {}, "Start with Windows"));
    (async () => {
      const a = await call("autostart_state");
      const sw = h("input", { type: "checkbox", role: "switch", checked: a.enabled, disabled: !a.available });
      sw.addEventListener("change", async () => {
        const r = await call("set_autostart", sw.checked);
        sw.checked = r.enabled;
        toast(r.enabled ? "MyVault will start when you sign in to Windows." : "MyVault won't start on its own.");
      });
      panel.append(h("label", { class: "switch" }, sw, h("span", { class: "sw-text" },
        h("span", {}, "Start MyVault when I sign in to Windows"),
        h("span", { class: "sw-sub" }, a.available
          ? "It waits by the clock (in the notification area), locked, until you open it. Also listed in Windows Settings › Apps › Startup."
          : "Available in the installed app (MyVault-Setup), not when run from source."))));
    })();
    return panel;
  }

  function updatesPanel() {
    const panel = h("div", { class: "panel" }, h("h3", {}, "Updates"));
    const paint = async () => {
      const u = await call("update_state");
      const sw = h("input", { type: "checkbox", role: "switch", checked: u.enabled });
      sw.addEventListener("change", async () => { await call("set_update_check", sw.checked); paint(); refreshUpdates(); });
      const when = u.last_check ? new Date(u.last_check * 1000).toLocaleString(LOCALE, { dateStyle: "medium", timeStyle: "short" }) : "never";
      panel.replaceChildren(h("h3", {}, "Updates"),
        h("p", { class: "prose", style: "margin:0" }, `This is MyVault ${u.current}. Updates also arrive offline: when you sync, a newer phone or PC hands its update over.`),
        h("label", { class: "switch" }, sw, h("span", { class: "sw-text" }, h("span", {}, "Let me know when a new version is out"),
          h("span", { class: "sw-sub" }, "MyVault looks at a small signed version file on GitHub, at most once a day. Nothing from your vault is sent."))),
        h("p", { class: "hint" }, u.checking ? "Checking…" : u.error ? u.error
          : u.available ? `MyVault ${u.available} is available. See the card on the left.` : `Last checked: ${when}.`),
        u.enabled && h("div", {}, btn("Check now", async () => { await call("check_updates", true); paint(); setTimeout(paint, 2500); setTimeout(refreshUpdates, 2600); }, "sm", "refresh")),
        goBack());
    };
    // If an update causes trouble: reinstall the stable release before this one.
    function goBack() {
      const slot = h("div", {});
      const box = h("div", { style: "display:grid;gap:8px;margin-top:16px;padding-top:16px;border-top:1px solid var(--rule)" },
        h("b", {}, "Go back to the previous version"),
        h("p", { class: "hint", style: "margin:0" }, "If an update causes trouble, MyVault can reinstall the stable release before it. Only versions signed by MyVault are offered, and your vault is copied first."),
        slot);
      const idle = () => slot.replaceChildren(btn("Find the previous version", find, "sm", "refresh"));
      async function find() {
        slot.replaceChildren(h("span", { class: "hint" }, "Looking on GitHub…"));
        const r = await call("rollback_info");
        if (!r.ok) return slot.replaceChildren(h("p", { class: "err", style: "margin:0 0 8px" }, r.error), btn("Try again", find, "sm"));
        slot.replaceChildren(h("div", { class: "result bad", role: "alert", style: "display:grid;gap:10px" },
          h("span", {}, h("b", {}, `Go back from ${r.current} to ${r.version}? `),
            `MyVault first copies your vault to ${r.backup} in your vault folder, then downloads ${r.version}, checks its signature, installs it and opens again. `,
            `Updates are never installed without asking, so you can choose Later if it offers ${r.current} again.`),
          h("div", { class: "inp-row", style: "flex-wrap:wrap" },
            btn(`Go back to ${r.version}`, async () => {
              slot.replaceChildren(h("span", { class: "hint" }, `Downloading and checking ${r.version}…`));
              const x = await call("rollback");
              if (!x.ok) slot.replaceChildren(h("p", { class: "err", style: "margin:0 0 8px" }, x.error), btn("Try again", find, "sm"));
            }, "primary sm"),
            btn("Cancel", idle, "sm"))));
      }
      idle();
      return box;
    }
    paint();
    return panel;
  }

  async function toolSettings() {
    const dirs = await call("folders");
    const cur = h("input", { class: "inp", type: "password", placeholder: "Current master password", "aria-label": "Current master password" });
    const [n1, n2] = pwPair("New master password", "Type it again");
    const msg = h("div");
    sheet(h("section", { class: "page" },
      toolHead("gear", "Settings", `MyVault ${S.version}`),
      languagePanel(),
      h("div", { class: "panel" },
        h("h3", {}, "Change master password"),
        h("div", { style: "max-width:340px" }, cur),
        h("div", { class: "two form", style: "margin:0" }, n1, n2),
        msg,
        h("div", {}, btn("Change password", async () => {
          msg.replaceChildren();
          if (n1.value.length < 8) return msg.append(h("p", { class: "err" }, "Use at least 8 characters."));
          if (n1.value !== n2.value) return msg.append(h("p", { class: "err" }, "The new passwords don't match."));
          const r = await call("change_master", cur.value, n1.value);
          if (r.ok) { cur.value = n1.value = n2.value = ""; msg.append(h("div", { class: "result" }, "Master password changed. Use the new one next time you unlock.")); }
          else msg.append(h("p", { class: "err" }, r.error));
        }, "primary"))),
      autolockPanel(),
      startupPanel(),
      updatesPanel(),
      h("div", { class: "panel" },
        h("h3", {}, "Folders"),
        folderRow("Your vault", "The one encrypted file with everything in it. Copy it to a USB stick now and then; it's useless without your master password.", "data", dirs.data),
        folderRow("MyVault program", "Where the app itself is installed. Updating or uninstalling only touches this folder, never your vault.", "app", dirs.app),
        folderRow("Browser extension", "Pick this folder in your browser's “Load unpacked”.", "extension", dirs.extension)),
      h("div", { class: "panel" },
        h("h3", {}, "How MyVault protects you"),
        h("ul", { class: "facts" },
          h("li", {}, icon("lock"), h("span", {}, h("b", {}, "Encrypted file. "), "Your master password is stretched with scrypt and the vault is sealed with AES-256-GCM. The password itself is never stored.")),
          h("li", {}, icon("shield"), h("span", {}, h("b", {}, "Auto-lock. "), "MyVault locks itself after the time you pick above, even while it waits by the clock. Ctrl+L or the tray icon locks it at once.")),
          h("li", {}, icon("copy"), h("span", {}, h("b", {}, "Private clipboard. "), "Copied secrets skip Windows clipboard history and cloud sync, and clear after 30 seconds.")),
          h("li", {}, icon("wifi"), h("span", {}, h("b", {}, "No cloud. "), "Your vault is never sent to the internet. Sync happens only over your WiFi, after you scan a one-time code.")))),
      h("div", { class: "panel" },
        h("h3", {}, "About MyVault"),
        h("p", { class: "hint" }, "Made by Ahmed Mohammed. Free software under the GPL-3.0 licence. No account, no cloud, no tracking. Contact: ahmedmohammedkhear@gmail.com"),
        h("div", { class: "inp-row", style: "flex-wrap:wrap;gap:8px;margin-top:10px" },
          ...[["Privacy policy", "PRIVACY.md"], ["Terms of use", "TERMS.md"], ["Security", "SECURITY.md"], ["What's new", "CHANGELOG.md"]]
            .map(([t, f]) => btn(t, () => call("open_doc", f), "sm"))))));
  }

  // ---- global keys & activity ---------------------------------------------------
  document.addEventListener("keydown", (e) => {
    if (!$(".shell")) return;
    const ctrl = e.ctrlKey || e.metaKey;
    if (ctrl && e.key.toLowerCase() === "f") { e.preventDefault(); $("#search").focus(); $("#search").select(); }
    else if (ctrl && e.key.toLowerCase() === "n") { e.preventDefault(); guard(() => renderEdit({ kind: "login", fields: {}, custom: {} })); }
    else if (ctrl && e.key.toLowerCase() === "l") { e.preventDefault(); onLocked(); }
    else if (ctrl && e.key.toLowerCase() === "s" && S.view === "edit") { e.preventDefault(); $("form.page").save(); }
    else if (e.key === "/" && !/INPUT|TEXTAREA/.test(document.activeElement.tagName)) { e.preventDefault(); $("#search").focus(); }
  });
  // Caps Lock warning on any password field (the browser only reports the
  // state on key/pointer events, so the last one seen is used on focus).
  const capsTip = h("div", { class: "caps-tip", role: "status", "aria-live": "polite" }, icon("caps"), "Caps Lock is on");
  document.body.append(capsTip);
  let capsOn = false;
  function syncCaps(e) {
    if (e && typeof e.getModifierState === "function") capsOn = e.getModifierState("CapsLock");
    const t = document.activeElement;
    const secret = t && t.tagName && (t.type === "password" || t.classList.contains("concealed"));
    if (!secret || !capsOn) return capsTip.classList.remove("show");
    const r = t.getBoundingClientRect();
    capsTip.classList.add("show");
    capsTip.style.top = `${Math.round(r.top + (r.height - capsTip.offsetHeight) / 2)}px`;
    capsTip.style.left = `${Math.round(r.right - capsTip.offsetWidth - 8)}px`;
  }
  ["keydown", "keyup", "pointerdown"].forEach((ev) => document.addEventListener(ev, syncCaps, true));
  document.addEventListener("focusin", () => syncCaps());
  document.addEventListener("focusout", () => setTimeout(() => syncCaps()));
  window.addEventListener("resize", () => syncCaps());
  document.addEventListener("scroll", () => syncCaps(), true);

  let lastPing = 0;
  const ping = () => {
    const now = Date.now();
    if (now - lastPing > 15000 && $(".shell")) { lastPing = now; call("ping").catch(() => {}); }
  };
  ["keydown", "pointerdown", "pointermove", "wheel"].forEach((ev) => document.addEventListener(ev, ping, { passive: true }));
  // Never let the window navigate away (dropped files, stray links).
  ["dragover", "drop"].forEach((ev) => document.addEventListener(ev, (e) => e.preventDefault()));

  function cmpVer(a, b) {
    const pa = String(a || "0").split(".").map(Number), pb = String(b || "0").split(".").map(Number);
    for (let i = 0; i < 3; i++) if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) - (pb[i] || 0);
    return 0;
  }

  window.MV = { onLocked, refresh, updates: refreshUpdates };
  window.addEventListener("pywebviewready", async () => {
    const b = await call("boot");
    S.version = b.version;
    if (b.unlocked) enterMain(); else renderLock(b.exists);
  });
})();
