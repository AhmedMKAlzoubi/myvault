# MyVault file format (v1)

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
  "content_version": 1,
  "device_id": "<uuid of the device that last wrote>",
  "updated_at": 1750000000.0,
  "entries": [ Entry, ... ]
}
```

### Entry

```json
{
  "id": "<uuid, stable across devices>",
  "title": "", "website": "", "app": "",
  "username": "", "email": "", "password": "",
  "region": "", "age": "", "gender": "", "phone": "",
  "notes": "",
  "custom": { "any label": "any value" },
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

## Sync rules (for the planned LAN sync)

- Entries are identified by their `id` (a UUID), stable across all devices.
- `updated_at` is a Unix timestamp (seconds, float). On conflict for the same
  `id`, **the entry with the larger `updated_at` wins** (last‑write‑wins).
- Deletion is a **tombstone**: `deleted = true` with a bumped `updated_at`.
  Never hard‑delete during sync, or the deletion would be "resurrected" by the
  other device's older copy.
- Merging two vaults = union of all entry ids, keeping the newest version of
  each. Clocks should be reasonably in sync; a future version may switch to a
  logical clock if this proves fragile.

## Notes for implementers

- Keep the envelope and payload byte‑for‑byte JSON‑compatible; do not add
  required fields without bumping `version` / `content_version`.
- Unknown fields should be **preserved** on round‑trip where possible, so newer
  entries survive being edited by an older app.
