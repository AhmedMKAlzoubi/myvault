// Content script: runs on every page. It
//   1) finds login fields,
//   2) offers to fill them from MyVault, and
//   3) offers to save new logins you type.
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
    return r.width > 0 && r.height > 0 && s.visibility !== "hidden" && s.display !== "none";
  };

  const passwordFields = () =>
    [...document.querySelectorAll('input[type="password"]')].filter(isVisible);

  function usernameFieldFor(pwField) {
    const form = pwField.form || document;
    const candidates = [...form.querySelectorAll('input')].filter(
      (i) => isVisible(i) &&
        ["text", "email", "tel", ""].includes((i.type || "").toLowerCase()) &&
        i.type !== "password"
    );
    // Prefer autocomplete=username, then name/id hints, else the field visually
    // just before the password box.
    const byAuto = candidates.find((i) => (i.autocomplete || "").includes("username"));
    if (byAuto) return byAuto;
    const hint = /user|email|login|account|phone|mobile/i;
    const byHint = candidates.find((i) => hint.test(i.name + " " + i.id + " " + (i.placeholder || "")));
    if (byHint) return byHint;
    return candidates.length ? candidates[candidates.length - 1] : null;
  }

  function setValue(input, value) {
    if (!input) return;
    const setter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype, "value").set;
    setter.call(input, value);
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function fillWith(cred) {
    const pw = passwordFields()[0];
    if (!pw) return;
    const user = usernameFieldFor(pw);
    const login = cred.username || cred.email || "";
    if (user && login) setValue(user, login);
    setValue(pw, cred.password || "");
    hidePanel();
  }

  // ---------- shadow-DOM UI ----------
  let host, root;
  function ui() {
    if (host) return root;
    host = document.createElement("div");
    host.style.all = "initial";
    host.style.position = "fixed";
    host.style.zIndex = "2147483647";
    host.style.top = "0";
    host.style.left = "0";
    document.documentElement.appendChild(host);
    root = host.attachShadow({ mode: "open" });
    root.innerHTML = `
      <style>
        * { box-sizing: border-box; font-family: Segoe UI, Arial, sans-serif; }
        .panel, .bar {
          position: fixed; background: #fff; color: #111;
          border: 1px solid #111; font-size: 13px;
        }
        .panel { min-width: 220px; box-shadow: 0 4px 14px rgba(0,0,0,.25); }
        .head { padding: 6px 10px; border-bottom: 1px solid #ccc; font-weight: 700; }
        .item { padding: 8px 10px; cursor: pointer; border-bottom: 1px solid #eee; }
        .item:hover { background: #111; color: #fff; }
        .sub { font-size: 11px; color: #666; }
        .item:hover .sub { color: #ddd; }
        .bar {
          top: 12px; left: 50%; transform: translateX(-50%);
          padding: 10px 12px; display: flex; gap: 8px; align-items: center;
          box-shadow: 0 4px 14px rgba(0,0,0,.25);
        }
        button {
          all: unset; border: 1px solid #111; padding: 5px 12px; cursor: pointer;
          background: #fff; color: #111; font-size: 12px;
        }
        button.primary { background: #111; color: #fff; }
        button:hover { background: #333; color: #fff; }
        .x { border: none; padding: 4px 8px; font-weight: 700; }
      </style>
      <div id="mount"></div>`;
    return root;
  }

  function hidePanel() {
    const m = host && root.getElementById ? root.querySelector("#mount") : null;
    if (m) m.innerHTML = "";
  }

  function showPanel(anchor, matches) {
    const r = ui();
    const mount = r.querySelector("#mount");
    const rect = anchor.getBoundingClientRect();
    const rows = matches.map((m, i) => `
      <div class="item" data-i="${i}">
        <div>${escapeHtml(m.title || DOMAIN)}</div>
        <div class="sub">${escapeHtml(m.username || m.email || "(no username)")}</div>
      </div>`).join("");
    mount.innerHTML = `
      <div class="panel" style="left:${Math.round(rect.left)}px; top:${Math.round(rect.bottom + 4)}px;">
        <div class="head">MyVault — fill login</div>
        ${rows}
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
    mount.innerHTML = `
      <div class="bar">
        <span>Save this login to MyVault?</span>
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
        () => {}
      );
      close();
    };
  }

  const escapeHtml = (s) =>
    String(s).replace(/[&<>"']/g, (c) => (
      { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

  // ---------- wire up filling ----------
  function loadMatches() {
    return new Promise((resolve) => {
      chrome.runtime.sendMessage({ type: "match", domain: DOMAIN }, (res) => {
        cachedMatches = res && res.ok && res.matches ? res.matches : [];
        matchesLoaded = true;
        resolve(cachedMatches);
      });
    });
  }

  function attachFillTriggers() {
    passwordFields().forEach((pw) => {
      const user = usernameFieldFor(pw);
      [user, pw].forEach((f) => {
        if (!f || f.__mvBound) return;
        f.__mvBound = true;
        f.addEventListener("focus", async () => {
          if (!matchesLoaded) await loadMatches();
          if (cachedMatches.length) showPanel(f, cachedMatches);
        });
      });
    });
  }

  // Hide the panel when clicking elsewhere.
  document.addEventListener("mousedown", (e) => {
    if (host && !e.composedPath().includes(host)) hidePanel();
  });

  // ---------- capture on submit ----------
  function currentCred() {
    const pw = passwordFields()[0];
    if (!pw || !pw.value) return null;
    const user = usernameFieldFor(pw);
    const login = user ? user.value.trim() : "";
    const looksEmail = /@/.test(login);
    return {
      username: looksEmail ? "" : login,
      email: looksEmail ? login : "",
      password: pw.value,
    };
  }

  function maybeOfferSave() {
    const cred = currentCred();
    if (!cred) return;
    // Don't nag if MyVault already has this exact login+password.
    const known = cachedMatches.some(
      (m) => m.password === cred.password &&
        (m.username === cred.username || m.email === cred.email ||
         (!cred.username && !cred.email))
    );
    if (known) return;
    showSaveBar(cred);
  }

  document.addEventListener("submit", () => setTimeout(maybeOfferSave, 0), true);
  // Some sites log in without a real form submit (button + JS). Also offer to
  // save shortly after the password field loses focus with a value present.
  document.addEventListener("focusout", (e) => {
    if (e.target && e.target.matches && e.target.matches('input[type="password"]')) {
      setTimeout(() => { if (document.activeElement?.tagName === "BUTTON") maybeOfferSave(); }, 200);
    }
  }, true);

  // ---------- messages from the popup ----------
  chrome.runtime.onMessage.addListener((msg, _s, resp) => {
    if (msg.type === "fill" && msg.cred) { fillWith(msg.cred); resp({ ok: true }); }
    if (msg.type === "hasLogin") { resp({ ok: true, hasPassword: passwordFields().length > 0 }); }
    return true;
  });

  // Initial pass (and again if the page adds fields later).
  attachFillTriggers();
  const mo = new MutationObserver(() => attachFillTriggers());
  mo.observe(document.documentElement, { childList: true, subtree: true });
})();
