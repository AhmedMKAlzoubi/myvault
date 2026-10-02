# MyVault file format (envelope v1, content v2)

This spec exists so the future **Android, Linux and iOS** apps can open, edit and
sync the *same* encrypted vault file the Windows app writes. Any implementation
that follows this can interoperate.

## On-disk envelope

The vault file (`vault.dat`) is UTF‑8 JSON:

```json
{
  "magic": "MYVAULT",
  "version": 1,
  "kdf": {
    "algo": "scrypt",
    "n": 32768,
    "r": 8,
    "p": 1,
    "dklen": 32,
    "salt": "<base64, 16 bytes>"
  },
  "cipher": {
    "algo": "AES-256-GCM",
    "nonce": "<base64, 12 bytes>",
    "data": "<base64: ciphertext WITH appended 16-byte GCM tag>"
  }
}
```

### Deriving the key

```
key (32 bytes) = scrypt(password_utf8, salt, N=n, r=r, p=p, dkLen=dklen)
```

### Decrypting

```
plaintext = AES_256_GCM_decrypt(key, nonce, data, aad = none)
```

`data` is the concatenation of ciphertext + 16‑byte authentication tag, exactly
as produced by most AES‑GCM libraries (Python `cryptography` AESGCM, Dart
`cryptography` / PointyCastle, WebCrypto). If the tag check fails, the password
is wrong or the file was altered — reject it.

On every save, generate a **fresh random `salt` and `nonce`**. Never reuse a
nonce with the same key.

## Decrypted payload

The plaintext is UTF‑8 JSON:

```json
{
  "content_version": 2,
  "device_id": "<uuid of the device that last wrote>",
  "updated_at": 1750000000.0,
  "entries": [ Entry, ... ]
}
```

### Entry

```json
{
  "id": "<uuid, stable across devices>",
  "kind": "login | api | ssh | note",
  "title": "", "website": "", "app": "",
  "username": "", "email": "", "password": "",
  "region": "", "age": "", "gender": "", "phone": "",
  "notes": "",
  "custom": { "any label": "any value" },
  "fields": { "kind-specific key": "value" },
  "password_policy": {
    "length": 16, "use_lower": true, "use_upper": true,
    "use_digits": true, "use_symbols": true,
    "avoid_ambiguous": true, "allowed_symbols": "!@#$%^&*-_=+?"
  },
  "created_at": 1750000000.0,
  "updated_at": 1750000000.0,
  "deleted": false
}
```

### Entry kinds (content v2)

`kind` says what the entry holds. Logins use the top-level fields; the other
kinds keep their values in `fields`. Secret keys are hidden until revealed.

| kind | `fields` keys (secret ones in **bold**) |
|---|---|
| `login` | (top-level `website`, `username`, `email`, **`password`**, …) |
| `api` | `service`, `endpoint`, `client_id`, **`client_secret`**, **`api_key`**, **`token`** |
| `ssh` | `host`, `port`, `ssh_user`, **`private_key`**, **`passphrase`**, `public_key`, `fingerprint` |
| `note` | (top-level **`notes`** is the note body) |

A content-v1 entry has no `kind` and reads as `login`.

## Sync rules

- Entries are identified by their `id` (a UUID), stable across all devices.
- `updated_at` is a Unix timestamp (seconds, float). On conflict for the same
  `id`, **the entry with the larger `updated_at` wins** (last‑write‑wins).
- Deletion is a **tombstone**: `deleted = true` with a bumped `updated_at`.
  Never hard‑delete during sync, or the deletion would be "resurrected" by the
  other device's older copy.
- Merging two vaults = union of all entry ids, keeping the newest version of
  each. Clocks should be reasonably in sync.

## QR sync protocol (v2)

1. The PC opens a TCP listener (port 8789, or any free port) and shows a QR code:
   `myvault://sync?v=2&h=<ip>[,<ip>…]&p=<port>&k=<base64url, 32 random bytes>`.
   The listener accepts **one** successful sync, or closes after 120 s.
2. The phone scans it and connects to the first reachable `h`.
3. Messages are `4-byte big-endian length || nonce(12) || AES-256-GCM(json)`,
   keyed by `k`, with AAD `MYVAULT_SYNC_v2|<c2s or s2c>|<seq>`.
4. Phone sends `c2s 0 {type:hello, protocol, device_id}`, PC answers `s2c 0` hello.
   Phone sends `c2s 1 {type:entries, entries:[…]}`, PC answers `s2c 1` entries.
5. Both sides merge with the rules above and save.

The key never touches the network and is never derived from a password, so a
recorded session can't be decrypted or brute-forced later. A connection that
fails the GCM check is ignored and the PC keeps waiting for the real phone.

### Version and update hand-over (0.5+)

The hello also carries `app_version`, `platform` (`windows` / `android`) and
`offers` (`{platform: version}` of the update packages the device holds). Older
apps don't send these; then nothing below happens and the sync is unchanged.

After the entries (message 1 each way), both sides send message 2
`{type: want, platform: <own platform or "">}`, asking for a package when the
peer offers one newer than its own version. Then the server's package goes
first, the client's second, each as one JSON header
`{type: package, platform, version, size, manifest: <base64>, sig}` (or
`{type: package, platform: ""}` if it has nothing after all) followed by the
file as raw AES-GCM frames of up to 1 MB, numbered on from the same counter.
A failed hand-over never undoes the sync that already happened.

## Releases and updates

Each package is listed in a manifest:

```json
{"app": "MyVault", "version": "0.5.0", "notes": "...",
 "files": {"windows": {"name": "MyVault-Setup-0.5.0.exe", "size": 0, "sha256": "..."},
           "android": {"name": "MyVault-0.5.0.apk", "size": 0, "sha256": "..."}}}
```

signed with Ed25519 (the `.sig` file is the base64 signature over the exact
manifest bytes). The public key is built into the apps (`UPDATE_PUBKEY` in
`myvault/update.py`); the private key never leaves the maintainer's machine.
The PC installs nothing unless the signature verifies and the file's SHA-256
matches. Android additionally refuses an APK not signed with MyVault's release
key. Online, the apps read `latest.json` and `latest.json.sig` from
`https://github.com/AhmedMKAlzoubi/myvault/releases/latest/download/`, but only
after the user has agreed, and at most once a day.

## Paper backup (encrypted PDF)

Each entry is printed as one block, shown both as Base32 text and as a QR code:

```
block = "MVP1" || salt(16) || nonce(12) || AES-256-GCM(zlib(entry JSON), aad = "MVP1" || salt)
key   = scrypt(backup password, salt, N=2^17, r=8, p=1, dkLen=32)
```

The JSON drops empty values. Base32 is RFC 4648 without padding, printed in
groups of four, 40 characters a line, under an `ENTRY n / total` heading. Readers
ignore spaces and case. The salt is repeated in every block, so a torn page
doesn't stop the others decrypting.

## Notes for implementers

- Keep the envelope and payload byte‑for‑byte JSON‑compatible; do not add
  required fields without bumping `version` / `content_version`.
- Unknown fields should be **preserved** on round‑trip where possible, so newer
  entries survive being edited by an older app.
