"""Personal documents: passports, ID cards, visas, licences, contracts...

* Files (photos, PDFs) are stored next to the vault, one encrypted file each.
  Every file has its own random AES-256-GCM key, kept inside the vault entry
  that owns it, so a file is exactly as protected as the vault, and changing
  the master password never has to touch the files.
* read_details() pulls the type, holder, number and dates out of a document's
  text: from the machine-readable zone (the <<< lines on passports and many
  ID cards, checked with its check digits) or, failing that, from dates next
  to words like "expiry".
* Reminders: each document lists how long before expiry to remind you. The
  schedule is kept in a small file outside the vault (so reminders still show
  while MyVault is locked) holding only the date, the type and the name you
  chose for reminders: never the number, holder or anything else.
"""

from __future__ import annotations

import base64
import datetime as dt
import json
import os
import re
import uuid
from pathlib import Path

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from . import paths

DOC_TYPES = ("passport", "id_card", "residence", "visa", "driving_license",
             "car_registration", "rental", "insurance", "other")
TYPE_LABELS = {"passport": "Passport", "id_card": "ID card", "residence": "Residence permit",
               "visa": "Visa", "driving_license": "Driving licence", "car_registration": "Car registration",
               "rental": "Rental contract", "insurance": "Insurance", "other": "Document"}
REMIND_PRESETS = (1, 3, 7, 14, 30, 60, 90, 180, 365)       # days before expiry
MAX_FILE = 20 * 1024 * 1024
_ID = re.compile(r"^[0-9a-f]{32}$")


# ---- encrypted files ----------------------------------------------------------
def files_dir() -> Path:
    d = paths.data_dir() / "files"
    d.mkdir(exist_ok=True)
    return d


def _blob_path(file_id: str) -> Path:
    if not _ID.match(file_id or ""):
        raise ValueError("bad file id")
    return files_dir() / f"{file_id}.bin"


def sniff_mime(data: bytes) -> str:
    if data[:3] == b"\xff\xd8\xff":
        return "image/jpeg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    if data[:4] == b"%PDF":
        return "application/pdf"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return ""


def seal(data: bytes, name: str) -> dict:
    """Encrypt and store a document file. Returns the reference kept in the entry."""
    if len(data) > MAX_FILE:
        raise ValueError(f"That file is over {MAX_FILE // (1024 * 1024)} MB.")
    mime = sniff_mime(data)
    if not mime:
        raise ValueError("Only photos (JPG, PNG, WebP) and PDFs can be added.")
    file_id, key, nonce = uuid.uuid4().hex, os.urandom(32), os.urandom(12)
    blob = nonce + AESGCM(key).encrypt(nonce, data, file_id.encode())
    _write_blob(file_id, blob)
    return {"id": file_id, "name": os.path.basename(name)[:120] or "document", "mime": mime,
            "size": len(data), "key": base64.b64encode(key).decode()}


def _write_blob(file_id: str, blob: bytes) -> None:
    p = _blob_path(file_id)
    tmp = p.with_suffix(".part")
    tmp.write_bytes(blob)
    os.replace(tmp, p)


def open_sealed(ref: dict, blob: bytes | None = None) -> bytes:
    """The plain file. Raises ValueError if it's missing or doesn't match its key."""
    if blob is None:
        p = _blob_path(ref["id"])
        if not p.exists():
            raise ValueError("That file isn't on this device yet. Sync with the device that has it.")
        blob = p.read_bytes()
    try:
        return AESGCM(base64.b64decode(ref["key"])).decrypt(blob[:12], blob[12:], ref["id"].encode())
    except (InvalidTag, ValueError, KeyError) as exc:
        raise ValueError("That file is damaged.") from exc


def have(file_id: str) -> bool:
    try:
        return _blob_path(file_id).exists()
    except ValueError:
        return False


def read_blob(file_id: str) -> bytes:
    return _blob_path(file_id).read_bytes()


def store_blob(ref: dict, blob: bytes) -> None:
    """Keep a file received from another device, after checking it opens with its key."""
    open_sealed(ref, blob)
    _write_blob(ref["id"], blob)


def refs(entry_fields: dict) -> list[dict]:
    try:
        out = json.loads(entry_fields.get("files") or "[]")
    except ValueError:
        return []
    return [r for r in out if isinstance(r, dict) and _ID.match(str(r.get("id", ""))) and r.get("key")]


def cleanup(entries) -> int:
    """Delete stored files no live document refers to (removed, or entry deleted)."""
    keep = {r["id"] for e in entries if not e.deleted and e.kind == "document" for r in refs(e.fields)}
    gone = 0
    for p in files_dir().glob("*.bin"):
        if p.stem not in keep:
            p.unlink(missing_ok=True)
            gone += 1
    return gone


