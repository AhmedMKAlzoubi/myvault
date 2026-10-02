# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

(Windows desktop app: Python + pywebview HTML UI. Android app: Flutter. Chromium browser extension. All three read the same encrypted vault format.)

## Users

First the author (Ahmed), on his own Windows PC and Android phone. If it proves practical, family and friends, then the public via GitHub and LinkedIn. Design for a non-technical person who has been reusing passwords and wants one safe place, while still serving a developer who stores SSH keys, API keys, client IDs and secrets.

## Product Purpose

An offline password and secrets manager. One master password unlocks an encrypted vault holding logins, API credentials, SSH keys and secure notes. Success: people stop reusing passwords, can always find a credential fast, and never have their data leave their own devices.

## Positioning

Nothing goes to a cloud or a company. Devices sync only by physically scanning a one-time QR code on the same WiFi. Backups are a printable PDF where everything, site names included, is encrypted; the app (or the phone camera) decodes it again.

## Operating Context

- Desktop: a resident window used many times a day. Search, copy, fill. Auto-locks after inactivity.
- Browser: the extension fills a login when you click a field and offers to save logins and registrations, suggesting a strong password on sign-up forms. It talks only to the desktop app on 127.0.0.1, with a pairing token.
- Phone: open, unlock, find, copy. Scan the PC's QR to sync. Scan paper backup QR codes to restore.
- Paper: an encrypted PDF printed and kept somewhere physical.

## Capabilities and Constraints

- Entry kinds: Login, API key / credentials, SSH key, Secure note. Plus free-form extra fields.
- Crypto: scrypt + AES-256-GCM. The vault format is shared across languages (VAULT_FORMAT.md) and must stay byte-compatible.
- Password generator: toggles for uppercase, lowercase, numbers and symbols, a length slider, and avoid look-alike characters.
- Browser auto-fill happens only on click (user decision). It never fills without a user action.
- No password reset exists, by design.
- No accounts, telemetry, analytics or network calls beyond LAN sync and loopback.

## Brand Commitments

Name: MyVault. Voice: plain, calm and honest. Explain security in everyday words, never in hype.

## Evidence on Hand

No users, testimonials or audits exist yet. Do not claim any.

## Product Principles

1. Local first: no data leaves the user's devices except through an action they deliberately take.
2. Safe by default: the secure choice is the easy one, and risky actions say what they risk.
3. Speed for the daily loop: search → copy or fill in seconds.
4. Understandable by family: no jargon is needed to use it, and details are there for developers who want them.

## Accessibility & Inclusion

Keyboard-complete on desktop, readable contrast in light and dark, and respect for reduced motion.
