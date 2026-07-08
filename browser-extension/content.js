// Content script: runs on every page. It
//   1) finds login/registration fields,
//   2) offers to fill them from MyVault (click any login field), and
//   3) offers to save the details when you log in or register.
//
// All UI is rendered inside a Shadow DOM so the host page's CSS can't affect it
// (and ours can't affect the page). Black & white to match the app.

(() => {
  if (window.__myvaultLoaded) return;
  window.__myvaultLoaded = true;

  const DOMAIN = location.hostname;
  let cachedMatches = [];
  let matchesLoaded = false;

  // ---------- helpers ----------
  const isVisible = (el) => {
    if (!el) return false;
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    return r.width > 4 && r.height > 4 && s.visibility !== "hidden" &&
      s.display !== "none" && s.opacity !== "0";
  };

  const textInputs = (scope) =>
    [...scope.querySelectorAll("input")].filter((i) => {
      const t = (i.type || "text").toLowerCase();
      return isVisible(i) && ["text", "email", "tel", "search", ""].includes(t);
    });

  const looksLike = (input, re) =>
    re.test([input.name, input.id, input.placeholder, input.autocomplete,
             input.getAttribute("aria-label") || "",
             (input.labels && input.labels[0] && input.labels[0].textContent) || ""
            ].join(" "));

  const EMAIL_RE = /e-?mail/i;
  const USER_RE = /user|login|account|screen[-_ ]?name|handle/i;
  const PHONE_RE = /phone|mobile|tel/i;

  function passwordFields() {
    return [...document.querySelectorAll('input[type="password"]')].filter(isVisible);
  }

  // Work out which box is the email, which is the username, which is the phone.
  function detectFields() {
    const pw = passwordFields();
    const scope = (pw[0] && pw[0].form) || document;
    const fields = textInputs(scope);

    let emailField = fields.find((i) => (i.type || "").toLowerCase() === "email");
    if (!emailField) emailField = fields.find((i) => looksLike(i, EMAIL_RE));

    let phoneField = fields.find((i) => (i.type || "").toLowerCase() === "tel");
    if (!phoneField) phoneField = fields.find((i) => looksLike(i, PHONE_RE));

    let usernameField = fields.find((i) => (i.autocomplete || "").includes("username"));
    if (!usernameField) {
      usernameField = fields.find(
        (i) => i !== emailField && i !== phoneField && looksLike(i, USER_RE));
    }

    // A single lonely text box next to a password is the "login" box: it may
    // accept either a username OR an email, so treat it as combined.
    const others = fields.filter((i) => i !== emailField && i !== phoneField);
    let combinedField = null;
    if (!usernameField && !emailField && others.length === 1) combinedField = others[0];
    if (!usernameField && others.length === 1 && !combinedField) combinedField = others[0];

    return { pw, fields, emailField, usernameField, phoneField, combinedField };
  }

  function setValue(input, value) {
    if (!input || value == null || value === "") return;
    const proto = input.tagName === "TEXTAREA"
      ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, "value").set;
    input.focus();
    setter.call(input, value);
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function fillWith(cred) {
    const f = detectFields();
    if (f.combinedField) {
      // one login box — prefer whatever the entry actually has
      setValue(f.combinedField, cred.username || cred.email);
    } else {
      if (f.emailField) setValue(f.emailField, cred.email || (!f.usernameField ? cred.username : ""));
      if (f.usernameField) setValue(f.usernameField, cred.username || (!f.emailField ? cred.email : ""));
    }
    if (f.pw[0]) setValue(f.pw[0], cred.password || "");
    hidePanel();
  }

  // ---------- shadow-DOM UI ----------
  let host, root;
  function ui() {
    if (host) return root;
    host = document.createElement("div");
    host.style.all = "initial";
    document.documentElement.appendChild(host);
    root = host.attachShadow({ mode: "open" });
    root.innerHTML = `
      <style>
        * { box-sizing: border-box; font-family: Segoe UI, Arial, sans-serif; }
        .panel, .bar {
          position: fixed; background: #fff; color: #111;
          border: 1px solid #111; font-size: 13px; z-index: 2147483647;
        }
        .panel { min-width: 230px; max-width: 340px; box-shadow: 0 4px 14px rgba(0,0,0,.28); }
        .head { padding: 6px 10px; border-bottom: 1px solid #ccc; font-weight: 700; }
        .item { padding: 8px 10px; cursor: pointer; border-bottom: 1px solid #eee; }
        .item:last-child { border-bottom: none; }
        .item:hover { background: #111; color: #fff; }
        .sub { font-size: 11px; color: #666; }
        .item:hover .sub { color: #ddd; }
        .bar {
          top: 14px; left: 50%; transform: translateX(-50%);
          padding: 10px 12px; display: flex; gap: 8px; align-items: center;
          box-shadow: 0 4px 14px rgba(0,0,0,.28); max-width: 92vw;
        }
        button {
          all: unset; border: 1px solid #111; padding: 5px 12px; cursor: pointer;
          background: #fff; color: #111; font-size: 12px; white-space: nowrap;
        }
        button.primary { background: #111; color: #fff; }
        button:hover { background: #333; color: #fff; }
        .x { border: none; padding: 4px 8px; font-weight: 700; }
      </style>
      <div id="mount"></div>`;
    return root;
  }

  function hidePanel() {
    if (host) root.querySelector("#mount").innerHTML = "";
  }

  const escapeHtml = (s) =>
    String(s).replace(/[&<>"']/g, (c) => (
      { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

  function showPanel(anchor, matches) {
    const r = ui();
    const mount = r.querySelector("#mount");
    const rect = anchor.getBoundingClientRect();
    const top = Math.min(rect.bottom + 4, window.innerHeight - 60);
    const left = Math.min(rect.left, window.innerWidth - 250);
    const rows = matches.map((m, i) => `
      <div class="item" data-i="${i}">
        <div>${escapeHtml(m.title || DOMAIN)}</div>
        <div class="sub">${escapeHtml(m.username || m.email || "(no username)")}</div>
      </div>`).join("");
    mount.innerHTML =
      `<div class="panel" style="left:${Math.round(left)}px; top:${Math.round(top)}px;">
        <div class="head">MyVault — click to fill</div>${rows}
      </div>`;
    mount.querySelectorAll(".item").forEach((el) => {
      el.addEventListener("mousedown", (e) => {
        e.preventDefault();
        fillWith(matches[Number(el.dataset.i)]);
      });
    });
  }

  function showSaveBar(cred) {
    const r = ui();
    const mount = r.querySelector("#mount");
    const who = cred.email || cred.username || "this login";
    mount.innerHTML =
      `<div class="bar">
        <span>Save <b>${escapeHtml(who)}</b> for ${escapeHtml(DOMAIN)} to MyVault?</span>
        <button class="primary" id="mv-save">Save</button>
        <button id="mv-no">No</button>
        <button class="x" id="mv-x">✕</button>
      </div>`;
    const close = () => (mount.innerHTML = "");
    r.getElementById("mv-no").onclick = close;
    r.getElementById("mv-x").onclick = close;
    r.getElementById("mv-save").onclick = () => {
      chrome.runtime.sendMessage(
        { type: "save", cred: { ...cred, domain: DOMAIN, url: location.href } },
        () => { matchesLoaded = false; }   // refresh matches after saving
      );
      close();
    };
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

  // Show the fill panel when any login-ish field gets focus (event delegation,
  // so it also works for fields the page adds later).
  document.addEventListener("focusin", async (e) => {
    const el = e.target;
    if (!(el instanceof HTMLInputElement)) return;
    const t = (el.type || "text").toLowerCase();
    if (!["text", "email", "tel", "password", "search", ""].includes(t)) return;
    if (!passwordFields().length && t !== "password" && t !== "email" &&
        !looksLike(el, USER_RE) && !looksLike(el, EMAIL_RE)) return;
    if (!matchesLoaded) await loadMatches();
    if (cachedMatches.length) showPanel(el, cachedMatches);
  }, true);

  // Hide the panel when clicking elsewhere.
  document.addEventListener("mousedown", (e) => {
    if (host && !e.composedPath().includes(host)) hidePanel();
  }, true);
  window.addEventListener("scroll", hidePanel, true);

  // ---------- capture on login / registration ----------
  function currentCred() {
    const f = detectFields();
    if (!f.pw[0] || !f.pw[0].value) return null;   // nothing to save without a password
    let username = "", email = "";
    if (f.combinedField) {
      const v = f.combinedField.value.trim();
      if (/@/.test(v)) email = v; else username = v;
    } else {
      email = f.emailField ? f.emailField.value.trim() : "";
      username = f.usernameField ? f.usernameField.value.trim() : "";
    }
    return {
      username, email,
      password: f.pw[0].value,
      phone: f.phoneField ? f.phoneField.value.trim() : "",
    };
  }

  let lastOffered = "";
  function maybeOfferSave() {
    const cred = currentCred();
    if (!cred) return;
    const known = cachedMatches.some(
      (m) => m.password === cred.password &&
        (m.username === cred.username || m.email === cred.email ||
         (!cred.username && !cred.email)));
    if (known) return;
    const sig = cred.username + "|" + cred.email + "|" + cred.password;
    if (sig === lastOffered) return;   // don't re-ask for the same thing
    lastOffered = sig;
    showSaveBar(cred);
  }

  // Real form submits...
  document.addEventListener("submit", () => setTimeout(maybeOfferSave, 0), true);
  // ...and JS logins (button click or Enter in the password box).
  document.addEventListener("click", (e) => {
    const b = e.target.closest("button, input[type=submit], [role=button], a");
    if (b && /log ?in|sign ?in|sign ?up|register|continue|submit|next|create/i
        .test(b.textContent + " " + (b.value || ""))) {
      setTimeout(maybeOfferSave, 150);
    }
  }, true);
  document.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && e.target instanceof HTMLInputElement &&
        e.target.type === "password") {
      setTimeout(maybeOfferSave, 150);
    }
  }, true);

  // ---------- messages from the popup ----------
  chrome.runtime.onMessage.addListener((msg, _s, resp) => {
    if (msg.type === "fill" && msg.cred) { fillWith(msg.cred); resp({ ok: true }); }
    else if (msg.type === "hasLogin") resp({ ok: true, hasPassword: passwordFields().length > 0 });
    else if (msg.type === "saveCurrent") { maybeOfferSaveForce(); resp({ ok: true }); }
    return true;
  });

  // Popup "save this page" — offer even if it looks already-known.
  function maybeOfferSaveForce() {
    const cred = currentCred();
    if (cred) { lastOffered = ""; showSaveBar(cred); }
    else showToast("No password field with a value on this page to save.");
  }

  function showToast(text) {
    const r = ui();
    const mount = r.querySelector("#mount");
    mount.innerHTML = `<div class="bar"><span>${escapeHtml(text)}</span>
      <button class="x" id="mv-t">✕</button></div>`;
    r.getElementById("mv-t").onclick = () => (mount.innerHTML = "");
    setTimeout(() => { if (mount.querySelector("#mv-t")) mount.innerHTML = ""; }, 4000);
  }

  // Pre-load matches so the first click is instant.
  loadMatches();
})();
