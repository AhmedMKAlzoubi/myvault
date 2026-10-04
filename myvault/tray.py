"""MyVault's icon in the notification area (by the clock), so it can keep running
for the browser extension with no taskbar button. Windows only; uses the .NET
WinForms that pywebview already loads, so there's no extra dependency."""

from __future__ import annotations


class Tray:
    def __init__(self, icon_path: str, on_open, on_lock, on_quit):
        import threading

        import clr
        clr.AddReference("System.Windows.Forms")
        clr.AddReference("System.Drawing")
        from System.Drawing import Icon
        from System.Threading import ApartmentState, Thread, ThreadStart
        from System.Windows.Forms import (Application, ContextMenuStrip, MouseButtons, NotifyIcon,
                                          ToolStripSeparator)

        from .i18n import tr

        ready = threading.Event()

        def safe(fn):
            def handler(*_):
                try:
                    fn()
                except Exception:   # a failed click must never take the tray thread down
                    pass
            return handler

        def run():
            n = NotifyIcon()
            n.Icon = Icon(icon_path)
            n.Text = "MyVault"
            menu = ContextMenuStrip()
            for text, fn in (("Open MyVault", on_open), ("Lock now", on_lock), (None, None), ("Quit MyVault", on_quit)):
                if text is None:
                    menu.Items.Add(ToolStripSeparator())
                else:
                    menu.Items.Add(tr(text)).Click += safe(fn)
            n.ContextMenuStrip = menu
            opener = safe(on_open)
            n.MouseClick += lambda s, e: opener() if e.Button == MouseButtons.Left else None
            n.Visible = True
            self._n = n
            ready.set()
            Application.Run()       # this thread's message loop, for the icon and its menu

        self._n = None
        t = Thread(ThreadStart(run))
        t.SetApartmentState(ApartmentState.STA)
        t.IsBackground = True       # never keeps the process alive after Quit
        t.Start()
        ready.wait(5)

    def tell(self, title: str, text: str) -> None:
        if self._n is not None:
            from System.Windows.Forms import ToolTipIcon
            self._n.ShowBalloonTip(5000, title, text, ToolTipIcon.Info)

    def remove(self) -> None:
        """Take the icon away now (otherwise a dead icon lingers until hovered)."""
        if self._n is not None:
            self._n.Visible = False
            self._n.Dispose()
            self._n = None
