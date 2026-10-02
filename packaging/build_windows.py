"""Build MyVault.exe and the installer in one go.

    .venv\\Scripts\\pip install -r requirements-dev.txt     (once)
    .venv\\Scripts\\python packaging\\build_windows.py

Output: dist\\MyVault\\MyVault.exe (the app) and dist\\MyVault-Setup-<version>.exe
(the installer to share). Needs Inno Setup 6 (winget install JRSoftware.InnoSetup).
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from myvault import __version__  # noqa: E402

VERSION_INFO = """VSVersionInfo(
  ffi=FixedFileInfo(filevers=({t}, 0), prodvers=({t}, 0), mask=0x3f, flags=0x0, OS=0x40004, fileType=0x1, subtype=0x0, date=(0, 0)),
  kids=[
    StringFileInfo([StringTable('040904B0', [
      StringStruct('CompanyName', 'Ahmed Mohammed'),
      StringStruct('FileDescription', 'MyVault'),
      StringStruct('FileVersion', '{v}'),
      StringStruct('InternalName', 'MyVault'),
      StringStruct('LegalCopyright', 'Ahmed Mohammed'),
      StringStruct('OriginalFilename', 'MyVault.exe'),
      StringStruct('ProductName', 'MyVault'),
      StringStruct('ProductVersion', '{v}')])]),
    VarFileInfo([VarStruct('Translation', [1033, 1200])])
  ]
)
"""


def iscc() -> str:
    env = os.environ.get
    for p in (Path(env("LOCALAPPDATA", "")) / "Programs" / "Inno Setup 6" / "ISCC.exe",
              Path(env("ProgramFiles(x86)", "")) / "Inno Setup 6" / "ISCC.exe",
              Path(env("ProgramFiles", "")) / "Inno Setup 6" / "ISCC.exe"):
        if p.exists():
            return str(p)
    found = shutil.which("ISCC")
    if not found:
        sys.exit("Inno Setup 6 not found. Install it with:  winget install JRSoftware.InnoSetup")
    return found


def main(packages: Path | None = None) -> None:
    """packages: a folder of <version>/ subfolders to ship inside the install (release.py)."""
    (ROOT / "build").mkdir(exist_ok=True)
    nums = ", ".join(__version__.split("."))
    (ROOT / "build" / "version_info.txt").write_text(VERSION_INFO.format(t=nums, v=__version__), "utf-8")
    shutil.rmtree(ROOT / "dist" / "MyVault", ignore_errors=True)
    subprocess.run([sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean",
                    "--distpath", str(ROOT / "dist"), "--workpath", str(ROOT / "build" / "pyinstaller"),
                    str(ROOT / "packaging" / "MyVault.spec")], check=True)
    # The extension sits beside MyVault.exe so it's easy to pick in "Load unpacked".
    shutil.copytree(ROOT / "browser-extension", ROOT / "dist" / "MyVault" / "browser-extension")
    if packages:   # the phone app (+ signed manifest), so this PC can hand it to a phone over sync
        shutil.copytree(packages, ROOT / "dist" / "MyVault" / "packages")
    subprocess.run([iscc(), f"/DAppVersion={__version__}", str(ROOT / "packaging" / "MyVault.iss")], check=True)
    print(f"\nDone: dist\\MyVault-Setup-{__version__}.exe")


if __name__ == "__main__":
    main()
