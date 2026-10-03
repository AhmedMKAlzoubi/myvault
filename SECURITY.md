# Security Policy

MyVault holds people's passwords, so security reports are taken seriously and are welcome.

## Supported versions

| Version | Security fixes |
|---|---|
| Latest release | Yes |
| Older releases | No. Please update. |

## Reporting a vulnerability

**Please don't open a public issue for a security problem.** Report it privately instead:

1. **Preferred:** use GitHub's private reporting. Go to the repository's **Security** tab and choose **Report a vulnerability** ([direct link](https://github.com/AhmedMKAlzoubi/myvault/security/advisories/new)).
2. **Or email** ahmedmohammedkhear@gmail.com with the subject "MyVault security".

Please include:

- the affected app (Windows, Android or the browser extension) and its version
- what an attacker can do, and the steps to reproduce it
- any proof-of-concept code

Please test only against your own devices and your own vaults. Never use someone else's data.

## What to expect

MyVault is a one-person project, so these timings are good-faith targets, not guarantees:

- **First reply:** within 7 days.
- **Assessment:** within 14 days, with an initial assessment and severity.
- **Fix:** serious issues get a signed release as soon as practical, and you'll be told when it's out.
- **Credit:** you'll be credited in the release notes and advisory unless you'd rather not be.

## In scope

- Anything that lets someone read vault contents without the master password.
- Weaknesses in the encryption, the sync protocol, the paper backup or update signature checks.
- The browser extension filling the wrong site, or leaking data to a page.
- The local connector (`127.0.0.1`) being reachable or abusable by websites or other users.
- The Android autofill service filling into the wrong app.

## Out of scope

- Attacks that need your unlocked device together with your master password, or malware already running as you.
- Weak master passwords chosen by the user.
- Reports from automated scanners with no demonstrated impact.

## How MyVault is built to be safe

The design notes are in [README.md](README.md#how-its-built) and [VAULT_FORMAT.md](VAULT_FORMAT.md). Code scanning (CodeQL), Dependabot and secret scanning with push protection are enabled on this repository.
