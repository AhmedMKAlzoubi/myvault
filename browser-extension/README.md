# MyVault browser auto-fill

A companion extension for **Comet, Chrome, Edge, Brave** (any Chromium browser).
It fills website logins from your MyVault app and offers to save new ones you type.

Nothing here has your passwords baked in. It simply asks the MyVault desktop app
— running privately on your own computer at `127.0.0.1` — and only when you've
paired it with the secret token and the app is open and unlocked.

## Install (one time)

1. Make sure the **MyVault desktop app is running and unlocked**.
2. In your browser, open the extensions page:
   - Comet / Chrome / Brave: menu → **Extensions → Manage Extensions**
   - Edge: menu → **Extensions**
3. Turn on **Developer mode** (usually a toggle at the top-right).
4. Click **Load unpacked** and select this `browser-extension` folder (the one with
   `manifest.json` inside). In the installed app it's next to `MyVault.exe`; the
   app's **Browser auto-fill** page has a **Copy** and an **Open folder** button for it.
5. The MyVault key icon appears in your toolbar. Click it → **Settings / pairing
   token**.
6. In the desktop app, open **Browser auto-fill** (bottom left), copy the
   **pairing token**, paste it into the extension's settings, and click
   **Save & test**. You should see “Connected”.

## Using it

- **Fill:** on a login page, click the username or password box. A small MyVault
  card lists the accounts saved for that site; click one to fill it. Nothing is
  ever filled without that click. You can also use the toolbar popup's **Fill**.
- **Sign up:** on a registration form, click the password box. MyVault suggests
  a strong random password; **Use this password** fills it (and the confirm box).
- **Save:** after you log in or register, a bar asks whether to save to MyVault.
  For sign-ups it also keeps details you typed, like name, country and date of
  birth, as extra fields. It never keeps card numbers or one-time codes.
- **Didn't save?** If a page reloads before you save, the popup shows the
  password it suggested for that site for the next 30 minutes (kept in memory
  only, gone when the browser closes).
- **Generate:** the popup has a generator with the same toggles as the app.

Auto-fill only works while the desktop app is **open and unlocked**. When it's
locked or closed, the extension does nothing.

## Why this is safe

- The connector listens only on `127.0.0.1` (your machine), never on the network.
- Every request must carry the pairing token; without it the app refuses.
- The extension talks to the app only from its background worker, so web pages
  never see the token. Its on-page cards live in a closed shadow root that the
  page's scripts can't reach into.
- No password is suggested unless the app is reachable, so a suggestion can't
  get lost with nothing saved.
- Domain matching is strict: `evil-netflix.com` will **not** be offered your
  `netflix.com` login.
