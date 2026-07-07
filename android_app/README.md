# MyVault for Android

The Android version of MyVault. It opens the **exact same encrypted vault file**
as the Windows app (verified byte-for-byte — see `test_fixtures/`), so once LAN
sync is added your phone and PC will share one vault.

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

```
flutter pub get
flutter build apk --release
```

The APK appears at `build/app/outputs/flutter-apk/app-release.apk`.

To run it on a phone plugged in via USB (with USB debugging on):

```
flutter run --release
```

## What it does

Same core as the desktop app: a master-password-locked, encrypted vault with all
the registration fields, custom fields, search, a password generator, and
clipboard copy that auto-clears after 30 seconds. 100% offline.

## Encryption

Identical to the desktop app: **scrypt** (N=32768, r=8, p=1) derives the key from
your master password; **AES-256-GCM** encrypts the vault. Implemented with the
PointyCastle library so the file format matches the Python version exactly
(`lib/crypto.dart`). See the repo's top-level `VAULT_FORMAT.md`.
