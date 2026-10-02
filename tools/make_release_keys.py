"""One-time: create MyVault's release keys in %USERPROFILE%\\.myvault-release\\.

    .venv\\Scripts\\python tools\\make_release_keys.py

Makes two keys, kept OUTSIDE the repo so they can never be committed:
  * myvault-release.jks  - the Android signing key. Android only installs an
    update signed with the same key, so this key IS the phone app's identity.
  * update_key.pem       - the Ed25519 key that signs latest.json, the release
    manifest the apps check before installing any update.
Refuses to overwrite existing keys: losing or replacing them breaks updates.
"""

from __future__ import annotations

import os
import secrets
import subprocess
import sys
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

HOME = Path.home() / ".myvault-release"
KEYTOOL = Path.home() / "dev" / "jdk-17.0.19+10" / "bin" / "keytool.exe"

README = """MyVault release keys. KEEP THIS FOLDER SAFE AND PRIVATE.

myvault-release.jks   Android signing key. If you lose it, phones can't take
                      updates any more (everyone would have to uninstall and
                      reinstall). If someone else gets it AND your update key,
                      they could make an APK your phones accept.
key.properties        The keystore's passwords (read by the Android build).
update_key.pem        Signs latest.json for every release. The apps refuse an
                      update whose manifest isn't signed by this key.
update_key.pub        The public half (also built into the apps).

Back up this whole folder (USB stick, and/or a secure note in MyVault with the
passwords from key.properties). Never commit it, never upload it anywhere.
"""


def main() -> None:
    HOME.mkdir(exist_ok=True)
    jks, props, upd = HOME / "myvault-release.jks", HOME / "key.properties", HOME / "update_key.pem"
    if jks.exists() or upd.exists():
        sys.exit(f"Keys already exist in {HOME}. Not touching them.")

    pw = secrets.token_urlsafe(24)   # PKCS12: store and key share one password
    subprocess.run([str(KEYTOOL), "-genkeypair", "-keystore", str(jks), "-storetype", "PKCS12",
                    "-alias", "myvault", "-keyalg", "RSA", "-keysize", "4096", "-validity", "36500",
                    "-dname", "CN=MyVault, O=Ahmed Mohammed",
                    "-storepass", pw, "-keypass", pw], check=True, capture_output=True)
    props.write_text(f"storeFile={jks.as_posix()}\nstorePassword={pw}\nkeyAlias=myvault\nkeyPassword={pw}\n", "utf-8")

    key = Ed25519PrivateKey.generate()
    upd.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                      serialization.NoEncryption()))
    pub = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    (HOME / "update_key.pub").write_text(pub.hex() + "\n", "utf-8")
    (HOME / "README-KEEP-SAFE.txt").write_text(README, "utf-8")
    if os.name == "nt":   # this user only
        subprocess.run(["icacls", str(HOME), "/inheritance:r", "/grant:r", f"{os.environ['USERNAME']}:(OI)(CI)F"],
                       check=True, capture_output=True)
    print("Keys created in", HOME)
    print("Update public key (goes into the apps):", pub.hex())


if __name__ == "__main__":
    main()
