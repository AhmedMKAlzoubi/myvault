"""
Updates without giving up "everything stays on the device".

A release is a set of packages (the Windows installer, the phone APK) plus a
small manifest listing each file's name, size and SHA-256, signed with MyVault's
Ed25519 update key (kept offline by the maintainer; see tools/make_release_keys.py).
Nothing is ever installed unless the manifest's signature checks out against the
public key below and the file's hash matches the manifest.

Packages reach a device two ways:
  * Over QR sync (sync.py): whichever device has the newer package for the
    other's platform hands it over on the encrypted channel. Fully offline.
  * Online, only if the user said yes: at most once a day the app downloads the
    public latest.json (+ .sig) from GitHub Releases. Nothing about the vault or
    the user is sent; GitHub sees only that someone fetched a public file.

Where packages live:
  bundled: <install dir>/packages/<version>/  (the installer ships the phone APK)
  cache:   %LOCALAPPDATA%/MyVault/packages/<version>/  (received or downloaded)
"""

from __future__ import annotations

import base64
import hashlib
import json
import re
import shutil
import sys
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

from . import __version__, paths

UPDATE_PUBKEY = bytes.fromhex("ac26f647835b4fa6349e66b4646feadf04cba6b42d8efda57fa0404f5a0d547e")
PLATFORM = "windows"
REPO = "AhmedMKAlzoubi/myvault"
LATEST_URL = f"https://github.com/{REPO}/releases/latest/download/latest.json"
ASSET_URL = "https://github.com/" + REPO + "/releases/download/v{version}/{name}"
RELEASES_API = f"https://api.github.com/repos/{REPO}/releases?per_page=30"
MAX_PACKAGE = 200 * 1024 * 1024
_NAME_RE = re.compile(r"^MyVault[A-Za-z0-9._-]{1,80}\.(exe|apk)$")
_VER_RE = re.compile(r"^\d{1,4}\.\d{1,4}\.\d{1,4}$")


class UpdateError(Exception):
    pass


def vtuple(v: str) -> tuple[int, ...]:
    """'0.10.2' -> (0, 10, 2). Anything malformed sorts as oldest."""
    return tuple(int(x) for x in v.split(".")) if v and _VER_RE.match(v) else (0,)


def newer(a: str, b: str) -> bool:
    return vtuple(a) > vtuple(b)


def verify_manifest(manifest: bytes, sig_b64: str) -> dict:
    """Check the Ed25519 signature, then parse. Raises UpdateError."""
    try:
        Ed25519PublicKey.from_public_bytes(UPDATE_PUBKEY).verify(base64.b64decode(sig_b64), manifest)
    except (InvalidSignature, ValueError) as exc:
        raise UpdateError("The update isn't signed by MyVault's update key.") from exc
    m = json.loads(manifest.decode("utf-8"))
    if m.get("app") != "MyVault" or not _VER_RE.match(str(m.get("version", ""))):
        raise UpdateError("That isn't a MyVault release manifest.")
    for plat, f in m.get("files", {}).items():
        if not _NAME_RE.match(str(f.get("name", ""))) or not re.fullmatch(r"[0-9a-f]{64}", str(f.get("sha256", ""))):
            raise UpdateError(f"Bad file entry for {plat} in the manifest.")
    return m


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


@dataclass
class Package:
    platform: str
    version: str
    path: Path
    manifest: bytes
    sig: str


def _install_dir() -> Path:
    return Path(sys.executable).parent if getattr(sys, "frozen", False) else Path(__file__).resolve().parent.parent


def cache_dir() -> Path:
    d = paths.data_dir() / "packages"
    d.mkdir(exist_ok=True)
    return d


_verified: dict[tuple[str, float], bool] = {}


