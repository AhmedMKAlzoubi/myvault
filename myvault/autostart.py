"""Start MyVault when you sign in to Windows (Settings > Apps > Startup lists it).

Uses the standard per-user Run key. Windows' own Startup-apps switch doesn't
delete that value; it flips a flag under StartupApproved, so both are read and
turning it on here clears a "disabled" flag set there.
"""

from __future__ import annotations

import sys

RUN = r"Software\Microsoft\Windows\CurrentVersion\Run"
APPROVED = r"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
NAME = "MyVault"


def available() -> bool:
    """Only the installed MyVault.exe can register itself (not a dev checkout)."""
    return sys.platform == "win32" and bool(getattr(sys, "frozen", False))


def command() -> str:
    return f'"{sys.executable}" --minimized'


def enabled(name: str = NAME) -> bool:
    if sys.platform != "win32":
        return False
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN) as k:
            winreg.QueryValueEx(k, name)
    except OSError:
        return False
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, APPROVED) as k:
            flag = winreg.QueryValueEx(k, name)[0]
        return not flag or flag[0] % 2 == 0      # 0x02/0x06 on, 0x03 off
    except OSError:
        return True                              # no flag yet = on


def set_enabled(on: bool, name: str = NAME, cmd: str | None = None) -> None:
    import winreg
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, RUN) as k:
        if on:
            winreg.SetValueEx(k, name, 0, winreg.REG_SZ, cmd or command())
        else:
            try:
                winreg.DeleteValue(k, name)
            except FileNotFoundError:
                pass
    try:   # forget any "disabled" choice made in Windows' Startup apps page
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, APPROVED, 0, winreg.KEY_SET_VALUE) as k:
            winreg.DeleteValue(k, name)
    except OSError:
        pass
