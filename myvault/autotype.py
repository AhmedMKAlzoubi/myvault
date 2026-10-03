"""Auto-type into other Windows programs (Discord, Steam, a game launcher...).

Windows gives password managers no way to read or fill other programs' login
boxes, so MyVault does what KeePass does: it types for you. The flow:
  1. You click the program's username box, then switch to MyVault.
  2. MyVault names the window it would type into (the one right behind it).
  3. You confirm; MyVault minimizes, which hands focus back to that box, checks
     the focused window really is that program, and types username, Tab,
     password as keystrokes. Nothing is typed anywhere else.

Programs running as administrator ignore keystrokes from normal apps (a
Windows rule), and some games read the keyboard directly; there it won't work.
"""

from __future__ import annotations

import ctypes
import os
import sys
import time
from ctypes import wintypes

VK_TAB, VK_RETURN = 0x09, 0x0D
KEYEVENTF_KEYUP, KEYEVENTF_UNICODE = 0x0002, 0x0004
GWL_EXSTYLE, WS_EX_TOOLWINDOW = -20, 0x00000080
DWMWA_CLOAKED = 14


class _KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", wintypes.WORD), ("wScan", wintypes.WORD), ("dwFlags", wintypes.DWORD),
                ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_size_t)]


class _INPUT(ctypes.Structure):
    class _U(ctypes.Union):
        _fields_ = [("ki", _KEYBDINPUT), ("pad", ctypes.c_byte * 32)]
    _anonymous_ = ("u",)
    _fields_ = [("type", wintypes.DWORD), ("u", _U)]


def available() -> bool:
    return sys.platform == "win32"


def _u32():
    return ctypes.WinDLL("user32", use_last_error=True)


def _title(hwnd) -> str:
    buf = ctypes.create_unicode_buffer(256)
    _u32().GetWindowTextW(hwnd, buf, 256)
    return buf.value


def _is_candidate(hwnd) -> bool:
    u = _u32()
    if not u.IsWindowVisible(hwnd) or u.IsIconic(hwnd) or not _title(hwnd):
        return False
    pid = wintypes.DWORD()
    u.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    if pid.value == os.getpid():
        return False                                   # MyVault itself
    if u.GetWindowLongW(hwnd, GWL_EXSTYLE) & WS_EX_TOOLWINDOW:
        return False                                   # tooltips, floating toolbars
    cloaked = wintypes.DWORD()
    try:                                               # hidden store apps / other desktops
        ctypes.windll.dwmapi.DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, ctypes.byref(cloaked), 4)
    except OSError:
        pass
    return not cloaked.value and _title(hwnd) != "Program Manager"


def target_window() -> tuple[int, str] | None:
    """The program window right behind MyVault: the one you were just in."""
    found: list[int] = []
    proc = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)

    def visit(hwnd, _):
        if _is_candidate(hwnd):
            found.append(hwnd)
            return False                               # top-down z-order: first one wins
        return True
    _u32().EnumWindows(proc(visit), 0)
    return (found[0], _title(found[0])) if found else None


def _key(vk=0, scan=0, flags=0) -> _INPUT:
    i = _INPUT(type=1)                                 # INPUT_KEYBOARD
    i.ki = _KEYBDINPUT(wVk=vk, wScan=scan, dwFlags=flags, time=0, dwExtraInfo=0)
    return i


def _send(inputs: list[_INPUT]) -> None:
    arr = (_INPUT * len(inputs))(*inputs)
    _u32().SendInput(len(inputs), arr, ctypes.sizeof(_INPUT))


def type_text(text: str) -> None:
    """Type any text, including symbols and non-Latin letters, as Unicode keys."""
    units = text.encode("utf-16-le")
    for k in range(0, len(units), 2):
        code = int.from_bytes(units[k:k + 2], "little")
        _send([_key(scan=code, flags=KEYEVENTF_UNICODE),
               _key(scan=code, flags=KEYEVENTF_UNICODE | KEYEVENTF_KEYUP)])
        time.sleep(0.004)                              # some apps drop very fast input


def press(vk: int) -> None:
    _send([_key(vk=vk), _key(vk=vk, flags=KEYEVENTF_KEYUP)])
    time.sleep(0.03)


def type_into(hwnd: int, parts: list[str], minimize_self) -> str:
    """Hand focus back to `hwnd`, check it really has it, then type `parts`
    separated by Tab. Returns "" on success or the reason it refused."""
    minimize_self()
    u = _u32()
    for _ in range(20):                                # Windows needs a moment to switch
        time.sleep(0.05)
        if u.GetForegroundWindow() == hwnd:
            break
    else:
        u.SetForegroundWindow(hwnd)
        time.sleep(0.15)
    if u.GetForegroundWindow() != hwnd:
        return "The other program didn't come to the front, so nothing was typed."
    time.sleep(0.12)
    for n, part in enumerate(parts):
        if n:
            press(VK_TAB)
        type_text(part)
    return ""
