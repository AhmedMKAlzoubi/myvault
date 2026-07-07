// Background service worker.
//
// This is the ONLY place that talks to the local MyVault connector. Content
// scripts and the popup ask it to do things via messages, so the secret token
// never lives inside web pages. Requests go to 127.0.0.1 (your own machine).

const DEFAULT_PORT = 8787;

async function getConfig() {
  const { token = "", port = DEFAULT_PORT } = await chrome.storage.local.get(["token", "port"]);
  return { token, port };
}

async function api(path, { method = "GET", body = null } = {}) {
  const { token, port } = await getConfig();
  if (!token) return { ok: false, error: "no-token" };
  const headers = { "X-MyVault-Token": token };
  if (body !== null) headers["Content-Type"] = "application/json";
  try {
    const res = await fetch(`http://127.0.0.1:${port}${path}`, {
      method,
      headers,
      body: body !== null ? JSON.stringify(body) : undefined,
    });
    if (res.status === 401) return { ok: false, error: "unauthorized" };
    if (res.status === 423) return { ok: false, error: "locked", ...(await res.json()) };
    const data = await res.json();
    return { ok: true, ...data };
  } catch (e) {
    // App not running / connector off.
    return { ok: false, error: "no-connection" };
  }
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  (async () => {
    switch (msg.type) {
      case "status":
        sendResponse(await api("/status"));
        break;
      case "match":
        sendResponse(await api("/match", { method: "POST", body: { domain: msg.domain } }));
        break;
      case "save":
        sendResponse(await api("/save", { method: "POST", body: msg.cred }));
        break;
      case "generate":
        sendResponse(await api("/generate", { method: "POST", body: { policy: msg.policy || null } }));
        break;
      default:
        sendResponse({ ok: false, error: "unknown-message" });
    }
  })();
  return true; // keep the message channel open for the async response
});
