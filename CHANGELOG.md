# Changelog

## 0.6.1 (6 October 2026)

- **Phone: scan documents like a scanner app.** "Scan document" finds the page's edges live, lets you drag the corners, straightens and cleans it, and takes several pages in one go (a card's front and back). It uses Google's on-device document scanner (from Google Play services); without it, the plain camera is used.
- **Fields that fit the document.** Each type shows its own fields: a passport has nationality, date of birth, place of birth and sex; a car registration has owner, plate, make and model and chassis number; a rental contract has landlord, tenant, address, rent and start and end dates; and so on. Anything filled in stays visible even if you change the type.
- **Reads more, and more carefully.** Details are read from all of a document's files together (front and back). Dates follow the order birth → issue → expiry, so a birth date is never taken for an expiry date. It also finds the address, phone, email, nationality, sex, place of birth, plate and chassis number, and an ID's number even when its label is in Arabic. An ID card is no longer mistaken for a residence permit.
- **Windows reminders** are now checked right after you save (not only every half hour), and Settings › Documents has **Send a test notification**. So does the phone (menu › Documents).
- The Windows app and the phone read documents by exactly the same rules, checked by shared tests.

## 0.6.0 (5 October 2026)

- **Personal documents** (Windows and Android): passports, ID cards, residence permits, visas, driving licences, car registrations, rental contracts, insurance and more.
  - Keep the details (type, name on the document, number, issued by, issue and expiry dates) and photos or PDFs of it, all encrypted. Each file has its own key, kept inside the vault.
  - **Reads the details for you, on your device:** from the machine-readable zone of passports and ID cards (checked with its check digits), or from dates labelled "expiry", "valid until", "تاريخ الانتهاء"… Windows uses its built-in text reader; the phone uses Google's on-device one, built into the app. Nothing is sent anywhere. You check the details before saving, and can always type them yourself.
  - **Reminders before a document expires:** choose any mix of 1 day, 3 days, 1 week, 2 weeks, 1 month, 2, 3 or 6 months, 1 year or your own number of days, plus the day itself. Notifications say only the type or a name you choose ("Passport expires in 1 month"), never numbers or names. They work while MyVault is locked or closed, and on the phone after a restart.
  - **Expiring soon** on the home screen, and each document's expiry in the list.
  - **Save a copy** of a file, after a warning that the copy isn't encrypted.
  - **Sync:** document details always sync. The files sync too unless you switch that off on a device (Settings › Documents on Windows, menu › Documents on the phone). Both devices need 0.6.0 for files to sync.
- Arabic for everything new.

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
