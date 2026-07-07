"""
The local "connector" the browser extension talks to.

SECURITY DESIGN (this is a password tool, so this matters):
  * Binds to 127.0.0.1 only  -> reachable only from your own computer, never
    from the WiFi/LAN/internet. Loopback also avoids Windows Firewall prompts.
  * Requires a pairing token -> every request must send the exact secret token
    shown in the app. Without it, requests are refused. This stops other local
    programs or web pages from reading your vault.
  * Only serves data while the vault is UNLOCKED and only the minimum needed.
  * Never returns anything unless the token matches, checked in constant time.

It runs in a background thread while the app is open. The extension asks it
"what logins do I have for this domain?" and "please save this new login".
"""

from __future__ import annotations

import hmac
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import __version__

HOST = "127.0.0.1"
MAX_BODY = 64 * 1024
TOKEN_HEADER = "X-MyVault-Token"


class _Handler(BaseHTTPRequestHandler):
    # Silence the default noisy stderr logging.
    def log_message(self, *args):  # noqa: D401
        pass

    # ---- helpers ---------------------------------------------------------
    @property
    def provider(self):
        return self.server.provider  # type: ignore[attr-defined]

    def _origin_allowed(self) -> str:
        origin = self.headers.get("Origin", "")
        # Only browser extensions get CORS access reflected back.
        if origin.startswith("chrome-extension://") or origin.startswith("moz-extension://"):
            return origin
        return "null"

    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", self._origin_allowed())
        self.send_header("Access-Control-Allow-Headers", f"{TOKEN_HEADER}, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Max-Age", "600")

    def _send(self, code: int, obj: dict) -> None:
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self) -> bool:
        given = self.headers.get(TOKEN_HEADER, "")
        return bool(given) and hmac.compare_digest(given, self.server.token)  # type: ignore[attr-defined]

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", 0) or 0)
        if length <= 0 or length > MAX_BODY:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return {}

    # ---- routes ----------------------------------------------------------
    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        if not self._authorized():
            return self._send(401, {"error": "unauthorized"})
        if self.path == "/status":
            return self._send(200, {
                "app": "MyVault",
                "version": __version__,
                "unlocked": self.provider.is_unlocked(),
            })
        return self._send(404, {"error": "not found"})

    def do_POST(self):
        if not self._authorized():
            return self._send(401, {"error": "unauthorized"})
        data = self._read_json()

        if self.path == "/match":
            if not self.provider.is_unlocked():
                return self._send(423, {"unlocked": False, "matches": []})
            matches = self.provider.match(data.get("domain", ""))
            return self._send(200, {"unlocked": True, "matches": matches})

        if self.path == "/save":
            if not self.provider.is_unlocked():
                return self._send(423, {"ok": False, "error": "locked"})
            result = self.provider.save(data)
            return self._send(200, result)

        if self.path == "/generate":
            return self._send(200, {"password": self.provider.generate(data.get("policy"))})

        return self._send(404, {"error": "not found"})


class Connector:
    """Owns the background HTTP server. Start on unlock, stop on lock/close."""

    def __init__(self, provider, token: str, port: int):
        self.provider = provider
        self.token = token
        self.port = port
        self._httpd: ThreadingHTTPServer | None = None
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        if self._httpd is not None:
            return
        httpd = ThreadingHTTPServer((HOST, self.port), _Handler)
        httpd.provider = self.provider      # type: ignore[attr-defined]
        httpd.token = self.token            # type: ignore[attr-defined]
        httpd.daemon_threads = True
        self._httpd = httpd
        self._thread = threading.Thread(target=httpd.serve_forever, daemon=True,
                                        name="myvault-connector")
        self._thread.start()

    def stop(self) -> None:
        if self._httpd is not None:
            self._httpd.shutdown()
            self._httpd.server_close()
            self._httpd = None
            self._thread = None

    @property
    def running(self) -> bool:
        return self._httpd is not None
