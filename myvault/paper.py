"""
Paper backup: print the whole vault as an encrypted PDF, and read it back.

Nothing on the sheet is readable. Each entry becomes ONE encrypted block
(site names included), printed twice:
  * as text in Base32 (A-Z and 2-7 only, so no 0/O or 1/l mix-ups when typed), and
  * as a QR code, which the phone app can scan to restore from paper.

Block (binary, then Base32):
    b"MVP1" | salt(16) | nonce(12) | AES-256-GCM(entry JSON, aad=b"MVP1"+salt)
Key = scrypt(backup password, salt, N=2^17, r=8, p=1). That's stronger than the
vault file's KDF on purpose: a paper copy can be photographed and attacked
offline forever. The salt sits in every block, so one torn page doesn't stop
the others from decrypting.

The PDF is written by hand here (uncompressed text, built-in Courier and
Helvetica), so reading it back is just pulling our own text out again.
See VAULT_FORMAT.md.
"""

from __future__ import annotations

import base64
import json
import os
import re
import time
import zlib

import segno
from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

MAGIC = b"MVP1"
N, R, P = 2 ** 17, 8, 1
GROUP, GROUPS_PER_LINE = 4, 10          # "ABCD EFGH ..." 40 chars a line
FOOTER = "MyVault encrypted backup  -"
MARK_RE = re.compile(r"^ENTRY (\d+) / (\d+)$")
B32_LINE_RE = re.compile(r"^[A-Z2-7 ]+$")


class BackupError(Exception):
    pass


def derive_key(password: str, salt: bytes) -> bytes:
    return Scrypt(salt=salt, length=32, n=N, r=R, p=P).derive(password.encode("utf-8"))


def _compact(entry: dict) -> dict:
    """Drop empty values so blocks (and QR codes) stay small."""
    return {k: v for k, v in entry.items() if v not in ("", {}, [], None)}


def encrypt_entries(entries: list[dict], password: str) -> list[str]:
    salt = os.urandom(16)
    key = derive_key(password, salt)
    aes = AESGCM(key)
    blocks = []
    for e in entries:
        nonce = os.urandom(12)
        body = zlib.compress(json.dumps(_compact(e), separators=(",", ":")).encode("utf-8"), 9)
        ct = aes.encrypt(nonce, body, MAGIC + salt)
        blocks.append(base64.b32encode(MAGIC + salt + nonce + ct).decode("ascii").rstrip("="))
    return blocks


def decrypt_blocks(blocks: list[str], password: str) -> tuple[list[dict], int]:
    """Returns (entries, unreadable_count). Raises BackupError if the password is
    wrong for every block."""
    keys: dict[bytes, bytes] = {}
    out, bad = [], 0
    for b32 in blocks:
        clean = re.sub(r"[^A-Z2-7]", "", b32.upper())
        try:
            raw = base64.b32decode(clean + "=" * (-len(clean) % 8))
        except ValueError:
            bad += 1
            continue
        if raw[:4] != MAGIC or len(raw) < 4 + 16 + 12 + 16:
            bad += 1
            continue
        salt, nonce, ct = raw[4:20], raw[20:32], raw[32:]
        if salt not in keys:
            keys[salt] = derive_key(password, salt)
        try:
            body = AESGCM(keys[salt]).decrypt(nonce, ct, MAGIC + salt)
            out.append(json.loads(zlib.decompress(body).decode("utf-8")))
        except (InvalidTag, ValueError, zlib.error):
            bad += 1
    if blocks and not out:
        raise BackupError("Wrong backup password, or this isn't a MyVault backup.")
    return out, bad


def _groups(b32: str) -> list[str]:
    g = [b32[i:i + GROUP] for i in range(0, len(b32), GROUP)]
    return [" ".join(g[i:i + GROUPS_PER_LINE]) for i in range(0, len(g), GROUPS_PER_LINE)]


# ---- a tiny PDF writer ---------------------------------------------------------
A4 = (595.0, 842.0)
MARGIN = 48.0


def _esc(text: str) -> str:
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


class _Page:
    def __init__(self):
        self.ops: list[str] = []

    def text(self, x, y, s, font="F1", size=9.0, gray=0.1):
        self.ops.append(f"{gray} g BT /{font} {size} Tf {x:.2f} {y:.2f} Td ({_esc(s)}) Tj ET")

    def rect(self, x, y, w, h, gray=0.0):
        self.ops.append(f"{gray} g {x:.2f} {y:.2f} {w:.2f} {h:.2f} re f")

    def line(self, x1, y1, x2, y2, width=0.4, rgb=(0.18, 0.29, 0.48)):
        r, g, b = rgb
        self.ops.append(f"{r} {g} {b} RG {width} w {x1:.2f} {y1:.2f} m {x2:.2f} {y2:.2f} l S")

    def qr(self, x, y, size, qr):
        rows = [list(r) for r in qr.matrix]
        n = len(rows)
        m = size / n
        for ry, row in enumerate(rows):
            cx = 0
            while cx < n:                       # merge horizontal runs into one rect
                if row[cx]:
                    start = cx
                    while cx < n and row[cx]:
                        cx += 1
                    self.rect(x + start * m, y + size - (ry + 1) * m, (cx - start) * m, m, 0.0)
                else:
                    cx += 1


def _tint(page: _Page, y_top: float, height: float) -> None:
    """Security-envelope tint band: fine diagonal linework."""
    x0, x1 = MARGIN, A4[0] - MARGIN
    step = 3.2
    x = x0 - height
    while x < x1:
        a, b = max(x, x0), min(x + height, x1)
        page.line(a, y_top - (a - x), b, y_top - (b - x), 0.35)
        x += step


