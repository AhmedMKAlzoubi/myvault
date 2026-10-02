# Cross-compatibility test vectors

These prove the Android (Dart) app and the Windows (Python) app read/write the
**same** encrypted vault format (see the repo's top-level `VAULT_FORMAT.md`).

- `fixture_vault.dat` — a real MyVault file **written by the Python app**. The
  master password is **`test-master-123`** (this is a throwaway test vault with
  fake data — safe to publish).
- `fixture_plaintext.json` — the exact decrypted contents, for reference.

The Dart unit tests and a one-off interop check confirm that Dart decrypts
`fixture_vault.dat` to `fixture_plaintext.json`, and that a vault written by Dart
decrypts correctly in Python. If either app ever changes the format in an
incompatible way, opening this fixture will fail — a deliberate early warning.
- `paper_block.txt` — one paper-backup block (Base32, exactly what a QR code on
  the printed PDF holds) **written by the Python app**. Backup password
  **`paper-fixture-pw`**. It holds one fake API-key entry (`client_secret` is
  `s3cr3t!`). The Dart tests decode it, so a change in either app's paper format
  shows up straight away.
