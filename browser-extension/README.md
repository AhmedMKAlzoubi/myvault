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
4. Click **Load unpacked** and select this `browser-extension` folder.
5. The MyVault key icon appears in your toolbar. Click it → **Settings / pairing
   token**.
6. In the desktop app: **Menu → Browser auto-fill…**, copy the **pairing token**,
   paste it into the extension's Settings, and click **Save & test**. You should
   see “Connected ✓”.

## Using it

- **Fill:** on a login page, click a username or password box — a small MyVault
  panel lists matching accounts; click one to fill. Or click the toolbar icon
  and press **Fill**.
- **Save:** after you type a new login and submit, a bar asks *“Save this login
  to MyVault?”* Click **Save** and it's stored (it updates an existing account
  instead of duplicating when it can).
- **Generate:** the toolbar popup has a quick password generator.

Auto-fill only works while the desktop app is **open and unlocked** — if it's
locked or closed, the extension simply does nothing (your vault stays sealed).

## Why this is safe

- The connector listens only on `127.0.0.1` (your machine), never on the network.
- Every request must carry the pairing token; without it the app refuses.
- The extension talks to the app only from its background worker, so web pages
  never see the token or your data.
- Domain matching is strict: `evil-netflix.com` will **not** be offered your
  `netflix.com` login.