# ---- reminders --------------------------------------------------------------------
def lead_label(days: int) -> str:
    named = {1: "1 day", 7: "1 week", 14: "2 weeks", 30: "1 month", 60: "2 months", 90: "3 months",
             180: "6 months", 365: "1 year"}
    return named.get(days, f"{days} days")


def parse_date(s: str) -> dt.date | None:
    try:
        return dt.date.fromisoformat((s or "").strip())
    except ValueError:
        return None


def remind_days(entry_fields: dict) -> list[int]:
    out = set()
    for part in str(entry_fields.get("remind", "")).split(","):
        if part.strip().isdigit() and 0 < int(part) <= 3650:
            out.add(int(part))
    return sorted(out, reverse=True)


def schedule(entries) -> list[dict]:
    """Every reminder of every live document: the day it's due, plus what the
    notification may say (type and the name you chose, nothing else)."""
    out = []
    for e in entries:
        if e.deleted or e.kind != "document":
            continue
        expires = parse_date(e.fields.get("expires", ""))
        days = remind_days(e.fields)
        if not expires or not days:
            continue
        name = str(e.fields.get("remind_name", "")).strip()[:40]
        doc_type = e.fields.get("doc_type") if e.fields.get("doc_type") in DOC_TYPES else "other"
        for d in days + [0]:                      # and on the day itself
            out.append({"key": f"{e.id}:{expires.isoformat()}:{d}", "entry": e.id,
                        "on": (expires - dt.timedelta(days=d)).isoformat(),
                        "expires": expires.isoformat(), "days": d, "type": doc_type, "name": name})
    return sorted(out, key=lambda r: r["on"])


def due(plan: list[dict], today: dt.date, shown: set[str]) -> list[dict]:
    """Reminders to show now: due and not shown yet, the latest one per document
    (if MyVault was off for a while you get one notice, not a pile)."""
    best: dict[str, dict] = {}
    done: dict[str, int] = {}                 # per document: the latest reminder already shown
    for r in plan:
        on, expires = parse_date(r["on"]), parse_date(r["expires"])
        if not on or not expires or not on <= today <= expires:
            continue
        if r["key"] in shown:
            done[r["entry"]] = min(done.get(r["entry"], 99999), r["days"])
        elif r["entry"] not in best or r["days"] < best[r["entry"]]["days"]:
            best[r["entry"]] = r
    # an earlier reminder never comes after a later one has been shown
    return [r for r in best.values() if r["days"] < done.get(r["entry"], 99999)]


def reminder_text(r: dict, tr=lambda s: s) -> str:
    """What a notification says, e.g. "Passport expires in 1 month." (tr: translate)."""
    name = r.get("name") or tr(TYPE_LABELS.get(r.get("type"), "Document"))
    return tr(f"{name} expires today.") if r["days"] == 0 else tr(f"{name} expires in {lead_label(r['days'])}.")


def schedule_file() -> Path:
    return paths.data_dir() / "reminders.json"


def save_schedule(entries) -> None:
    p = schedule_file()
    tmp = p.with_suffix(".part")
    tmp.write_text(json.dumps(schedule(entries)), "utf-8")
    os.replace(tmp, p)


def load_schedule() -> list[dict]:
    try:
        return json.loads(schedule_file().read_text("utf-8"))
    except (OSError, ValueError):
        return []


# ---- reading details from a document's text ---------------------------------------
_W = (7, 3, 1)
_FIX_DIGIT = str.maketrans("OQDIZSBGL", "001125861")


def _check(s: str) -> int:
    total = 0
    for i, c in enumerate(s):
        v = int(c) if c.isdigit() else (ord(c) - 55 if "A" <= c <= "Z" else 0)
        total += v * _W[i % 3]
    return total % 10


def _field(s: str, digit: str, numeric: bool) -> str | None:
    """A field with its check digit; tries the usual OCR mix-ups (O/0, I/1...)."""
    for cand in ((s, digit), (s.translate(_FIX_DIGIT) if numeric else s, digit.translate(_FIX_DIGIT))):
        f, d = cand
        if d.isdigit() and _check(f) == int(d):
            return f
    return None


def _yymmdd(s: str, future: bool) -> str:
    try:
        y, m, d = int(s[:2]), int(s[2:4]), int(s[4:6])
        year = 2000 + y if future or y <= dt.date.today().year % 100 else 1900 + y
        return dt.date(year, m, d).isoformat()
    except ValueError:
        return ""


def _name(s: str) -> str:
    surname, _, given = s.strip("<").partition("<<")
    return " ".join(p.replace("<", " ").strip().title() for p in (given, surname) if p.strip("<"))


