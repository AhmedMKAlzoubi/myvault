"""Copy secrets to the Windows clipboard WITHOUT them landing in clipboard
history (Win+V) or Cloud Clipboard, and clear them again after a while.

Windows keeps every copy in its history unless the copy carries these marker
formats, which is what real password managers set:
  ExcludeClipboardContentFromMonitorProcessing, CanIncludeInClipboardHistory=0,
  CanUploadToCloudClipboard=0.
"""

from __future__ import annotations

import ctypes
import sys
import threading
import time

_lock = threading.Lock()
_last = {"text": None}

if sys.platform == "win32":
    from ctypes import wintypes

    _u32 = ctypes.WinDLL("user32", use_last_error=True)
    _k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    _u32.OpenClipboard.argtypes = [wintypes.HWND]
    _u32.SetClipboardData.argtypes = [wintypes.UINT, wintypes.HANDLE]
    _u32.SetClipboardData.restype = wintypes.HANDLE
    _u32.GetClipboardData.argtypes = [wintypes.UINT]
    _u32.GetClipboardData.restype = wintypes.HANDLE
    _u32.RegisterClipboardFormatW.argtypes = [wintypes.LPCWSTR]
    _u32.RegisterClipboardFormatW.restype = wintypes.UINT
    _k32.GlobalAlloc.argtypes = [wintypes.UINT, ctypes.c_size_t]
    _k32.GlobalAlloc.restype = wintypes.HGLOBAL
    _k32.GlobalLock.argtypes = [wintypes.HGLOBAL]
    _k32.GlobalLock.restype = ctypes.c_void_p
    _k32.GlobalUnlock.argtypes = [wintypes.HGLOBAL]
    CF_UNICODETEXT = 13
    GMEM_MOVEABLE = 0x0002

    def _open() -> bool:
        for _ in range(10):                 # another app may hold it briefly
            if _u32.OpenClipboard(None):
                return True
            time.sleep(0.03)
        return False

    def _put(fmt: int, data: bytes) -> None:
        h = _k32.GlobalAlloc(GMEM_MOVEABLE, len(data))
        ptr = _k32.GlobalLock(h)
        ctypes.memmove(ptr, data, len(data))
        _k32.GlobalUnlock(h)
        _u32.SetClipboardData(fmt, h)

    def _set(text: str, private: bool) -> bool:
        if not _open():
            return False
        try:
            _u32.EmptyClipboard()
            if text:
                _put(CF_UNICODETEXT, (text + "\0").encode("utf-16-le"))
            if private:
                zero = (0).to_bytes(4, "little")
                _put(_u32.RegisterClipboardFormatW("ExcludeClipboardContentFromMonitorProcessing"), zero)
                _put(_u32.RegisterClipboardFormatW("CanIncludeInClipboardHistory"), zero)
                _put(_u32.RegisterClipboardFormatW("CanUploadToCloudClipboard"), zero)
            return True
        finally:
            _u32.CloseClipboard()

    def _get() -> str | None:
        if not _open():
            return None
        try:
            h = _u32.GetClipboardData(CF_UNICODETEXT)
            if not h:
                return None
            ptr = _k32.GlobalLock(h)
            try:
                return ctypes.wstring_at(ptr)
            finally:
                _k32.GlobalUnlock(h)
        finally:
            _u32.CloseClipboard()
else:  # ponytail: other OSes not supported yet; the desktop app targets Windows
    def _set(text: str, private: bool) -> bool:
        return False

    def _get() -> str | None:
        return None


def copy_secret(text: str, clear_after: float = 30.0) -> bool:
    """Copy privately; wipe after `clear_after` seconds if still ours."""
    with _lock:
        ok = _set(text, private=True)
        _last["text"] = text
    if ok and clear_after:
        def wipe():
            with _lock:
                if _last["text"] == text and _get() == text:
                    _set("", private=False)
                    _last["text"] = None
        t = threading.Timer(clear_after, wipe)
        t.daemon = True
        t.start()
    return ok


def wipe_now() -> None:
    """Called on lock/quit: clear the clipboard if it still holds our secret."""
    with _lock:
        if _last["text"] is not None and _get() == _last["text"]:
            _set("", private=False)
        _last["text"] = None
