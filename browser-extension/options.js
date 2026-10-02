// Options: save the pairing token + port, and test the connection.

const $ = (id) => document.getElementById(id);
const send = (msg) => new Promise((res) => chrome.runtime.sendMessage(msg, res));

async function load() {
  const { token = "", port = 8787 } = await chrome.storage.local.get(["token", "port"]);
  $("token").value = token;
  $("port").value = port;
}

async function save() {
  const token = $("token").value.trim();
  const port = parseInt($("port").value, 10) || 8787;
  await chrome.storage.local.set({ token, port });
  return { token, port };
}

function msg(cls, text) {
  $("msg").className = cls;
  $("msg").textContent = text;
}

async function test() {
  const res = await send({ type: "status" });
  if (res && res.ok) {
    msg("ok", res.unlocked
      ? `Connected. MyVault ${res.version || ""} is unlocked and ready.`
      : "Connected, but the vault is locked. Unlock the app to fill logins.");
  } else if (res && res.error === "unauthorized") {
    msg("bad", "Reached the app, but the token is wrong. Copy it again from the app.");
  } else if (res && res.error === "no-token") {
    msg("bad", "Enter the pairing token first.");
  } else {
    msg("bad", "Couldn't reach MyVault. Make sure the app is open, then check the port.");
  }
}

$("save").onclick = async () => { await save(); msg("", "Saved. Testing…"); test(); };
$("test").onclick = test;
load();
