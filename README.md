# MyVault

An offline password manager for Windows and Android. One master password opens
an encrypted vault holding your logins, API keys, client IDs and secrets, SSH
keys, and private notes. Nothing goes to a cloud or a company.

- **Encrypted on disk.** scrypt turns your master password into a key, and
  AES-256-GCM seals the vault with it. The password itself is never stored.
- **Sync by QR code.** Your PC shows a one-time code, your phone scans it, and the
  two swap changes over your own WiFi. No account and no server.
- **Paper backup.** Print the whole vault as a PDF where nothing is readable,
  not even the site names. The app reads the PDF back, and the phone can restore
  from the printed QR codes.
- **Browser fill.** A small extension for Chrome, Edge, Brave and Comet fills
  logins when you click a login box. On sign-up forms it suggests a strong
  password and offers to save the new account.

> **There is no password reset.** If you forget the master password, nobody can
> open the vault, not even you. That's what keeps it safe. Write the master
> password down and keep it somewhere physical.

---

## Windows app

**Install it:** run `MyVault-Setup-<version>.exe` from the **Releases** page. It
installs like any other app, with a desktop shortcut, a Start menu entry and an
uninstaller under *Settings → Apps*. No admin rights needed: it goes into
`%LOCALAPPDATA%\Programs\MyVault`, or Program Files if you choose "install for
all users". Because the installer isn't code-signed yet, Windows SmartScreen may
say it "protected your PC": choose **More info → Run anyway**.

Your vault is stored separately in `%LOCALAPPDATA%\MyVault\vault.dat`, so
updating or uninstalling the app never touches it. **Settings → Folders** opens
the vault folder, the program folder and the browser-extension folder in
Explorer.

**Run from source** (for development): double-click `run_myvault.bat`. Set it up
once on a new machine:

```bash
python -m venv .venv
```

```bash
.venv\Scripts\pip install -r requirements.txt
```

**Build the installer yourself:**

```bash
.venv\Scripts\pip install -r requirements-dev.txt
```

```bash
.venv\Scripts\python packaging\build_windows.py
```

That writes `dist\MyVault\MyVault.exe` and `dist\MyVault-Setup-<version>.exe`. It
needs [Inno Setup 6](https://jrsoftware.org/isinfo.php)
(`winget install JRSoftware.InnoSetup`). The icons come from
`tools\make_icons.py`.

What's in it:

| | |
|---|---|
| Entry types | Login, API key (service, endpoint, client ID, client secret, API key, token), SSH key (host, port, user, private key, passphrase, public key, fingerprint), secure note. Plus extra fields of your own on any entry. |
| Reveal | Secret values stay under a printed "security tint" until you choose to show them, and cover themselves again after 20 seconds. |
| Copy | Copied secrets skip Windows clipboard history (Win+V) and cloud clipboard, and clear after 30 seconds. |
| Generator | Uppercase, lowercase, numbers and symbols toggles, avoid look-alike characters, length slider from 6 to 128, strength meter. |
| Auto-lock | After 5 minutes without use, and when you close the window. |
| Keyboard | `Ctrl F` search, `Ctrl N` new login, `Ctrl S` save, `Ctrl L` lock, arrow keys in the list. |

The vault file is useless without your master password, so you can copy it to a
USB stick as a backup.

## Android app

A Flutter app in [`android_app/`](android_app/) that opens the same vault format.
Download the APK from the **Releases** page, or build it yourself (see
[`android_app/README.md`](android_app/README.md)).

The phone app has the same entry types, reveal and generator. It locks after 30
seconds in the background or 5 minutes idle, blocks screenshots and the
recent-apps preview, marks copied secrets as sensitive, and is excluded from
Google cloud backup.

## Sync PC ↔ phone

1. PC: **Sync with phone → Show sync code.**
2. Phone: tap the **scan** button and point the camera at the code.
3. Both end up with the newest version of every entry. Deletions carry across.

The code holds a one-time random 256-bit key and the PC's address. The key only
travels through the camera, so nobody else on the WiFi can read or tamper with
the exchange. The PC listens only while the code is on screen, for at most two
minutes, and stops after one sync. The first time, Windows may ask whether
MyVault may use the network: allow it on **private** networks.

## Updates

- **When you sync,** each device tells the other its version. If the PC is newer
  it hands the phone its update over the encrypted channel, and the phone asks
  "Install now?". It works the other way too: a phone that updated online
  passes the PC its installer. No internet is needed.
- **Online (optional, asked once):** new versions come out now and then. To spot
  them, the apps look (at most once a day) at a small,
  signed version file from this repo's Releases page. Nothing from the vault is
  ever sent. Updates are only installed if they carry the maintainer's
  signature, and Android also checks that the APK is signed with MyVault's
  release key.

Making a release (maintainer):

```bash
.venv\Scripts\python packaging\release.py --notes "What changed" --publish
```

That builds the signed phone APK, the Windows installer with the APK inside,
and the signed `latest.json`, then uploads them to a GitHub release. The keys
live in `%USERPROFILE%\.myvault-release` (created once by
`tools\make_release_keys.py`) and are never committed.

## Paper backup

**Paper backup → Save PDF…** asks for a backup password (it can be your master
password, or a different one) and writes a PDF. Each entry becomes one encrypted
block, printed as text and as a QR code. Print it and keep it somewhere safe,
away from the backup password.

To restore, use **Paper backup → Choose PDF…** on the PC, or **Restore from
paper** on the phone and scan each code. Restored entries merge into the vault,
and the newer copy of each one wins.

## Browser extension

See [`browser-extension/README.md`](browser-extension/README.md). In short: load
the folder as an unpacked extension, then paste the pairing token from
**Browser auto-fill** in the app. The extension talks only to the app on
`127.0.0.1`, only while it's unlocked, and never fills anything without a click.

## How it's built

```
myvault/            Windows app (Python)
  crypto.py         scrypt + AES-256-GCM vault file
  vault.py          entries, kinds, load/save (atomic writes)
  sync.py           QR pairing session + encrypted exchange
  paper.py          encrypted PDF writer/reader (no PDF library needed)
  clipboard.py      private clipboard (no history, auto-clear)
  server.py         127.0.0.1 connector for the browser extension
  app.py            pywebview window + the API the UI calls
  ui/               the interface: index.html, app.css, app.js
assets/             the app icon (myvault.ico, icon-1024.png)
packaging/          PyInstaller spec, Inno Setup script, build_windows.py
tools/make_icons.py draws every icon size (Windows, Android, extension)
android_app/        Android app (Flutter)
browser-extension/  Chromium extension (Manifest V3)
tests/              python tests/test_core.py, python tests/interop_sync.py
```

The file, sync and paper formats are written up in
[`VAULT_FORMAT.md`](VAULT_FORMAT.md), so any implementation can read the same
vault. Tests cover the crypto, the merge rules, QR sync (including a live
Python ↔ Dart session), and the paper round-trip (including decoding QR codes
scanned off a rendered page).

```bash
.venv\Scripts\python tests\test_core.py
```

## Limits worth knowing

- The desktop app is Windows-only for now (the clipboard protection uses Windows
  APIs). The UI and core are cross-platform Python, so macOS and Linux are mostly
  a matter of a clipboard backend.
- Sync needs both devices on the same network. Some guest or office networks
  block device-to-device traffic.
- Python can't wipe strings from memory, so a secret you've opened stays in RAM
  until the app locks. That's the same limit most password managers live with.
- No security audit has been done. Read the code, and report anything you find.
