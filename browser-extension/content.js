// Content script: runs on every page. It
//   1) finds login and registration fields,
//   2) offers your saved logins when you click a login box (never fills on its own),
//   3) on sign-up forms, offers a strong generated password,
//   4) after you log in or register, offers to save the details to MyVault.
//
// All UI lives in a closed Shadow DOM so the page's CSS can't touch it (and
// ours can't touch the page). Page-supplied text is only set via textContent.

(() => {
  if (window.__myvaultLoaded) return;
  window.__myvaultLoaded = true;

  const DOMAIN = location.hostname;
  let cachedMatches = [];
  let matchesLoaded = false;
  let suggested = "";            // a password we suggested and the user accepted

  // ---------- field detection ----------
  const isVisible = (el) => {
    if (!el) return false;
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    return r.width > 4 && r.height > 4 && s.visibility !== "hidden" && s.display !== "none" && s.opacity !== "0";
  };
  const hint = (el) => [el.name, el.id, el.placeholder, el.autocomplete, el.getAttribute("aria-label") || "",
    (el.labels && el.labels[0] && el.labels[0].textContent) || ""].join(" ");
  const looksLike = (el, re) => re.test(hint(el));

  const EMAIL_RE = /e-?mail/i;
  const USER_RE = /user|login|account|screen[-_ ]?name|handle/i;
  const PHONE_RE = /phone|mobile|tel\b/i;
  const SIGNUP_RE = /sign ?up|register|create (an |your |new )?account|join now|get started/i;
  const NEVER_RE = /card|cvv|cvc|iban|ssn|social.?sec|security.?code|otp|one.?time|captcha|coupon|promo|search|cc-/i;

  const textInputs = (scope) => [...scope.querySelectorAll("input")].filter((i) => {
    const t = (i.type || "text").toLowerCase();
    return isVisible(i) && ["text", "email", "tel", ""].includes(t);
  });
  const passwordFields = () => [...document.querySelectorAll('input[type="password"]')].filter(isVisible);

  // Fields that want a NEW password: marked new-password, a password + confirm
  // pair in one form, or a lone password box in a form whose button says "sign up".
  function newPasswordFields() {
    const pw = passwordFields().filter((i) => !(i.autocomplete || "").includes("current-password"));
    const marked = pw.filter((i) => (i.autocomplete || "").includes("new-password"));
    if (marked.length) return marked;
    const byForm = new Map();
    pw.forEach((i) => byForm.set(i.form, [...(byForm.get(i.form) || []), i]));
    for (const [form, list] of byForm) {
      if (form && list.length >= 2) return list;
      if (form && list.length === 1) {
        const buttons = [...form.querySelectorAll("button, input[type=submit], [role=button]")]
          .map((b) => b.textContent + " " + (b.value || "")).join(" ");
        if (SIGNUP_RE.test(buttons)) return list;
      }
    }
    return [];
  }

  function detectFields() {
    const pw = passwordFields();
    const scope = (pw[0] && pw[0].form) || document;
    const fields = textInputs(scope);
    let emailField = fields.find((i) => (i.type || "").toLowerCase() === "email") || fields.find((i) => looksLike(i, EMAIL_RE));
    let phoneField = fields.find((i) => (i.type || "").toLowerCase() === "tel") || fields.find((i) => looksLike(i, PHONE_RE));
    let usernameField = fields.find((i) => (i.autocomplete || "").includes("username"))
      || fields.find((i) => i !== emailField && i !== phoneField && looksLike(i, USER_RE));
    // One lone text box next to a password is "the login box": username OR email.
    const others = fields.filter((i) => i !== emailField && i !== phoneField);
    const combinedField = !usernameField && !emailField && others.length === 1 ? others[0] : null;
    return { pw, scope, fields, emailField, usernameField, phoneField, combinedField };
  }

  // Extra details typed into a sign-up form (name, birthday, country...).
  // Never card numbers, codes, or anything that looks like a one-time secret.
  const PROFILE = [
    ["region", /country|region|nation/i], ["gender", /gender|\bsex\b/i], ["age", /\bage\b/i],
  ];
  const EXTRA = [
    ["First name", /first.?name|given.?name|fname/i], ["Last name", /last.?name|surname|family.?name|lname/i],
    ["Full name", /full.?name|^name$|your.?name/i], ["Date of birth", /birth|dob|bday/i],
    ["City", /city|town/i], ["Address", /address|street/i], ["Postal code", /zip|postal|post.?code/i],
  ];
  function captureProfile(f) {
    const out = { extra: {} };
    const skip = new Set([f.emailField, f.usernameField, f.phoneField, f.combinedField]);
    const els = [...f.scope.querySelectorAll("input, select")].filter((el) =>
      isVisible(el) && !skip.has(el) && el.type !== "password" && el.type !== "hidden" && el.type !== "checkbox"
      && el.type !== "radio" && el.type !== "submit" && !NEVER_RE.test(hint(el)));
    for (const el of els) {
      const v = el.tagName === "SELECT" ? (el.selectedOptions[0] || {}).textContent : el.value;
      const val = (v || "").trim();
      if (!val || val.length > 200) continue;
      const h = hint(el);
      const p = PROFILE.find(([, re]) => re.test(h));
      if (p) { out[p[0]] = val; continue; }
      const x = EXTRA.find(([, re]) => re.test(h));
      if (x) out.extra[x[0]] = val;
    }
    return out;
  }

  let filling = false;            // our own focus() calls must not reopen panels
  function setValue(input, value) {
    if (!input || value == null || value === "") return;
    const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value").set;
    filling = true;
    input.focus();
    filling = false;
    setter.call(input, value);
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function fillWith(cred) {
    const f = detectFields();
    if (f.combinedField) setValue(f.combinedField, cred.username || cred.email);
    else {
      if (f.emailField) setValue(f.emailField, cred.email || (!f.usernameField ? cred.username : ""));
      if (f.usernameField) setValue(f.usernameField, cred.username || (!f.emailField ? cred.email : ""));
    }
    if (f.pw[0]) setValue(f.pw[0], cred.password || "");
    hidePanel();
  }

  // ---------- shadow-DOM UI (security-envelope look) ----------
  const TINT = "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='14' height='7'%3E%3Cpath d='M0 3.5C2.3.7 4.7.7 7 3.5s4.7 2.8 7 0M0 7c2.3-2.8 4.7-2.8 7 0s4.7 2.8 7 0M0 0c2.3-2.8 4.7-2.8 7 0s4.7 2.8 7 0' fill='none' stroke='%23000' stroke-width='.85'/%3E%3C/svg%3E\")";
  let host, root, mount;
  function ui() {
    if (host) return mount;
    host = document.createElement("div");
    host.style.all = "initial";
    // Inline !important beats any page stylesheet, so the page can't make our
    // cards invisible while they still take clicks.
    for (const [k, v] of [["display", "block"], ["opacity", "1"], ["visibility", "visible"], ["filter", "none"],
      ["transform", "none"], ["clip-path", "none"], ["mask", "none"], ["position", "static"], ["pointer-events", "auto"]]) {
      host.style.setProperty(k, v, "important");
    }
    document.documentElement.appendChild(host);
    root = host.attachShadow({ mode: "closed" });
    root.innerHTML = `
      <style>
        :host { all: initial; }
        * { box-sizing: border-box; font-family: "Segoe UI Variable Text", "Segoe UI", system-ui, sans-serif; }
        .card { position: fixed; z-index: 2147483647; background: #FBFBFC; color: #1B2433; font-size: 13px;
          border: 1px solid #C2C9D6; border-radius: 8px; box-shadow: 0 1px 2px rgba(27,36,51,.08), 0 10px 28px rgba(27,36,51,.16);
          overflow: hidden; min-width: 250px; max-width: 360px; }
        .head { position: relative; padding: 9px 12px 8px; font-weight: 600; display: flex; align-items: center; gap: 8px;
          border-bottom: 1px solid #D5DAE3; background: #F4F5F7; }
        .head::before { content: ""; position: absolute; inset: 0; background: #2F4A7A; opacity: .16;
          -webkit-mask: ${TINT} 0 0 / 14px 7px repeat; mask: ${TINT} 0 0 / 14px 7px repeat; }
        .head span { position: relative; }
        .mark { position: relative; width: 18px; height: 13px; }
        .item { padding: 9px 12px; cursor: pointer; border-bottom: 1px solid #ECEEF2; }
        .item:last-child { border-bottom: 0; }
        .item:hover, .item:focus { background: #1B2433; color: #F4F5F7; outline: none; }
        .sub { font-size: 12px; color: #5F687A; }
        .item:hover .sub, .item:focus .sub { color: #C9D2E3; }
        .pw { font-family: "Cascadia Mono", Consolas, monospace; font-size: 14px; word-break: break-all; padding: 10px 12px 4px; letter-spacing: .02em; }
        .pw .d { color: #2F4A7A; }
        .note { padding: 0 12px 10px; font-size: 12px; color: #5F687A; }
        .row { display: flex; gap: 6px; padding: 0 12px 12px; }
        .bar { top: 14px; left: 50%; transform: translateX(-50%); display: flex; gap: 8px; align-items: center; padding: 10px 12px; max-width: 92vw; }
        button { all: unset; border: 1px solid #C2C9D6; border-radius: 6px; padding: 5px 12px; cursor: pointer; background: #FBFBFC;
          color: #1B2433; font-size: 12.5px; font-weight: 500; white-space: nowrap; }
        button:hover { border-color: #5F687A; background: #ECEEF2; }
        button:focus-visible { outline: 2px solid #2F4A7A; outline-offset: 2px; }
        button.primary { background: #1B2433; border-color: #1B2433; color: #F4F5F7; }
        button.primary:hover { background: #2F4A7A; border-color: #2F4A7A; }
        button.x { border: 0; padding: 4px 6px; color: #5F687A; line-height: 0; }
        @media (prefers-color-scheme: dark) {
          .card { background: #1A202A; color: #E6EAF2; border-color: #384256; }
          .head { background: #161B24; border-color: #2A3242; } .head::before { background: #7E98CC; opacity: .22; }
          .item { border-color: #2A3242; } .item:hover, .item:focus { background: #E6EAF2; color: #12161E; }
          .sub, .note { color: #959EAF; } .item:hover .sub { color: #384256; } .pw .d { color: #7E98CC; }
          button { background: #1A202A; color: #E6EAF2; border-color: #384256; } button:hover { background: #222B3B; }
          button.primary { background: #E6EAF2; color: #12161E; border-color: #E6EAF2; }
        }
      </style>
      <div id="mount"></div>`;
    mount = root.getElementById("mount");
    return mount;
  }
  const MARK = '<svg class="mark" viewBox="0 0 30 22" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="1" y="1" width="28" height="20" rx="2.5"/><path d="M1.5 2l13.5 10L28.5 2"/></svg>';
  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  function head(text) {
    const h = el("div", "head");
    h.insertAdjacentHTML("afterbegin", MARK);   // constant markup only
    h.append(el("span", "", text));
    return h;
  }
  function place(card, anchor) {
    const r = anchor.getBoundingClientRect();
    card.style.top = Math.round(Math.min(r.bottom + 6, window.innerHeight - 200)) + "px";
    card.style.left = Math.round(Math.max(8, Math.min(r.left, window.innerWidth - 370))) + "px";
  }
  function hidePanel() { if (mount) mount.replaceChildren(); }

  // Fill only from a card the user can genuinely see: shown for a moment, and
  // reported visible (not covered, faded or transformed) by the browser's own
  // occlusion check. Stops a page hiding the card under a fake button.
  function guardVisible(card) {
    const shownAt = performance.now();
    let visible = !("IntersectionObserver" in window);
    try {
      const io = new IntersectionObserver((es) => {
        for (const e of es) visible = e.isVisible === undefined ? e.isIntersecting : e.isVisible;
      }, { trackVisibility: true, delay: 100 });
      io.observe(card);
    } catch (_) {
      visible = true;          // no occlusion API: fall back to the timing check
    }
    return () => visible && performance.now() - shownAt > 350;
  }

  function showPanel(anchor, matches) {
    const m = ui();
    const card = el("div", "card");
    const canFill = guardVisible(card);
    card.append(head("MyVault: choose an account"));
    matches.forEach((cred) => {
      const it = el("div", "item");
      it.tabIndex = 0;
      it.append(el("div", "", cred.title || DOMAIN), el("div", "sub", cred.username || cred.email || "(no username)"));
      const go = (e) => { e.preventDefault(); if (e.isTrusted && canFill()) fillWith(cred); };
      it.addEventListener("mousedown", go);
      it.addEventListener("keydown", (e) => { if (e.key === "Enter") go(e); });
      card.append(it);
    });
    place(card, anchor);
    m.replaceChildren(card);
  }

  function showSuggestion(anchor, targets) {
    chrome.runtime.sendMessage({ type: "generate", domain: DOMAIN }, (res) => {
      if (!res || !res.ok || !res.password) return;   // app closed or locked: never suggest
      const pw = res.password;
      const m = ui();
      const card = el("div", "card");
      card.append(head("MyVault: suggested password"));
      const box = el("div", "pw");
      [...pw].forEach((c) => box.append(/[0-9]/.test(c) ? el("span", "d", c) : document.createTextNode(c)));
      card.append(box, el("div", "note", "Strong and random. MyVault offers to save it when you submit the form."));
      const row = el("div", "row");
      const use = el("button", "primary", "Use this password");
      const no = el("button", "", "Not now");
      use.addEventListener("mousedown", (e) => {
        e.preventDefault();
        targets.forEach((t) => setValue(t, pw));
        suggested = pw;
        // Safety net: if the page reloads before you save, the popup still shows it.
        chrome.runtime.sendMessage({ type: "remember", domain: DOMAIN, password: pw });
        hidePanel();
      });
      no.addEventListener("mousedown", (e) => { e.preventDefault(); declined.add(anchor); hidePanel(); });
      row.append(use, no);
      card.append(row);
      place(card, anchor);
      m.replaceChildren(card);
    });
  }
  const declined = new WeakSet();

  function showSaveBar(cred, isNew) {
    const m = ui();
    const bar = el("div", "card bar");
    const who = cred.email || cred.username || "this login";
    const text = el("span");
    text.append(isNew ? "Save your new account " : "Save ", el("b", "", who), ` for ${DOMAIN} to MyVault?`);
    const save = el("button", "primary", "Save");
    const no = el("button", "", "Not now");
    const x = el("button", "x");
    x.insertAdjacentHTML("afterbegin", '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>');
    x.setAttribute("aria-label", "Close");
    const close = () => m.replaceChildren();
    no.onclick = close;
    x.onclick = close;
    save.onclick = () => {
      chrome.runtime.sendMessage({ type: "save", cred: { ...cred, domain: DOMAIN, url: location.origin } }, (res) => {
        matchesLoaded = false;
        toast(res && res.ok ? "Saved to MyVault." : "Couldn't save. Is MyVault open and unlocked?");
      });
      if (suggested === cred.password) chrome.runtime.sendMessage({ type: "forget", domain: DOMAIN });
      suggested = "";
      close();
    };
    bar.append(text, save, no, x);
    m.replaceChildren(bar);
  }

  function toast(text) {
    const m = ui();
    const bar = el("div", "card bar");
    bar.append(el("span", "", text));
    m.replaceChildren(bar);
    setTimeout(() => { if (m.contains(bar)) m.replaceChildren(); }, 3500);
  }

  // ---------- matches ----------
  function loadMatches() {
    return new Promise((resolve) => {
      chrome.runtime.sendMessage({ type: "match", domain: DOMAIN }, (res) => {
        cachedMatches = res && res.ok && res.matches ? res.matches : [];
        matchesLoaded = true;
        resolve(cachedMatches);
      });
    });
  }

  // Click/focus on a field: sign-up password boxes get a suggestion, login
  // boxes get the account picker. Nothing is ever filled without a click.
  document.addEventListener("focusin", async (e) => {
    const t = e.target;
    if (filling || !(t instanceof HTMLInputElement)) return;
    const type = (t.type || "text").toLowerCase();
    if (!["text", "email", "tel", "password", ""].includes(type)) return;
    const fresh = newPasswordFields();
    if (type === "password" && fresh.includes(t)) {
      if (!t.value && !suggested && !declined.has(t)) showSuggestion(t, fresh);
      return;
    }
    if (!passwordFields().length && type !== "password" && type !== "email" && !looksLike(t, USER_RE) && !looksLike(t, EMAIL_RE)) return;
    if (fresh.length) return;                     // a sign-up form: don't offer existing logins
    if (!matchesLoaded) await loadMatches();
    if (cachedMatches.length) showPanel(t, cachedMatches);
  }, true);

  document.addEventListener("mousedown", (e) => {
    if (host && !e.composedPath().includes(host) && mount && mount.querySelector(".card:not(.bar)")) hidePanel();
  }, true);
  window.addEventListener("scroll", () => { if (mount && mount.querySelector(".card:not(.bar)")) hidePanel(); }, true);

  // ---------- capture on login / registration ----------
  function currentCred() {
    const f = detectFields();
    const pwField = f.pw.find((p) => p.value);
    if (!pwField) return null;
    let username = "", email = "";
    if (f.combinedField) {
      const v = f.combinedField.value.trim();
      if (v.includes("@")) email = v; else username = v;
    } else {
      email = f.emailField ? f.emailField.value.trim() : "";
      username = f.usernameField ? f.usernameField.value.trim() : "";
    }
    const isNew = newPasswordFields().length > 0;
    const cred = { username, email, password: pwField.value, phone: f.phoneField ? f.phoneField.value.trim() : "" };
    if (isNew) Object.assign(cred, captureProfile(f));
    return { cred, isNew };
  }

  let lastOffered = "";
  function maybeOfferSave(force = false) {
    const cur = currentCred();
    if (!cur) { if (force) toast("There's no filled-in password on this page to save."); return; }
    const { cred, isNew } = cur;
    const known = cachedMatches.some((m) => m.password === cred.password &&
      (m.username === cred.username || m.email === cred.email || (!cred.username && !cred.email)));
    if (known && !force) return;
    const sig = cred.username + "|" + cred.email + "|" + cred.password;
    if (sig === lastOffered && !force) return;
    lastOffered = sig;
    // You accepted MyVault's suggested password for this sign-up: you clearly
    // want it kept, so save straight away instead of asking again.
    if (suggested && cred.password === suggested && !force) return autoSave(cred);
    showSaveBar(cred, isNew);
  }

  function autoSave(cred) {
    chrome.runtime.sendMessage({ type: "save", cred: { ...cred, domain: DOMAIN, url: location.origin } }, (res) => {
      matchesLoaded = false;
      if (res && res.ok) {
        chrome.runtime.sendMessage({ type: "forget", domain: DOMAIN });
        suggested = "";
        toast(`Saved your new ${DOMAIN} account to MyVault.`);
      } else {
        // Couldn't reach the app: fall back to asking, so nothing is lost.
        lastOffered = "";
        showSaveBar(cred, true);
      }
    });
  }

  document.addEventListener("submit", () => setTimeout(maybeOfferSave, 0), true);
  document.addEventListener("click", (e) => {
    const b = e.target.closest && e.target.closest("button, input[type=submit], [role=button], a");
    if (b && /log ?in|sign ?in|sign ?up|register|continue|submit|next|create|join/i.test(b.textContent + " " + (b.value || ""))) {
      setTimeout(maybeOfferSave, 150);
    }
  }, true);
  document.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && e.target instanceof HTMLInputElement && e.target.type === "password") setTimeout(maybeOfferSave, 150);
  }, true);

  // ---------- messages from the popup ----------
  chrome.runtime.onMessage.addListener((msg, _s, resp) => {
    if (msg.type === "fill" && msg.cred) {
      // The popup says which site it meant; refuse if the tab has moved on since.
      if (msg.domain && msg.domain !== DOMAIN) { resp({ ok: false, error: "the page changed" }); return true; }
      fillWith(msg.cred); resp({ ok: true });
    }
    else if (msg.type === "saveCurrent") { lastOffered = ""; maybeOfferSave(true); resp({ ok: true }); }
    return true;
  });

  loadMatches();
})();
