// Popup: connection status, logins for this site, a recent suggestion, and a generator.

const $ = (id) => document.getElementById(id);
const send = (msg) => new Promise((res) => chrome.runtime.sendMessage(msg, res));
const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };

function hostOf(url) {
  try { return new URL(url).hostname; } catch { return ""; }
}
async function activeTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab;
}
function setStatus(ok, text) {
  $("status").replaceChildren(el("span", "dot " + (ok ? "ok" : "bad")), el("span", "", text));
}
function digits(target, pw) {
  target.replaceChildren(...[...pw].map((c) => /[0-9]/.test(c) ? el("span", "d", c) : document.createTextNode(c)));
}

async function refresh() {
  const status = await send({ type: "status" });
  if (!status || !status.ok) {
    setStatus(false, status && status.error === "no-token"
      ? "Not paired yet. Open Settings below and paste the token."
      : status && status.error === "unauthorized" ? "The pairing token is wrong. Copy it again from the app."
      : "Can't reach MyVault. Is the app open?");
    return;
  }
  if (!status.unlocked) return setStatus(false, "MyVault is locked. Unlock the app to fill.");
  setStatus(true, `Connected to MyVault ${status.version || ""}`);

  const tab = await activeTab();
  const domain = hostOf(tab?.url || "");
  const res = await send({ type: "match", domain });
  const matches = (res && res.ok && res.matches) || [];
  $("matches").replaceChildren(...(matches.length ? matches.map((m) => {
    const div = el("div", "item");
    const txt = el("div");
    txt.append(el("div", "t", m.title || domain), el("div", "s", m.username || m.email || "(no username)"));
    const b = el("button", "primary", "Fill");
    b.onclick = async () => { await chrome.tabs.sendMessage(tab.id, { type: "fill", cred: m }); window.close(); };
    div.append(txt, b);
    return div;
  }) : [el("div", "empty", `No saved logins for ${domain || "this page"}.`)]));

  const r = await send({ type: "recent", domain });
  if (r && r.recent) {
    const box = el("div", "recent");
    const pw = el("div");
    pw.style.cssText = "font-family:'Cascadia Mono',Consolas,monospace;word-break:break-all";
    digits(pw, r.recent.password);
    const copy = el("button", "", "Copy");
    copy.onclick = () => navigator.clipboard.writeText(r.recent.password).then(() => (copy.textContent = "Copied"));
    box.append(el("div", "lbl", "Password suggested on this site, not saved yet"), pw, copy);
    $("recent").replaceChildren(box);
  }
}

// ---- generator ----
const KEYS = ["use_upper", "use_lower", "use_digits", "use_symbols", "avoid_ambiguous"];
let current = "";
async function generate() {
  const policy = { length: parseInt($("genlen").value, 10) };
  KEYS.forEach((k) => (policy[k] = $(k).checked));
  $("lenout").value = policy.length;
  if (!KEYS.slice(0, 4).some((k) => policy[k])) { current = ""; $("genout").textContent = "Turn on at least one kind."; return; }
  const res = await send({ type: "generate", policy });
  current = res && res.ok ? res.password : "";
  if (current) digits($("genout"), current); else $("genout").textContent = "Open MyVault to generate.";
}
$("genlen").addEventListener("input", generate);
KEYS.forEach((k) => $(k).addEventListener("change", generate));
$("gengo").onclick = generate;
$("gencopy").onclick = async () => {
  if (!current) return;
  await navigator.clipboard.writeText(current);
  $("gencopy").textContent = "Copied";
  setTimeout(() => ($("gencopy").textContent = "Copy"), 1200);
};
$("savepage").onclick = async () => {
  const tab = await activeTab();
  try {
    await chrome.tabs.sendMessage(tab.id, { type: "saveCurrent" });
    window.close();
  } catch {
    $("savepage").textContent = "Reload the page first, then try again";
  }
};
$("opts").onclick = (e) => { e.preventDefault(); chrome.runtime.openOptionsPage(); };

refresh();
generate();
