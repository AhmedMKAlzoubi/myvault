# PyInstaller recipe for MyVault.exe. Built by packaging/build_windows.py; run that, not this.
# One-folder build (not one-file): starts faster and trips antivirus heuristics less.
# The browser extension is copied next to MyVault.exe by build_windows.py, not bundled here.
from pathlib import Path

from PyInstaller.utils.hooks import collect_submodules

ROOT = Path(SPECPATH).parent

a = Analysis(
    [str(ROOT / "main.py")],
    pathex=[str(ROOT)],
    datas=[
        (str(ROOT / "myvault" / "ui"), "myvault/ui"),
        (str(ROOT / "assets" / "myvault.ico"), "assets"),
    ],
    # winrt: Windows' built-in text reader for documents (imported only when reading one)
    hiddenimports=["webview.platforms.winforms", "clr_loader", *collect_submodules("winrt")],
    excludes=["tkinter", "unittest", "pydoc", "PIL", "PyInstaller"],
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz, a.scripts, [],
    exclude_binaries=True,
    name="MyVault",
    icon=str(ROOT / "assets" / "myvault.ico"),
    version=str(ROOT / "build" / "version_info.txt"),
    console=False,
    upx=False,
)
coll = COLLECT(exe, a.binaries, a.datas, name="MyVault", upx=False)