def _mrz_lines(text: str) -> list[str]:
    out = []
    for raw in text.upper().splitlines():
        line = re.sub(r"\s+", "", raw).replace("«", "<")
        if len(line) >= 28 and re.fullmatch(r"[A-Z0-9<]+", line) and line.count("<") >= 2:
            out.append(line)
    return out


def _kind(code: str) -> str:
    c = code[:1]
    return {"P": "passport", "V": "visa"}.get(c, "id_card" if c in "IAC" else "other")


def read_mrz(text: str) -> dict:
    lines = _mrz_lines(text)
    for width, rows in ((44, 2), (36, 2), (30, 3)):
        fit = [ln.ljust(width, "<")[:width] for ln in lines if abs(len(ln) - width) <= 3]
        for i in range(len(fit) - rows + 1):
            block = fit[i:i + rows]
            got = (_td1 if rows == 3 else _td23)(block)
            if got.get("expires"):
                got["how"] = "mrz"
                return got
    return {}


def _td23(b: list[str]) -> dict:
    l1, l2 = b
    number = _field(l2[0:9], l2[9], False)
    birth = _field(l2[13:19], l2[19], True)
    expiry = _field(l2[21:27], l2[27], True)
    out = {"doc_type": _kind(l1[:2]), "country": l1[2:5].strip("<"), "holder": _name(l1[5:])}
    if number:
        out["number"] = number.strip("<")
    if birth:
        out["birth"] = _yymmdd(birth, False)
    if expiry:
        out["expires"] = _yymmdd(expiry, True)
    return out


def _td1(b: list[str]) -> dict:
    l1, l2, l3 = b
    number = _field(l1[5:14], l1[14], False)
    birth = _field(l2[0:6], l2[6], True)
    expiry = _field(l2[8:14], l2[14], True)
    out = {"doc_type": _kind(l1[:2]), "country": l1[2:5].strip("<"), "holder": _name(l3)}
    if number:
        out["number"] = number.strip("<")
    if birth:
        out["birth"] = _yymmdd(birth, False)
    if expiry:
        out["expires"] = _yymmdd(expiry, True)
    return out


_MONTHS = {m: i for i, m in enumerate(
    "jan feb mar apr may jun jul aug sep oct nov dec".split(), 1)}
_EXPIRY = re.compile(r"expir|valid\s*(until|thru|through|to)|end\s*date|انتهاء|صالح[ةه]?\s*(حتى|لغاية)|ينتهي", re.I)
_ISSUE = re.compile(r"issue|start\s*date|إصدار|الإصدار|تحرير", re.I)
_BIRTH = re.compile(r"birth|born|dob|ميلاد|الولادة", re.I)
_NUMBER = re.compile(r"(?:no\.?|number|num\.?|رقم)\s*[:.#]?\s*([A-Z0-9][A-Z0-9-]{4,17})", re.I)
_TYPES = [("passport", r"passport|جواز"), ("visa", r"\bvisa\b|تأشيرة"),
          ("driving_license", r"driv\w*\s*licen[cs]e|رخصة\s*(ال)?قيادة|رخصة\s*سوق"),
          ("car_registration", r"vehicle|registration|رخصة\s*(ال)?مركبة|ترخيص"),
          ("rental", r"lease|tenan|rent|إيجار|استئجار"), ("residence", r"residen|إقامة"),
          ("insurance", r"insurance|تأمين"), ("id_card", r"identity|national\s*id|\bid\s*card|هوية|بطاقة\s*شخصية")]


def _dates(text: str):
    """(position, iso date) for every date-looking thing in the text."""
    pats = [
        (r"\b(\d{4})[./-](\d{1,2})[./-](\d{1,2})\b", lambda g: (g[0], g[1], g[2])),
        (r"\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b", lambda g: (g[2], g[1], g[0])),
        (r"\b(\d{1,2})\s*([A-Za-z]{3})[a-z]*\.?,?\s*(\d{4})\b", lambda g: (g[2], _MONTHS.get(g[1].lower()), g[0])),
        (r"\b([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})\b", lambda g: (g[2], _MONTHS.get(g[0].lower()), g[1])),
    ]
    for rx, order in pats:
        for m in re.finditer(rx, text):
            y, mo, d = order(m.groups())
            try:
                y, mo, d = int(y), int(mo or 0), int(d)
                if mo > 12 >= d:                 # month-first (US) date
                    mo, d = d, mo
                yield m.start(), dt.date(y, mo, d).isoformat()
            except (TypeError, ValueError):
                continue


