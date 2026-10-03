# MyVault Privacy Policy

**Last updated:** 3 October 2026 · Applies to MyVault 0.5.2 and later (Windows app, Android app, browser extension)

MyVault is a password manager that runs only on your own devices. It is made by Ahmed Mohammed as a personal open project. There is no MyVault company, server, account or cloud.

## The short version

- **We collect nothing.** MyVault has no accounts, analytics, advertising, crash reporting or tracking of any kind.
- **Your vault never leaves your devices** unless you move it yourself: by syncing your PC and phone over your own WiFi, or by printing a paper backup.
- **Everything in the vault is encrypted** with your master password (scrypt + AES-256-GCM). Nobody else can read it, us included. If you forget the master password, it can't be recovered.

## What MyVault stores, and where

| What | Where | Protected by |
|---|---|---|
| Your vault (logins, notes, API keys, SSH keys, secrets) | Windows: `%LOCALAPPDATA%\MyVault\`; Android: the app's private storage | Your master password (scrypt + AES-256-GCM) |
| Settings (auto-lock time, update-check choice, start with Windows) | Same folder, a small file; on Android the app's private storage | Not secret; contains no vault data |
| Logins Android captured for you ("Save to MyVault?") before you unlocked | The app's private storage on the phone, until you next unlock | AES-256-GCM with a key held by the Android Keystore |
| Paper backup PDF | Wherever you save or print it | Your master password (scrypt, stronger settings) |

## When MyVault uses the network

MyVault makes only these connections:

1. **PC ↔ phone sync.** The phone connects straight to your PC over your local network after you scan the QR code. Each sync uses a new one-time key from that QR code, and everything sent is encrypted with it. Nothing goes through the internet or through us.
2. **Browser extension ↔ Windows app.** The extension talks only to the MyVault app on the same computer (`127.0.0.1`). It never sends anything to a website or to us.
3. **Update checks (only if you turn them on).** MyVault asks once whether it may check for updates. If you say yes, it downloads a small public file (`latest.json`) from GitHub Releases now and then. Like any download, GitHub sees your IP address; see [GitHub's privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement). No vault data or identifier is sent. Updates are only installed when you agree, and only if they carry MyVault's digital signature.

## Permissions (Android)

- **Camera:** used only to scan the sync QR code. No pictures are saved.
- **Install other apps:** used only when you choose to install a MyVault update. Before installing, MyVault checks the file is signed by the same key as the app you already have.
- **Autofill service (optional, you switch it on):** lets MyVault offer to fill and save logins in other apps. MyVault reads a login screen only when Android asks it to fill or save, keeps only the app name or website and the username and password, and fills only after you unlock and pick an account.

## Clipboard and screen

When you copy a secret, MyVault marks it as sensitive so Windows clipboard history and Android's preview don't keep it, and clears it after 30 seconds. The Android app blocks screenshots and screen recording.

## Children

MyVault isn't directed at children and collects no personal data from anyone, so no child's data is collected.

## Your choices and deleting your data

All your data is on your devices, so you are in full control:

- **Delete everything:** uninstall the app, or delete the `MyVault` folder (the Windows app's Settings has an "Open folder" button). On Android, uninstall the app or clear its storage.
- **Export or move it:** sync to another device, or make a paper backup.
- There is nothing to request from us, because we hold none of your data.

## Changes to this policy

If this policy changes, the new version will be published here with a new "Last updated" date and listed in [CHANGELOG.md](CHANGELOG.md).

## Contact

- Questions: [GitHub Issues](https://github.com/AhmedMKAlzoubi/myvault/issues) or email **ahmedmohammedkhear@gmail.com**
- Security problems: please follow [SECURITY.md](SECURITY.md) and don't open a public issue
