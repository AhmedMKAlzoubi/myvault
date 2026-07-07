"""
Encryption for MyVault.

The whole vault is stored as ONE encrypted blob on disk. Nothing is readable
without your master password. We never store the master password itself.

How it works (in plain terms):
  1. Your master password is stretched into a strong 256-bit key using scrypt,
     a deliberately slow + memory-hard function. This makes password guessing
     extremely expensive for an attacker, even with a stolen vault file.
  2. That key encrypts the vault with AES-256-GCM. GCM also *authenticates*:
     if a single byte of the file is changed (or the password is wrong),
     decryption fails loudly instead of returning garbage.

This exact scheme (scrypt + AES-256-GCM, parameters stored in the file header)
is intentionally simple so the future Android/Linux apps can open the same file.
See VAULT_FORMAT.md for the on-disk layout.
"""

from __future__ import annotations

import base64
import binascii
import json
import os
from dataclasses import dataclass

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

MAGIC = "MYVAULT"
FORMAT_VERSION = 1

# scrypt cost parameters. Higher = slower to guess but slower to unlock.
# n must be a power of 2. These give ~32 MB memory use and unlock in a fraction
# of a second on a normal PC, while being painful to brute-force at scale.
SCRYPT_N = 2 ** 15  # 32768
SCRYPT_R = 8
SCRYPT_P = 1
KEY_LEN = 32        # 256-bit AES key
SALT_LEN = 16
NONCE_LEN = 12


class WrongPasswordError(Exception):
    """Raised when the master password is wrong or the file is corrupt/tampered."""


class VaultFormatError(Exception):
    """Raised when the file is not a recognizable MyVault file."""


@dataclass
class KdfParams:
    salt: bytes
    n: int = SCRYPT_N
    r: int = SCRYPT_R
    p: int = SCRYPT_P
    dklen: int = KEY_LEN

    def derive(self, password: str) -> bytes:
        kdf = Scrypt(salt=self.salt, length=self.dklen, n=self.n, r=self.r, p=self.p)
        return kdf.derive(password.encode("utf-8"))


def _b64e(raw: bytes) -> str:
    return base64.b64encode(raw).decode("ascii")


def _b64d(text: str) -> bytes:
    return base64.b64decode(text.encode("ascii"))


def encrypt(plaintext: bytes, password: str) -> bytes:
    """Encrypt raw bytes with the master password. Returns the full file bytes."""
    params = KdfParams(salt=os.urandom(SALT_LEN))
    key = params.derive(password)
    nonce = os.urandom(NONCE_LEN)
    ciphertext = AESGCM(key).encrypt(nonce, plaintext, None)

    envelope = {
        "magic": MAGIC,
        "version": FORMAT_VERSION,
        "kdf": {
            "algo": "scrypt",
            "n": params.n,
            "r": params.r,
            "p": params.p,
            "dklen": params.dklen,
            "salt": _b64e(params.salt),
        },
        "cipher": {
            "algo": "AES-256-GCM",
            "nonce": _b64e(nonce),
            "data": _b64e(ciphertext),
        },
    }
    return json.dumps(envelope, indent=2).encode("utf-8")


def decrypt(file_bytes: bytes, password: str) -> bytes:
    """Decrypt a MyVault file. Raises WrongPasswordError on bad password/tamper."""
    try:
        envelope = json.loads(file_bytes.decode("utf-8"))
    except (ValueError, UnicodeDecodeError) as exc:
        raise VaultFormatError("File is not valid MyVault data.") from exc

    if envelope.get("magic") != MAGIC:
        raise VaultFormatError("This is not a MyVault file.")

    try:
        kdf = envelope["kdf"]
        params = KdfParams(
            salt=_b64d(kdf["salt"]),
            n=int(kdf["n"]),
            r=int(kdf["r"]),
            p=int(kdf["p"]),
            dklen=int(kdf["dklen"]),
        )
        nonce = _b64d(envelope["cipher"]["nonce"])
        data = _b64d(envelope["cipher"]["data"])
    except (KeyError, ValueError, TypeError, binascii.Error) as exc:
        raise VaultFormatError("The vault file is corrupt or unreadable.") from exc

    key = params.derive(password)
    try:
        return AESGCM(key).decrypt(nonce, data, None)
    except InvalidTag as exc:
        raise WrongPasswordError("Wrong master password (or the file was altered).") from exc
