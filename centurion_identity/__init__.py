"""Who is asking.

The Brain's identity layer: people, passkeys, sessions and the audit of who did
what. It exists so that a multi-person Brain is not one shared key, and so that
every product built on the Brain — the practice desk, the web Desk, the phones —
answers to the same question: *which person is this?*

Deliberately dependency-free: SQLite from the standard library, and passkey
verification done by hand in :mod:`centurion_identity.webauthn` rather than
pulled in from a vendor library that can change under us.
"""

from centurion_identity.store import (
    IdentityError,
    IdentityStore,
    Person,
    default_db_path,
)

__all__ = ["IdentityError", "IdentityStore", "Person", "default_db_path"]
