# MyVault for Android

The Android version of MyVault. It reads and writes the **same encrypted vault
format** as the Windows app (checked with test vectors in `test_fixtures/`), and
syncs with the PC by scanning the QR code the PC shows.

Built with Flutter (one codebase that also targets Linux and iOS later).

## Install the ready-made app (easiest)

Download **`MyVault.apk`** from the repository's **Releases** page
(github.com/AhmedMKAlzoubi/myvault/releases) on your phone, tap it, and install.
Android will ask you to allow installing from this source (“Install unknown
apps”) — that's normal for an app you build yourself instead of getting from the
Play Store.

> The APK is signed with a local **debug key** (fine for personal use / sideloading).
> A Play Store release would need a proper signing key; we can set that up later.

## Build it yourself

From this folder, with Flutter on your PATH:

```bash
flutter pub get
```

```bash
flutter build apk --release
```

The APK appears at `build/app/outputs/flutter-apk/app-release.apk`.

To run it on a phone plugged in via USB (with USB debugging on):

```bash
flutter run --release
```

## What it does

- Logins, API keys, SSH keys and secure notes, with extra fields of your own.
- Secret values stay covered by the tint until you tap the eye; they re-cover after 20 s.
- Password generator: uppercase, lowercase, numbers, symbols, avoid look-alikes, length 6 to 128.
- **Sync with PC:** tap the scan button, point at the code on the PC. Over your WiFi only.
- **Restore from paper:** scan the QR codes on a printed MyVault backup.
- Locks after 30 s in the background or 5 min idle. Screenshots and the
  recent-apps preview are blocked. Copied secrets are marked sensitive and clear
  after 30 s. Excluded from Google cloud backup.

Run the tests with `flutter test`. `python tests/interop_sync.py` (from the repo
root) runs a live sync between the Python PC code and this Dart code.

## Encryption

Identical to the desktop app: **scrypt** (N=32768, r=8, p=1) derives the key from
your master password; **AES-256-GCM** encrypts the vault. Implemented with the
PointyCastle library so the file format matches the Python version exactly
(`lib/crypto.dart`). See the repo's top-level `VAULT_FORMAT.md`.