def read_details(text: str, today: dt.date | None = None) -> dict:
    """Best guesses from a document's text; the person checks them before saving."""
    today = today or dt.date.today()
    text = text.translate(str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789"))
    found = read_mrz(text)
    if found:
        found.pop("birth", None)
        found.setdefault("issued", "")
    else:
        found = {"how": "text"}
    for kind, rx in _TYPES:
        if "doc_type" not in found and re.search(rx, text, re.I):
            found["doc_type"] = kind
    labelled = {}
    for pos, iso in _dates(text):
        # The nearest label before the date, on its line or the one above.
        before = text[max(0, pos - 50):pos]
        hits = [(m.end(), label) for label, rx in (("expires", _EXPIRY), ("issued", _ISSUE), ("birth", _BIRTH))
                for m in rx.finditer(before)]
        if hits:
            labelled.setdefault(max(hits)[1], iso)
        else:
            labelled.setdefault("other", []).append(iso)
    if not found.get("expires"):
        if "expires" in labelled:
            found["expires"] = labelled["expires"]
        else:                                    # no label: the latest date still to come
            future = sorted(d for d in labelled.get("other", []) if d > today.isoformat())
            if future:
                found["expires"] = future[-1]
                found["guessed"] = True
    if not found.get("issued") and "issued" in labelled:
        found["issued"] = labelled["issued"]
    if "number" not in found:
        m = _NUMBER.search(text)
        if m and re.search(r"\d", m.group(1)):
            found["number"] = m.group(1)
    return {k: v for k, v in found.items() if v not in ("", None)}


# ---- reading text from a scan (Windows' built-in, offline OCR) -----------------
def ocr(data: bytes) -> str:
    """The text of a photo, or of a PDF's first page. Windows only; raises
    RuntimeError if Windows can't read it."""
    import asyncio

    async def run() -> str:
        from winrt.windows.graphics.imaging import BitmapDecoder
        from winrt.windows.media.ocr import OcrEngine
        from winrt.windows.storage.streams import DataWriter, InMemoryRandomAccessStream

        async def stream_of(raw: bytes):
            s = InMemoryRandomAccessStream()
            w = DataWriter(s)
            w.write_bytes(raw)
            await w.store_async()
            w.detach_stream()
            s.seek(0)
            return s

        src = await stream_of(data)
        if sniff_mime(data) == "application/pdf":
            from winrt.windows.data.pdf import PdfDocument, PdfPageRenderOptions
            doc = await PdfDocument.load_from_stream_async(src)
            page = doc.get_page(0)
            png = InMemoryRandomAccessStream()
            opts = PdfPageRenderOptions()
            opts.destination_width = 2000        # sharp enough for small print
            await page.render_with_options_to_stream_async(png, opts)
            png.seek(0)
            src = png
        bitmap = await (await BitmapDecoder.create_async(src)).get_software_bitmap_async()
        if max(bitmap.pixel_width, bitmap.pixel_height) > OcrEngine.max_image_dimension:
            raise RuntimeError("That image is too large to read. Try a smaller photo.")
        texts = []
        for lang in OcrEngine.available_recognizer_languages:   # each installed one, e.g. English and Arabic
            engine = OcrEngine.try_create_from_language(lang)
            if engine is not None:
                result = await engine.recognize_async(bitmap)
                texts.append("\n".join(line.text for line in result.lines))
        if not texts:
            raise RuntimeError("Windows has no text-reading language installed.")
        return "\n".join(texts)

    try:
        return asyncio.run(run())
    except ImportError as exc:
        raise RuntimeError("Reading documents needs Windows 10 or later.") from exc
    except OSError as exc:
        raise RuntimeError("Windows couldn't read that file.") from exc


def preview_png(data: bytes, width: int = 900) -> bytes:
    """A PDF's first page as PNG, for showing it in the app (Windows only)."""
    import asyncio

    async def run() -> bytes:
        from winrt.windows.data.pdf import PdfDocument, PdfPageRenderOptions
        from winrt.windows.storage.streams import DataReader, DataWriter, InMemoryRandomAccessStream
        src = InMemoryRandomAccessStream()
        w = DataWriter(src)
        w.write_bytes(data)
        await w.store_async()
        w.detach_stream()
        src.seek(0)
        page = (await PdfDocument.load_from_stream_async(src)).get_page(0)
        out = InMemoryRandomAccessStream()
        opts = PdfPageRenderOptions()
        opts.destination_width = width
        await page.render_with_options_to_stream_async(out, opts)
        out.seek(0)
        r = DataReader(out.get_input_stream_at(0))
        n = await r.load_async(out.size)
        buf = bytearray(n)
        r.read_bytes(buf)
        return bytes(buf)

    try:
        return asyncio.run(run())
    except (ImportError, OSError) as exc:
        raise RuntimeError("Windows couldn't show that PDF.") from exc
