"""
Download a document's files in another format: PDF, Word (.docx), PNG or JPEG.

A PDF or Word file puts every page on A4 like a photocopy: card-shaped pages
(an ID's front and back) at real ID-card size, two to a page; anything else
fits the page. Windows' own imaging converts the pictures and renders PDFs.
The phone does the same in DocsBridge.kt (export).
"""

from __future__ import annotations

import asyncio
import io
import struct
import zipfile

A4 = (595.28, 841.89)          # points
MARGIN = 36.0
CARD = (242.65, 153.07)        # ID-1 card, 85.6 x 54 mm
FORMATS = {"pdf": ("pdf", "application/pdf"), "docx": ("docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
           "png": ("png", "image/png"), "jpeg": ("jpg", "image/jpeg")}


def is_card(w: int, h: int) -> bool:
    """Shaped like an ID card (front or back), lying down."""
    return 1.45 <= w / h <= 1.72


# ---- converting pictures (Windows Imaging) ---------------------------------------
async def _stream(data: bytes):
    from winrt.windows.storage.streams import DataWriter, InMemoryRandomAccessStream
    s = InMemoryRandomAccessStream()
    w = DataWriter(s)
    w.write_bytes(data)
    await w.store_async()
    w.detach_stream()
    s.seek(0)
    return s


async def _read(stream) -> bytes:
    from winrt.windows.storage.streams import DataReader
    stream.seek(0)
    r = DataReader(stream.get_input_stream_at(0))
    n = await r.load_async(stream.size)
    buf = bytearray(n)
    r.read_bytes(buf)
    return bytes(buf)


async def _encode(data: bytes, png: bool) -> bytes:
    from winrt.windows.graphics.imaging import BitmapAlphaMode, BitmapDecoder, BitmapEncoder, BitmapPixelFormat
    from winrt.windows.storage.streams import InMemoryRandomAccessStream
    dec = await BitmapDecoder.create_async(await _stream(data))
    bmp = await dec.get_software_bitmap_converted_async(BitmapPixelFormat.BGRA8,
                                                        BitmapAlphaMode.STRAIGHT if png else BitmapAlphaMode.IGNORE)
    out = InMemoryRandomAccessStream()
    enc = await BitmapEncoder.create_async(BitmapEncoder.png_encoder_id if png else BitmapEncoder.jpeg_encoder_id, out)
    enc.set_software_bitmap(bmp)
    await enc.flush_async()
    return await _read(out)


async def _pdf_pages(data: bytes, width: int = 1700) -> list[bytes]:
    from winrt.windows.data.pdf import PdfDocument, PdfPageRenderOptions
    from winrt.windows.storage.streams import InMemoryRandomAccessStream
    doc = await PdfDocument.load_from_stream_async(await _stream(data))
    pages = []
    for i in range(doc.page_count):
        out = InMemoryRandomAccessStream()
        opts = PdfPageRenderOptions()
        opts.destination_width = width
        await doc.get_page(i).render_with_options_to_stream_async(out, opts)
        pages.append(await _read(out))
    return pages


def _run(coro):
    try:
        return asyncio.run(coro)
    except (ImportError, OSError) as exc:
        raise RuntimeError("Windows couldn't convert that file.") from exc


def jpeg_pages(data: bytes) -> list[bytes]:
    """Every page of a photo or PDF, as JPEG."""
    async def go():
        sources = await _pdf_pages(data) if data[:4] == b"%PDF" else [data]
        return [s if s[:2] == b"\xff\xd8" else await _encode(s, png=False) for s in sources]
    return _run(go())


def picture(data: bytes, fmt: str) -> bytes:
    """One picture as PNG or JPEG (a PDF's first page)."""
    async def go():
        src = (await _pdf_pages(data))[0] if data[:4] == b"%PDF" else data
        return await _encode(src, png=fmt == "png")
    return _run(go())


def jpeg_size(b: bytes) -> tuple[int, int]:
    """(width, height) from a JPEG's frame header."""
    i = 2
    while i + 9 < len(b):
        if b[i] != 0xFF:
            i += 1
            continue
        marker = b[i + 1]
        if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            h, w = struct.unpack(">HH", b[i + 5:i + 9])
            return w, h
        i += 2 + struct.unpack(">H", b[i + 2:i + 4])[0]
    raise ValueError("not a JPEG")


# ---- laying pages out on A4 -------------------------------------------------------
def layout(sizes: list[tuple[int, int]]) -> list[list[tuple[int, float, float, float, float]]]:
    """Sheets of (picture index, x, y from the top, width, height) in points."""
    sheets, i = [], 0
    while i < len(sizes):
        w, h = sizes[i]
        if is_card(w, h):
            cards = [i] + ([i + 1] if i + 1 < len(sizes) and is_card(*sizes[i + 1]) else [])
            x = (A4[0] - CARD[0]) / 2
            sheets.append([(k, x, MARGIN * 2 + n * (CARD[1] + MARGIN), *CARD) for n, k in enumerate(cards)])
            i += len(cards)
            continue
        s = min((A4[0] - 2 * MARGIN) / w, (A4[1] - 2 * MARGIN) / h)
        sheets.append([(i, (A4[0] - w * s) / 2, MARGIN, w * s, h * s)])
        i += 1
    return sheets


def to_pdf(jpegs: list[bytes]) -> bytes:
    sizes = [jpeg_size(j) for j in jpegs]
    objs: list[bytes] = [b"<< /Type /Catalog /Pages 2 0 R >>", b""]
    def add(body: bytes) -> int:
        objs.append(body)
        return len(objs)
    images = [add(b"<< /Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB "
                  b"/BitsPerComponent 8 /Filter /DCTDecode /Length %d >>\nstream\n" % (w, h, len(j)) + j + b"\nendstream")
              for j, (w, h) in zip(jpegs, sizes)]
    kids = []
    for sheet in layout(sizes):
        ops = b"".join(b"q %.2f 0 0 %.2f %.2f %.2f cm /I%d Do Q\n" % (w, h, x, A4[1] - y - h, k)
                       for k, x, y, w, h in sheet)
        content = add(b"<< /Length %d >>\nstream\n" % len(ops) + ops + b"endstream")
        res = b" ".join(b"/I%d %d 0 R" % (k, images[k]) for k, *_ in sheet)
        kids.append(add(b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.2f %.2f] /Resources << /XObject << %s >> >> "
                        b"/Contents %d 0 R >>" % (A4[0], A4[1], res, content)))
    objs[1] = b"<< /Type /Pages /Kids [%s] /Count %d >>" % (b" ".join(b"%d 0 R" % k for k in kids), len(kids))
    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for n, body in enumerate(objs, 1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % n + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1) + b"".join(b"%010d 00000 n \n" % o for o in offsets)
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
    return bytes(out)


