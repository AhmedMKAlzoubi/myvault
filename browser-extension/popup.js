// Popup: shows connection status, logins for the current site, and a generator.

const $ = (id) => document.getElementById(id);
const send = (msg) => new Promise((res) => chrome.runtime.sendMessage(msg, res));

function hostOf(url) {
  try { return new URL(url).hostname; } catch { return ""; }
}

async function activeTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab;
}

function setStatus(cls, text) {
  $("status").innerHTML = `<span class="dot ${cls}">●</span> ${text}`;
}

async function refresh() {
  const status = await send({ type: "status" });
  if (!status || !status.ok) {
    if (status && status.error === "no-token") {
      setStatus("bad", "Not paired — open Settings and paste the token.");
    } else {
      setStatus("bad", "Can't reach MyVault. Is the app open and unlocked?");
    }
    $("matches").innerHTML = "";
    return;
  }
  if (!status.unlocked) {
    setStatus("bad", "MyVault is locked — unlock the app to auto-fill.");
    $("matches").innerHTML = "";
    return;
  }
  setStatus("ok", `Connected — MyVault ${status.version || ""}`);

  const tab = await activeTab();
  const domain = hostOf(tab?.url || "");
  const res = await send({ type: "match", domain });
  const matches = (res && res.ok && res.matches) || [];
  if (!matches.length) {
    $("matches").innerHTML = `<div class="empty">No saved logins for “${domain || "this page"}”.</div>`;
    return;
  }
  $("matches").innerHTML = "";
  matches.forEach((m) => {
    const div = document.createElement("div");
    div.className = "item";
    div.innerHTML = `<div><div class="t"></div><div class="s"></div></div>`;
    div.querySelector(".t").textContent = m.title || domain;
    div.querySelector(".s").textContent = m.username || m.email || "(no username)";
    const btn = document.createElement("button");
    btn.className = "primary";
    btn.textContent = "Fill";
    btn.onclick = async () => {
      await chrome.tabs.sendMessage(tab.id, { type: "fill", cred: m });
      window.close();
    };
    div.appendChild(btn);
    $("matches").appendChild(div);
  });
}

$("gengo").onclick = async () => {
  const len = Math.max(6, Math.min(64, parseInt($("genlen").value, 10) || 16));
  const res = await send({ type: "generate", policy: { length: len } });
  $("genout").value = res && res.ok ? res.password : "(connect the app first)";
};
$("gencopy").onclick = async () => {
  if (!$("genout").value) return;
  await navigator.clipboard.writeText($("genout").value);
  $("gencopy").textContent = "Copied";
  setTimeout(() => ($("gencopy").textContent = "Copy"), 1200);
};
$("savepage").onclick = async () => {
  const tab = await activeTab();
  try {
    await chrome.tabs.sendMessage(tab.id, { type: "saveCurrent" });
    window.close();   // let the user see the save bar on the page
  } catch {
    // content script not loaded on this page (e.g. it was open before install)
    $("savepage").textContent = "Reload the page first, then try";
  }
};

$("opts").onclick = (e) => { e.preventDefault(); chrome.runtime.openOptionsPage(); };

refresh();
