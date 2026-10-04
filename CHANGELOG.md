# Changelog

## 0.5.4 (3 October 2026)

- **Arabic (العربية).** The Windows app, the phone app, the browser extension and the installer now come in English and Arabic, right to left in Arabic. They follow your system language, or you can choose in Settings (Windows) or the menu (phone). Your entries are never translated, and passwords always read left to right.
- **A saved password can't be replaced by accident** (Windows and Android). When you edit a login, its password is read-only, and Generate (and Paste on the phone) only appear while the box is empty. **Change password** first warns you, then lets you type a new one or generate one, and **Keep the old password** puts the saved one back until you save.
- Windows: the Sync page no longer shows a stray "undefined" above the button.
- **Go back to the previous version** (Windows, Settings › Updates): reinstalls the stable release before yours, after checking its signature and copying your vault. The phone's Updates page explains how to go back on Android.
- Windows: installing an update now really closes MyVault first. Since 0.5.3, closing only hid it in the tray, which could leave its files in use.
- Windows: the installer now removes phone APKs bundled by earlier versions, so the MyVault program's `packages` folder holds only the APK that matches the PC app.
- README: screenshots.

## 0.5.3 (3 October 2026)

- **Windows: runs in the background.** The X button now hides MyVault to the notification area by the clock instead of quitting, so browser fill keeps working without a taskbar button. Click the icon to open it; right-click it to lock or quit. Start with Windows now starts it there.

## 0.5.2 (3 October 2026)

- **Android: autofill in other apps.** Turn MyVault on as Android's autofill service (menu › Autofill in other apps). It fills logins in apps and Chrome after you unlock, and saves new sign-ins you allow ("Save to MyVault?").
- **Windows: "Type into app".** Types a login's username and password into the program behind MyVault, for desktop apps that browsers can't reach.
- **Browser extension:** when you accept a suggested password while signing up, the account is saved automatically.
- **Auto-lock timer** in Settings, on Windows and Android.
- **Android:** Paste buttons next to secret fields.
- Secure notes no longer show their first line in the list, and their text isn't searchable.
- Added a privacy policy, terms of use, security policy and a troubleshooting guide.
- MyVault is now licensed under GPL-3.0.

## 0.5.1 (3 October 2026)

- Security fixes from an audit. The biggest: the phone now checks that updates are signed by MyVault before offering them, and that the APK is from the same developer.
- The browser connector replies only to the exact MyVault extension.

## 0.5.0 (3 October 2026)

- New interface, sync by QR code, storage for API keys, SSH keys and other secrets, encrypted paper backup, Windows installer, signed updates.

## 0.1 to 0.4 (July 2026)

- First versions: the encrypted vault, the Android app, browser fill and capture, and WiFi sync.
