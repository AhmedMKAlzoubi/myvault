# MyVault Privacy Policy

**Last updated:** 6 October 2026 · Applies to MyVault 0.7.0 and later (Windows app, Android app, browser extension)

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
| Personal document files (photos and PDFs of passports, IDs, contracts…) | Next to the vault, in a `files` folder, one encrypted file each | AES-256-GCM, each with its own random key kept inside the encrypted vault |
| Document reminder schedule | Next to the vault (`reminders.json`); on Android the app's private storage | Not encrypted, so reminders work while MyVault is locked. It holds only, for each reminder, the date, the expiry date and a short text such as "Passport expires in 1 month" (the type, or the name you chose for reminders). Never numbers, holders' names or anything else from the document |
| Copies of documents you choose to save | Wherever you save them | **Not encrypted.** MyVault warns you before saving one |
| Daily backups (Windows) | `%LOCALAPPDATA%\MyVault\backups\`, one copy a day for 14 days | Your master password: they are copies of the encrypted vault file |
| Fingerprint unlock (Android, if you turn it on) | The app's private storage | Your master password, encrypted by a key in the Android Keystore that only opens after your fingerprint or face. Fingerprints and face data stay with Android; MyVault never sees them |
| Paper backup PDF | Wherever you save or print it | Your master password (scrypt, stronger settings). It includes document details, not the photos or PDFs |

## When MyVault uses the network

MyVault makes only these connections:

1. **PC ↔ phone sync.** The phone connects straight to your PC over your local network after you scan the QR code. Each sync uses a new one-time key from that QR code, and everything sent is encrypted with it. Nothing goes through the internet or through us.
2. **Browser extension ↔ Windows app.** The extension talks only to the MyVault app on the same computer (`127.0.0.1`). It never sends anything to a website or to us.
3. **Update checks (only if you turn them on).** MyVault asks once whether it may check for updates. If you say yes, it downloads a small public file (`latest.json`) from GitHub Releases now and then. Like any download, GitHub sees your IP address; see [GitHub's privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement). No vault data or identifier is sent. Updates are only installed when you agree, and only if they carry MyVault's digital signature. Store builds (Google Play, Microsoft Store) skip this: the store installs updates.
4. **Leaked-password check (only when you press "Check for leaked passwords").** MyVault asks [Have I Been Pwned](https://haveibeenpwned.com/Passwords) whether your passwords appear in known data leaks, using its "range" method: for each password it sends only the **first 5 characters of its SHA-1 hash** (a scrambled fingerprint of the password), gets back a list of leaked hashes that start the same way, and checks for a match on your device. Your passwords, their full hashes, usernames and sites are never sent. Like any web request, the service sees your IP address; see [its privacy policy](https://haveibeenpwned.com/Privacy).

## Permissions (Android)

- **Camera:** used to scan the sync QR code and, when you choose "Take a photo", to photograph a document. The photo goes straight into MyVault's encrypted storage; the camera app's temporary copy is deleted at once.
- **Notifications:** used only for document reminders you set. Each says only the document type (or the name you chose) and the time left, e.g. "Passport expires in 1 month". On a locked screen Android hides even that.
- **Run at startup:** so document reminders keep working after the phone restarts. Nothing else runs.
- **NFC (optional):** used only while you choose "Read the chip" and hold a passport or ID card to the phone. The chip opens only with the document's number, birth date and expiry (or its card access number), and the details are read into the entry on your phone. Nothing is sent anywhere.
- **Fingerprint or face (optional):** used only if you turn on fingerprint unlock. Android checks the fingerprint and tells MyVault only whether it matched.
- **Install other apps:** used only when you choose to install a MyVault update (not in the Google Play build). Before installing, MyVault checks the file is signed by the same key as the app you already have.
- **Autofill service (optional, you switch it on):** lets MyVault offer to fill and save logins in other apps. MyVault reads a login screen only when Android asks it to fill or save, keeps only the app name or website and the username and password, and fills only after you unlock and pick an account.

## Reading documents

When you ask MyVault to read a document's details, the text is read **on your device**: on Windows by its built-in text reader, on Android by Google's on-device text recognizer, which is built into the MyVault app. No image or text is sent anywhere. The details are only suggestions; you check them before saving.

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