def packages() -> dict[str, Package]:
    """The newest verified package per platform among bundled and cached ones."""
    best: dict[str, Package] = {}
    for root in (_install_dir() / "packages", cache_dir()):
        if not root.is_dir():
            continue
        for mf in root.glob("*/*.json"):
            sig = mf.with_suffix(".sig")
            if not sig.exists():
                continue
            try:
                raw = mf.read_bytes()
                m = verify_manifest(raw, sig.read_text().strip())
            except (UpdateError, OSError, ValueError):
                continue
            for plat, f in m["files"].items():
                p = mf.parent / f["name"]
                if not p.exists() or p.stat().st_size != f.get("size"):
                    continue
                key = (str(p), p.stat().st_mtime)
                if key not in _verified:          # hash each file once per run
                    _verified[key] = sha256_file(p) == f["sha256"]
                if _verified[key] and (plat not in best or newer(m["version"], best[plat].version)):
                    best[plat] = Package(plat, m["version"], p, raw, sig.read_text().strip())
    return best


def offers() -> dict[str, str]:
    """What this device can hand to others: platform -> version."""
    return {plat: p.version for plat, p in packages().items()}


def store(manifest: bytes, sig: str, platform: str, tmp_file: Path) -> Package:
    """Verify a received/downloaded package and keep it in the cache."""
    m = verify_manifest(manifest, sig)
    f = m["files"].get(platform)
    if not f:
        raise UpdateError("The manifest doesn't list that package.")
    if tmp_file.stat().st_size != f["size"] or sha256_file(tmp_file) != f["sha256"]:
        raise UpdateError("The update file is damaged (its fingerprint doesn't match).")
    d = cache_dir() / m["version"]
    d.mkdir(exist_ok=True)
    dest = d / f["name"]
    shutil.move(str(tmp_file), dest)
    stem = f"manifest-{platform}"
    (d / f"{stem}.json").write_bytes(manifest)
    (d / f"{stem}.sig").write_text(sig)
    return Package(platform, m["version"], dest, manifest, sig)


def ready_installer() -> Package | None:
    """A verified Windows installer newer than this app, if one is waiting."""
    p = packages().get(PLATFORM)
    return p if p and newer(p.version, __version__) else None


def _get(url: str, limit: int) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "MyVault-update-check"})
    with urllib.request.urlopen(req, timeout=15) as r:
        data = r.read(limit + 1)
    if len(data) > limit:
        raise UpdateError("Unexpectedly large response.")
    return data


def check_online() -> tuple[dict, bytes, str]:
    """Fetch and verify the latest release manifest from GitHub."""
    raw = _get(LATEST_URL, 64 * 1024)
    sig = _get(LATEST_URL + ".sig", 1024).decode("ascii").strip()
    return verify_manifest(raw, sig), raw, sig


def previous_release(current: str = __version__) -> tuple[dict, bytes, str]:
    """For going back: the newest stable (not pre-release) release older than
    `current` whose signed manifest verifies and has a Windows installer."""
    releases = json.loads(_get(RELEASES_API, 4 * 1024 * 1024))
    tags = {str(r.get("tag_name", "")).removeprefix("v") for r in releases
            if not r.get("draft") and not r.get("prerelease")}
    for v in sorted((t for t in tags if _VER_RE.match(t) and newer(current, t)), key=vtuple, reverse=True)[:5]:
        url = ASSET_URL.format(version=v, name="latest.json")
        try:
            raw = _get(url, 64 * 1024)
            sig = _get(url + ".sig", 1024).decode("ascii").strip()
            m = verify_manifest(raw, sig)
        except (UpdateError, OSError, ValueError):
            continue        # releases before 0.5.0 have no signed manifest: never offered
        if m["version"] == v and PLATFORM in m.get("files", {}):
            return m, raw, sig
    raise UpdateError("There's no earlier signed MyVault release to go back to.")


def download(m: dict, raw: bytes, sig: str, platform: str, progress=None) -> Package:
    f = m["files"][platform]
    if f["size"] > MAX_PACKAGE:
        raise UpdateError("The update is too large.")
    tmp = cache_dir() / (f["name"] + ".part")
    req = urllib.request.Request(ASSET_URL.format(version=m["version"], name=f["name"]),
                                 headers={"User-Agent": "MyVault-update-check"})
    got = 0
    with urllib.request.urlopen(req, timeout=30) as r, open(tmp, "wb") as out:
        while chunk := r.read(1 << 20):
            got += len(chunk)
            if got > f["size"]:
                raise UpdateError("The download is bigger than the manifest says.")
            out.write(chunk)
            if progress:
                progress(got, f["size"])
    return store(raw, sig, platform, tmp)
