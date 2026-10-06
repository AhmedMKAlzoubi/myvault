"""
Two-factor codes (TOTP, RFC 6238): the 6-digit codes an authenticator app shows.

A login keeps its 2FA secret in fields["totp"], either the otpauth:// link from
the site's QR code or the bare secret. The same rules are in the phone's
lib/otp.dart; android_app/test_fixtures/otp_cases.json checks both.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import re
import struct
import time
from urllib.parse import parse_qs, unquote, urlparse

_ALGS = {"SHA1": hashlib.sha1, "SHA256": hashlib.sha256, "SHA512": hashlib.sha512}


def parse(text: str) -> dict:
    """{secret, digits, period, algorithm, issuer, account}; ValueError if it isn't a 2FA secret."""
    text = (text or "").strip()
    out = {"digits": 6, "period": 30, "algorithm": "SHA1", "issuer": "", "account": ""}
    if text.lower().startswith("otpauth://"):
        u = urlparse(text)
        if u.netloc.lower() != "totp":
            raise ValueError("Only time-based codes (TOTP) are supported.")
        q = {k.lower(): v[0] for k, v in parse_qs(u.query).items()}
        label = unquote(u.path.lstrip("/"))
        issuer, _, account = label.rpartition(":")
        out.update(issuer=q.get("issuer", issuer).strip(), account=account.strip())
        text = q.get("secret", "")
        try:
            out["digits"] = int(q.get("digits", 6))
            out["period"] = int(q.get("period", 30))
        except ValueError:
            raise ValueError("That 2FA link isn't valid.") from None
        out["algorithm"] = q.get("algorithm", "SHA1").upper()
    secret = re.sub(r"[\s-]", "", text).upper().rstrip("=")
    if (not re.fullmatch(r"[A-Z2-7]{16,}", secret) or out["algorithm"] not in _ALGS
            or out["digits"] not in (6, 7, 8) or not 10 <= out["period"] <= 300):
        raise ValueError("That isn't a 2FA secret. Paste the setup key or the otpauth:// link.")
    out["secret"] = secret
    return out


def code(spec: dict | str, now: float | None = None) -> tuple[str, int]:
    """The current code and the seconds it stays valid."""
    s = parse(spec) if isinstance(spec, str) else spec
    t = time.time() if now is None else now
    key = base64.b32decode(s["secret"] + "=" * (-len(s["secret"]) % 8))
    mac = hmac.new(key, struct.pack(">Q", int(t // s["period"])), _ALGS[s["algorithm"]]).digest()
    o = mac[-1] & 0x0F
    n = (struct.unpack(">I", mac[o:o + 4])[0] & 0x7FFFFFFF) % 10 ** s["digits"]
    return str(n).zfill(s["digits"]), s["period"] - int(t) % s["period"]
