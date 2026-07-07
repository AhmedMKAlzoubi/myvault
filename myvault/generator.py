"""
Password generator.

Every website has annoying, different rules ("must have a symbol", "8-20 chars",
"no special characters allowed"). Each entry stores its own PasswordPolicy so you
can regenerate a password that matches *that* site's rules whenever you need to.

Uses the OS cryptographically-secure random source (secrets), not random.random.
"""

from __future__ import annotations

import secrets
import string
from dataclasses import dataclass, field, asdict

# Characters that are easy to confuse when reading/typing a password by hand.
AMBIGUOUS = set("Il1O0o|`'\"{}[]()/\\~,;:.<>")

DEFAULT_SYMBOLS = "!@#$%^&*-_=+?"


@dataclass
class PasswordPolicy:
    length: int = 16
    use_lower: bool = True
    use_upper: bool = True
    use_digits: bool = True
    use_symbols: bool = True
    avoid_ambiguous: bool = True
    allowed_symbols: str = DEFAULT_SYMBOLS

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict | None) -> "PasswordPolicy":
        if not data:
            return cls()
        known = {f for f in cls.__dataclass_fields__}
        return cls(**{k: v for k, v in data.items() if k in known})


def _pool(policy: PasswordPolicy) -> tuple[list[str], str]:
    """Return (required_groups, full_pool). Each required group guarantees at
    least one character of that type appears in the result."""
    groups: list[str] = []
    if policy.use_lower:
        groups.append(string.ascii_lowercase)
    if policy.use_upper:
        groups.append(string.ascii_uppercase)
    if policy.use_digits:
        groups.append(string.digits)
    if policy.use_symbols and policy.allowed_symbols:
        groups.append(policy.allowed_symbols)

    if policy.avoid_ambiguous:
        groups = ["".join(c for c in g if c not in AMBIGUOUS) for g in groups]

    groups = [g for g in groups if g]
    full_pool = "".join(groups)
    return groups, full_pool


def generate(policy: PasswordPolicy) -> str:
    """Generate a random password satisfying the policy. Raises ValueError if
    the policy is impossible (no character types enabled)."""
    groups, full_pool = _pool(policy)
    if not full_pool:
        raise ValueError("Enable at least one character type.")

    length = max(policy.length, len(groups), 1)

    # Guarantee at least one char from each enabled group, then fill the rest.
    chars = [secrets.choice(g) for g in groups]
    chars += [secrets.choice(full_pool) for _ in range(length - len(chars))]

    # Shuffle so the guaranteed characters are not always at the front.
    for i in range(len(chars) - 1, 0, -1):
        j = secrets.randbelow(i + 1)
        chars[i], chars[j] = chars[j], chars[i]

    return "".join(chars)


def strength_label(password: str) -> str:
    """A rough, honest strength hint for the UI (not a security guarantee)."""
    if not password:
        return ""
    pool = 0
    if any(c.islower() for c in password):
        pool += 26
    if any(c.isupper() for c in password):
        pool += 26
    if any(c.isdigit() for c in password):
        pool += 10
    if any(not c.isalnum() for c in password):
        pool += 20
    # bits of entropy ~ length * log2(pool)
    import math
    bits = len(password) * (math.log2(pool) if pool else 0)
    if bits < 40:
        return "Weak"
    if bits < 70:
        return "Okay"
    if bits < 100:
        return "Strong"
    return "Very strong"
