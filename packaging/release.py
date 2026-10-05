"""Build a complete MyVault release: phone APK, Windows installer, signed manifest.

    .venv\\Scripts\\python packaging\\release.py --notes "What changed"
    .venv\\Scripts\\python packaging\\release.py --notes "..." --publish   (also uploads to GitHub)

Steps:
  1. Stamp the version from myvault/__init__.py into the phone app.
  2. Build the 64-bit phone APK, signed with the release key (~/.myvault-release).
  3. Build the Windows installer with that APK inside (so the PC can hand it to
     a phone over sync), next to a manifest signed with the update key.
  4. Write dist/release/: the installer, the APK, latest.json and latest.json.sig.
Publishing uploads exactly those four files to a GitHub release v<version>,
which is what the apps' online check reads.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "packaging"))
from cryptography.hazmat.primitives import serialization  # noqa: E402

import build_windows  # noqa: E402
from myvault import __version__, update  # noqa: E402

KEYS = Path.home() / ".myvault-release"
APP = ROOT / "android_app"
OUT = ROOT / "dist" / "release"


def flutter() -> str:
    for cand in (shutil.which("flutter"), str(Path.home() / "dev" / "flutter" / "bin" / "flutter.bat")):
        if cand and Path(cand).exists():
            return cand
    sys.exit("Flutter not found (looked on PATH and in ~/dev/flutter).")


def sign(manifest: dict) -> tuple[bytes, str]:
    key = serialization.load_pem_private_key((KEYS / "update_key.pem").read_bytes(), None)
    pub = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    if pub != update.UPDATE_PUBKEY:
        sys.exit("update_key.pem doesn't match UPDATE_PUBKEY in myvault/update.py.")
    raw = json.dumps(manifest, indent=2).encode("utf-8")
    return raw, base64.b64encode(key.sign(raw)).decode("ascii")


def entry(path: Path) -> dict:
    return {"name": path.name, "size": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def stamp_version() -> None:
    major, minor, patch = (int(x) for x in __version__.split("."))
    code = major * 10000 + minor * 100 + patch
    pub = APP / "pubspec.yaml"
    pub.write_text(re.sub(r"(?m)^version: .*$", f"version: {__version__}+{code}", pub.read_text("utf-8")), "utf-8")
    (APP / "lib" / "version.dart").write_text(
        "/// This app's version. Written by packaging/release.py from myvault/__init__.py\n"
        "/// so the PC and phone apps of one release always agree.\n"
        f"const appVersion = '{__version__}';\n", "utf-8")
    man = ROOT / "browser-extension" / "manifest.json"
    man.write_text(re.sub(r'"version": "[0-9.]+"', f'"version": "{__version__}"', man.read_text("utf-8")), "utf-8")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--notes", default="", help="short release notes shown in the update prompt")
    ap.add_argument("--publish", action="store_true", help="create the GitHub release and upload the files")
    ap.add_argument("--prerelease", action="store_true",
                    help="a test build: never offered as an update or as a version to go back to")
    args = ap.parse_args()
    v = __version__
    if not (KEYS / "key.properties").exists() or not (KEYS / "update_key.pem").exists():
        sys.exit(f"Release keys missing in {KEYS}. Run tools/make_release_keys.py once.")

    stamp_version()
    shutil.rmtree(OUT, ignore_errors=True)
    OUT.mkdir(parents=True)

    # 1. phone app (64-bit ARM: practically every phone from the last decade)
    subprocess.run([flutter(), "build", "apk", "--release", "--flavor", "direct", "--split-per-abi", "--target-platform", "android-arm64"],
                   cwd=APP, check=True)
    apk = OUT / f"MyVault-{v}.apk"
    shutil.copy(APP / "build" / "app" / "outputs" / "flutter-apk" / "app-arm64-v8a-direct-release.apk", apk)

    # 2. Windows installer carrying the APK + its signed manifest
    stage = ROOT / "build" / "packages" / v
    shutil.rmtree(stage.parent, ignore_errors=True)
    stage.mkdir(parents=True)
    shutil.copy(apk, stage / apk.name)
    raw, sig = sign({"app": "MyVault", "version": v, "files": {"android": entry(apk)}})
    (stage / "manifest-android.json").write_bytes(raw)
    (stage / "manifest-android.sig").write_text(sig)
    build_windows.main(packages=stage.parent)
    setup = OUT / f"MyVault-Setup-{v}.exe"
    shutil.copy(ROOT / "dist" / setup.name, setup)

    # 3. the manifest the apps check online
    raw, sig = sign({"app": "MyVault", "version": v, "published": time.strftime("%Y-%m-%d"),
                     "notes": args.notes, "files": {"windows": entry(setup), "android": entry(apk)}})
    (OUT / "latest.json").write_bytes(raw)
    (OUT / "latest.json.sig").write_text(sig)
    print(f"\nRelease {v} ready in {OUT}:")
    for f in sorted(OUT.iterdir()):
        print(f"  {f.name}  ({f.stat().st_size / 1e6:.1f} MB)")

    if args.publish:
        subprocess.run(["gh", "release", "create", f"v{v}", *[str(f) for f in sorted(OUT.iterdir())],
                        "--title", f"MyVault {v}", "--notes", args.notes or f"MyVault {v}",
                        *(["--prerelease"] if args.prerelease else [])], cwd=ROOT, check=True)
        print(f"Published v{v}. Apps that check online will offer it within a day.")
    else:
        print("Not published. To publish, run again with --publish (needs `gh auth login`).")


if __name__ == "__main__":
    main()