def _crosshairs(page: _Page) -> None:
    w, h = A4
    for cx, cy in ((24, 24), (w - 24, 24), (24, h - 24), (w - 24, h - 24)):
        page.line(cx - 7, cy, cx + 7, cy, 0.5, (0.1, 0.1, 0.1))
        page.line(cx, cy - 7, cx, cy + 7, 0.5, (0.1, 0.1, 0.1))


def _write_pdf(pages: list[_Page]) -> bytes:
    objs: list[bytes] = []
    def add(body: str | bytes) -> int:
        objs.append(body.encode("latin-1") if isinstance(body, str) else body)
        return len(objs)
    add("<< /Type /Catalog /Pages 2 0 R >>")
    add("")                                           # pages tree, filled below
    f1 = add("<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>")
    f2 = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    f3 = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>")
    kids = []
    for p in pages:
        stream = "\n".join(p.ops).encode("latin-1")
        c = add(b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream")
        kids.append(add(
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {A4[0]:.0f} {A4[1]:.0f}] "
            f"/Resources << /Font << /F1 {f1} 0 R /F2 {f2} 0 R /F3 {f3} 0 R >> >> /Contents {c} 0 R >>"))
    objs[1] = (f"<< /Type /Pages /Kids [{' '.join(f'{k} 0 R' for k in kids)}] "
               f"/Count {len(kids)} >>").encode("latin-1")
    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for i, body in enumerate(objs, 1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % i + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
    for off in offsets:
        out += b"%010d 00000 n \n" % off
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
    return bytes(out)


def build_pdf(entries: list[dict], password: str) -> bytes:
    blocks = encrypt_entries(entries, password)
    total = len(blocks)
    when = time.strftime("%d %B %Y")
    pages: list[_Page] = []

    def new_page() -> _Page:
        p = _Page()
        _crosshairs(p)
        p.text(MARGIN, 24, f"{FOOTER}  {when}  -  page {len(pages) + 1}", "F2", 7, 0.45)
        pages.append(p)
        return p

    page = new_page()
    y = A4[1] - MARGIN
    _tint(page, y, 26)
    y -= 50
    page.text(MARGIN, y, "MyVault encrypted backup", "F3", 18)
    y -= 20
    for line in (
        f"{total} entries. Created {when}. Everything below is encrypted, including site names.",
        "Without the backup password this sheet cannot be read.",
        "To restore: on the PC, MyVault > Paper backup > Choose PDF. From paper: the phone app >",
        "Restore from paper, then scan each code. Keep the backup password apart from this sheet.",
    ):
        page.text(MARGIN, y, line, "F2", 9.5, 0.2)
        y -= 13
    y -= 16

    for i, b32 in enumerate(blocks, 1):
        lines = _groups(b32)
        try:
            qr = segno.make(b32, error="m")    # Base32 fits QR alphanumeric mode
            qr_size = max(130.0, min(220.0, len(qr.matrix) * 2.0))   # >=0.7 mm modules on paper
        except segno.DataOverflowError:
            qr = None                         # ponytail: huge entry (big RSA key) is text-only
            qr_size = 0.0
        block_h = max(16 + len(lines) * 11.5, qr_size + 16) + 22
        if y - min(block_h, 300) < MARGIN + 20:
            page = new_page()
            y = A4[1] - MARGIN
        page.line(MARGIN, y, A4[0] - MARGIN, y, 0.4, (0.6, 0.62, 0.66))
        y -= 16
        page.text(MARGIN, y, f"ENTRY {i} / {total}", "F3", 9, 0.1)
        if qr is not None:
            page.qr(A4[0] - MARGIN - qr_size, y - qr_size + 6, qr_size, qr)
        qr_bottom = y - qr_size
        ty = y - 16
        for line in lines:
            if ty < MARGIN + 20:              # long block: continue on the next page
                page = new_page()
                ty = A4[1] - MARGIN
                qr_bottom = ty
            page.text(MARGIN, ty, line, "F1", 9.5, 0.08)
            ty -= 11.5
        if qr is None:
            page.text(MARGIN, ty - 4, "(too large for a QR code; restore this one from the PDF file or type it in)", "F2", 7.5, 0.45)
            ty -= 12
        y = min(ty, qr_bottom) - 10
    return _write_pdf(pages)


# ---- reading it back -----------------------------------------------------------
_TJ_RE = re.compile(rb"\(((?:\\.|[^\\)])*)\)\s*Tj")


def _unesc(raw: bytes) -> str:
    return re.sub(rb"\\(.)", rb"\1", raw).decode("latin-1")


def extract_blocks(pdf_or_text: bytes | str) -> list[str]:
    """Pull the Base32 blocks out of one of our PDFs (or pasted plain text)."""
    if isinstance(pdf_or_text, bytes) and pdf_or_text.startswith(b"%PDF"):
        lines = [_unesc(m.group(1)) for m in _TJ_RE.finditer(pdf_or_text)]
    else:
        text = pdf_or_text.decode("utf-8", "replace") if isinstance(pdf_or_text, bytes) else pdf_or_text
        lines = [ln.strip() for ln in text.splitlines()]
    blocks, cur = [], None
    for ln in lines:
        if ln.startswith(FOOTER):
            continue                       # page footer inside a block that spans pages
        if MARK_RE.match(ln):
            if cur:
                blocks.append(cur)
            cur = ""
        elif cur is not None and ln and B32_LINE_RE.match(ln):
            cur += ln.replace(" ", "")
        elif cur:
            blocks.append(cur)
            cur = None
    if cur:
        blocks.append(cur)
    return blocks


def read_pdf(data: bytes, password: str) -> tuple[list[dict], int]:
    blocks = extract_blocks(data)
    if not blocks:
        raise BackupError("No MyVault backup blocks found in that file.")
    return decrypt_blocks(blocks, password)