def to_docx(jpegs: list[bytes]) -> bytes:
    """A Word document with each page's picture (cards at card size)."""
    emu = 12700                                                    # per point
    body = []
    for n, j in enumerate(jpegs, 1):
        w, h = jpeg_size(j)
        if is_card(w, h):
            cw, ch = CARD
        else:
            s = min((A4[0] - 2 * 72) / w, (A4[1] - 2 * 72) / h)    # Word's default 1-inch margins
            cw, ch = w * s, h * s
        cx, cy = int(cw * emu), int(ch * emu)
        body.append(
            f'<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing><wp:inline><wp:extent cx="{cx}" cy="{cy}"/>'
            f'<wp:docPr id="{n}" name="Page {n}"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
            f'<pic:pic><pic:nvPicPr><pic:cNvPr id="{n}" name="page{n}.jpg"/><pic:cNvPicPr/></pic:nvPicPr>'
            f'<pic:blipFill><a:blip r:embed="rId{n}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
            f'<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
            f'</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>')
    ns = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
          'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
          'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
          'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"')
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml",
                   '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                   '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                   '<Default Extension="xml" ContentType="application/xml"/><Default Extension="jpg" ContentType="image/jpeg"/>'
                   '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
        z.writestr("_rels/.rels",
                   '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
        z.writestr("word/_rels/document.xml.rels",
                   '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   + "".join(f'<Relationship Id="rId{n}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
                             f'Target="media/page{n}.jpg"/>' for n in range(1, len(jpegs) + 1)) + "</Relationships>")
        z.writestr("word/document.xml",
                   f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {ns}><w:body>{"".join(body)}'
                   '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>'
                   '</w:body></w:document>')
        for n, j in enumerate(jpegs, 1):
            z.writestr(f"word/media/page{n}.jpg", j)
    return out.getvalue()


def export(files: list[bytes], fmt: str) -> bytes:
    """All the files as one PDF or Word document, or the first as PNG/JPEG."""
    if fmt in ("png", "jpeg"):
        return picture(files[0], fmt)
    pages = [p for f in files for p in jpeg_pages(f)]
    return to_pdf(pages) if fmt == "pdf" else to_docx(pages)
