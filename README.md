# MyVault

Your own small, **offline** password manager. It keeps all the details you type
into websites and apps — username, email, password, region, age, gender, and
anything else — neatly organized and locked behind **one master password** you
memorize, so you never have to reuse passwords or dig through notes again.

- **100% local.** Nothing is ever sent to the internet or any company.
- **Encrypted.** The file on your disk is scrambled with strong encryption
  (scrypt + AES‑256‑GCM). Without your master password it is useless to anyone.
- **Lightweight.** Uses about 20–40 MB of memory and stays out of your way.

> ⚠️ **The one rule:** there is *no password reset*. If you forget your master
> password, your vault cannot be recovered — that is exactly what makes it safe.
> Write the master password down somewhere physically safe, and keep a backup of
> your vault file (see below).

---

## How to run it (Windows)

**The easy way:** double‑click **`run_myvault.bat`** in this folder.

**The manual way**, from a terminal opened in this folder:

```
python main.py
```

The first time it opens, you create your master password. After that, it just
asks for that password to unlock.

If you ever move this folder to a fresh computer, set it up once with:

```
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
```

---

## Where your data lives

Your accounts are saved in a single encrypted file:

```
Windows:  %LOCALAPPDATA%\MyVault\vault.dat
```

(Use **Menu → “Where is my vault file?”** inside the app to see the exact path.)

**Back this file up** — copy it to a USB stick or a private cloud folder now and
then. It is safe to store anywhere because it is encrypted, but if you lose it
*and* have no backup, your saved passwords are gone.

---

## What it does today

- Add, edit, search and delete entries with all the common sign‑up fields, plus
  unlimited **extra fields** for anything else (security questions, PINs, etc.).
- **Generate a password** that matches a specific site's rules (length, symbols,
  digits…), and remember those rules per entry so you can regenerate later.
- **Copy** username / email / password to the clipboard; the clipboard
  auto‑clears after 30 seconds.
- **Auto‑locks** itself after 5 minutes of inactivity.

## What's coming next (planned)

1. **Auto‑fill & capture** — a companion browser add‑on that fills website
   fields from MyVault and offers to save new logins you type. *(Bonus #1 & #2.)*
2. **Android app** — built to open this exact same encrypted vault file.
3. **LAN auto‑sync** — when your PC and phone are on the same home WiFi, their
   vaults merge automatically and privately. *(Bonus #5.)*
4. **Linux**, and **iOS** if a family member needs it.

The vault file format is documented in [`VAULT_FORMAT.md`](VAULT_FORMAT.md) so
every future app can read and write the same file.

---

## Is this really secure?

The building blocks are the same ones real password managers use:

- **scrypt** turns your master password into an encryption key and is
  deliberately slow + memory‑hungry, which makes mass password‑guessing very
  expensive.
- **AES‑256‑GCM** encrypts the data and detects any tampering.
- Your master password is **never stored** anywhere.

It is not audited software, so for now treat it as "much better than reusing
passwords and keeping them in notes" — which is exactly the problem it solves.
