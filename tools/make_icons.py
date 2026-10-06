"""Draws the MyVault icon and writes every size the apps need.

    .venv\\Scripts\\python tools\\make_icons.py      (needs Pillow: requirements-dev.txt)

The mark is the security envelope: a paper envelope with the blue tint printed
inside, on an ink tile. Tiny sizes drop the tint so the shape stays crisp.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
INK = (27, 36, 51, 255)        # #1B2433
PAPER = (244, 245, 247, 255)   # #F4F5F7
TINT = (47, 74, 122, 255)      # #2F4A7A
SS = 4                         # supersampling factor


def _waves(d: ImageDraw.ImageDraw, box, pitch, amp, wl, width, color):
    x0, y0, x1, y1 = box
    y = y0 + pitch / 2
    while y < y1:
        pts = [(x, y + amp * math.sin((x - x0) / wl * 2 * math.pi)) for x in range(int(x0), int(x1) + 1, 2)]
        d.line(pts, fill=color, width=width)
        y += pitch


def envelope(size: int, tile: bool = True, scale: float = 0.64, mono: bool = False) -> Image.Image:
    """One icon at `size` px. tile=False draws only the envelope (Android
    adaptive foreground); mono=True draws a white silhouette (themed icons)."""
    S = size * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    small = size <= 32
    if tile:
        d.rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * 0.22), fill=INK)
        if not small:  # a faint tint across the tile itself, kept inside its corners
            layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
            _waves(ImageDraw.Draw(layer), (0, 0, S, S), S * 0.035, S * 0.006, S * 0.11,
                   max(1, int(S * 0.0035)), (126, 152, 204, 70))
            img.alpha_composite(Image.composite(layer, Image.new("RGBA", (S, S)), img.getchannel("A")))
    w, h = S * scale, S * scale * 0.68
    x0, y0 = (S - w) / 2, (S - h) / 2 + S * 0.01
    x1, y1 = x0 + w, y0 + h
    r = S * (0.035 if not small else 0.05)
    body = INK if mono else PAPER
    if mono:
        body = (255, 255, 255, 255)
    d.rounded_rectangle((x0, y0, x1, y1), radius=r, fill=body)
    if not small and not mono:
        # the security tint printed inside the envelope
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).rounded_rectangle((x0, y0, x1, y1), radius=r, fill=255)
        tint = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        _waves(ImageDraw.Draw(tint), (x0, y0 + h * 0.18, x1, y1), h * 0.085, h * 0.02, w * 0.16,
               max(1, int(S * 0.0075)), TINT)
        img.paste(tint, (0, 0), Image.composite(tint, Image.new("RGBA", (S, S)), mask))
    # the flap: a solid paper triangle edged in ink
    apex = (S / 2, y0 + h * 0.58)
    flap = [(x0 + r * 0.3, y0), (x1 - r * 0.3, y0), apex]
    edge = INK if not mono else (0, 0, 0, 0)
    stroke = max(SS, int(S * (0.022 if not small else 0.05)))
    if mono:
        d.line([flap[0], apex, flap[1]], fill=(0, 0, 0, 0), width=stroke)
    else:
        d.polygon(flap, fill=PAPER)
        d.line([flap[0], apex, flap[1]], fill=edge, width=stroke, joint="curve")
    # the padlock that seals the flap, outlined in paper so it reads on the tint
    _lock(d, S / 2, apex[1] - h * 0.05, w * (0.24 if not small else 0.36),
          (255, 255, 255, 255) if mono else INK, (0, 0, 0, 0) if mono else PAPER, mono)
    return img.resize((size, size), Image.LANCZOS)


def _lock(d: ImageDraw.ImageDraw, cx: float, top: float, bw: float, ink, paper, mono: bool) -> None:
    bh = bw * 0.8                       # the body
    sw, t = bw * 0.6, bw * 0.16         # the shackle: width, thickness
    pad = bw * 0.13                     # the paper outline around it all
    body = (cx - bw / 2, top, cx + bw / 2, top + bh)
    shackle = (cx - sw / 2, top - sw * 0.72, cx + sw / 2, top + sw * 0.4)
    for grow, colour in ((pad, paper), (0, ink)):    # (in mono, the outline is cut out)
        d.rounded_rectangle((shackle[0] - grow, shackle[1] - grow, shackle[2] + grow, shackle[3] + grow),
                            radius=sw / 2 + grow, outline=colour, width=int(t + 2 * grow))
        d.rounded_rectangle((body[0] - grow, body[1] - grow, body[2] + grow, body[3] + grow),
                            radius=bw * 0.16 + grow, fill=colour)
    # the keyhole
    hole = (0, 0, 0, 0) if mono else paper
    kr = bw * 0.1
    d.ellipse((cx - kr, top + bh * 0.33 - kr, cx + kr, top + bh * 0.33 + kr), fill=hole)
    d.rectangle((cx - kr * 0.45, top + bh * 0.33, cx + kr * 0.45, top + bh * 0.66), fill=hole)


def save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print("wrote", path.relative_to(ROOT))


def main() -> None:
    assets = ROOT / "assets"
    save(envelope(1024), assets / "icon-1024.png")
    ico_sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    imgs = [envelope(s) for s in ico_sizes]
    imgs[-1].save(assets / "myvault.ico", sizes=[(s, s) for s in ico_sizes], append_images=imgs[:-1])
    print("wrote assets/myvault.ico")
    for s in (16, 32, 48, 128):
        save(envelope(s), ROOT / "browser-extension" / "icons" / f"icon{s}.png")

    res = ROOT / "android_app" / "android" / "app" / "src" / "main" / "res"
    for dens, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        save(envelope(px), res / f"mipmap-{dens}" / "ic_launcher.png")
        fg = int(px * 108 / 48)  # adaptive layers are 108dp; keep the mark inside the 66dp safe zone
        save(envelope(fg, tile=False, scale=0.46), res / f"mipmap-{dens}" / "ic_launcher_foreground.png")
        save(envelope(fg, tile=False, scale=0.46, mono=True), res / f"mipmap-{dens}" / "ic_launcher_monochrome.png")
    (res / "mipmap-anydpi-v26").mkdir(exist_ok=True)
    (res / "mipmap-anydpi-v26" / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        '</adaptive-icon>\n', encoding="utf-8")
    (res / "values" / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#1B2433</color>\n</resources>\n', encoding="utf-8")
    print("wrote adaptive icon xml")


if __name__ == "__main__":
    main()
