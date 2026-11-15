"""The identity store — people, passkeys, sessions, invitations, audit.

One SQLite file beside the rest of the Brain's state. No ORM, no service, no
network: a customer's Brain must be able to answer "who is this?" with the
machine switched off from the internet.

Design rules that are not negotiable here:

* A passkey is the credential. There is no password to reset, lose, or leak.
* Session tokens are stored hashed. A stolen database does not hand over live
  sessions.
* Invitations are single-use and time-boxed, and redeeming one is the only way
  a person exists other than the first owner.
* Every change of consequence is written to the audit table with who did it.
* Sign-in is throttled per bucket. The throttle lives in the database, not in
  memory, because a restart must not hand an attacker a fresh budget.
"""

from __future__ import annotations

import hashlib
import json
import secrets
import sqlite3
import threading
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

ROLES = ("owner", "admin", "member")
SESSION_DAYS = 30
INVITATION_MINUTES = 15
SUCCESS = 0

SCHEMA = """
CREATE TABLE IF NOT EXISTS people (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    email       TEXT NOT NULL UNIQUE COLLATE NOCASE,
    role        TEXT NOT NULL,
    status      TEXT NOT NULL DEFAULT 'active',
    created_at  REAL NOT NULL,
    created_by  TEXT
);
CREATE TABLE IF NOT EXISTS credentials (
    id           TEXT PRIMARY KEY,
    person_id    TEXT NOT NULL,
    public_key   BLOB NOT NULL,
    sign_count   INTEGER NOT NULL DEFAULT 0,
    algorithm    INTEGER,
    label        TEXT,
    transports   TEXT,
    created_at   REAL NOT NULL,
    last_used_at REAL,
    revoked_at   REAL
);
CREATE INDEX IF NOT EXISTS credentials_by_person ON credentials(person_id);
CREATE TABLE IF NOT EXISTS sessions (
    token_hash   TEXT PRIMARY KEY,
    person_id    TEXT NOT NULL,
    created_at   REAL NOT NULL,
    last_seen_at REAL NOT NULL,
    expires_at   REAL NOT NULL,
    closed_at    REAL,
    user_agent   TEXT
);
CREATE TABLE IF NOT EXISTS invitations (
    token_hash  TEXT PRIMARY KEY,
    person_id   TEXT NOT NULL,
    created_at  REAL NOT NULL,
    expires_at  REAL NOT NULL,
    redeemed_at REAL,
    created_by  TEXT
);
CREATE TABLE IF NOT EXISTS audit (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    at        REAL NOT NULL,
    person_id TEXT,
    action    TEXT NOT NULL,
    detail    TEXT
);
CREATE TABLE IF NOT EXISTS attempts (
    bucket       TEXT PRIMARY KEY,
    window_start REAL NOT NULL,
    count        INTEGER NOT NULL DEFAULT 0
);
"""


class IdentityError(Exception):
    """A refusal the caller is meant to read."""


@dataclass
class Person:
    id: str
    name: str
    email: str
    role: str
    status: str
    created_at: float

    @property
    def active(self) -> bool:
        return self.status == "active"

    def public(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "email": self.email,
            "role": self.role,
            "status": self.status,
        }


def default_db_path() -> Path:
    try:
        from centurion_constants import get_centurion_home

        return Path(get_centurion_home()) / "identity.db"
    except Exception:  # noqa: BLE001
        return Path.home() / ".centurion" / "identity.db"


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _new_token() -> str:
    return secrets.token_urlsafe(32)


def _person(row: sqlite3.Row) -> Person:
    return Person(
        id=row["id"],
        name=row["name"],
        email=row["email"],
        role=row["role"],
        status=row["status"],
        created_at=row["created_at"],
    )


class IdentityStore:
    """People and how they prove who they are."""

    def __init__(self, path: Optional[Path] = None) -> None:
        self.path = Path(path) if path else default_db_path()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        self._conn = sqlite3.connect(str(self.path), check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.executescript(SCHEMA)
        self._conn.commit()

    # ── lifecycle ───────────────────────────────────────────────────────────

    def close(self) -> None:
        with self._lock:
            self._conn.close()

    def is_claimed(self) -> bool:
        with self._lock:
            row = self._conn.execute("SELECT COUNT(*) AS n FROM people").fetchone()
        return bool(row["n"])

    def people_count(self) -> int:
        with self._lock:
            row = self._conn.execute(
                "SELECT COUNT(*) AS n FROM people WHERE status = 'active'"
            ).fetchone()
        return int(row["n"])

    # ── people ──────────────────────────────────────────────────────────────

    def claim(self, name: str, email: str) -> Person:
        """The first person on a Brain. Runs once, and only once.

        Whoever holds the machine gets the owner seat. This is the analogue of
        plugging a monitor in: physical access is the first credential, and the
        passkey they register next replaces it.
        """
        name = " ".join((name or "").split())
        email = (email or "").strip().lower()
        if not name:
            raise IdentityError("A name is needed before this machine can be claimed.")
        if "@" not in email:
            raise IdentityError("An email address is needed for sign-in.")
        with self._lock:
            existing = self._conn.execute("SELECT COUNT(*) AS n FROM people").fetchone()
            if existing["n"]:
                raise IdentityError(
                    "This Brain already has an owner. Ask them for an invitation."
                )
            person_id = uuid.uuid4().hex
            now = time.time()
            self._conn.execute(
                "INSERT INTO people (id, name, email, role, status, created_at)"
                " VALUES (?, ?, ?, 'owner', 'active', ?)",
                (person_id, name, email, now),
            )
            self._conn.execute(
                "INSERT INTO audit (at, person_id, action, detail) VALUES (?, ?, ?, ?)",
                (now, person_id, "brain.claimed", email),
            )
            self._conn.commit()
            row = self._conn.execute("SELECT * FROM people WHERE id = ?", (person_id,)).fetchone()
        return _person(row)

    def admit(
        self, name: str, email: str, *, role: str = "member", created_by: Optional[str] = None
    ) -> Person:
        name = " ".join((name or "").split())
        email = (email or "").strip().lower()
        if not name:
            raise IdentityError("A name is needed.")
        if "@" not in email:
            raise IdentityError("An email address is needed for sign-in.")
        if role not in ROLES:
            raise IdentityError(f"Unknown role: {role}")
        if role == "owner":
            raise IdentityError("There is only one owner. Promote by changing a role, not by adding one.")
        with self._lock:
            if self._conn.execute("SELECT 1 FROM people WHERE email = ?", (email,)).fetchone():
                raise IdentityError(f"{email} is already on this Brain.")
            person_id = uuid.uuid4().hex
            now = time.time()
            self._conn.execute(
                "INSERT INTO people (id, name, email, role, status, created_at, created_by)"
                " VALUES (?, ?, ?, ?, 'active', ?, ?)",
                (person_id, name, email, role, now, created_by),
            )
            self._conn.execute(
                "INSERT INTO audit (at, person_id, action, detail) VALUES (?, ?, ?, ?)",
                (now, person_id, "person.admitted", f"{email} as {role}"),
            )
            self._conn.commit()
            row = self._conn.execute("SELECT * FROM people WHERE id = ?", (person_id,)).fetchone()
        return _person(row)

    def get_person(self, person_id: str) -> Optional[Person]:
        with self._lock:
            row = self._conn.execute("SELECT * FROM people WHERE id = ?", (person_id,)).fetchone()
        return _person(row) if row else None

    def person_by_email(self, email: str) -> Optional[Person]:
        with self._lock:
            row = self._conn.execute(
                "SELECT * FROM people WHERE email = ?", ((email or "").strip().lower(),)
            ).fetchone()
        return _person(row) if row else None

    def list_people(self) -> List[Person]:
        with self._lock:
            rows = self._conn.execute("SELECT * FROM people ORDER BY created_at").fetchall()
        return [_person(r) for r in rows]

    def set_role(self, person_id: str, role: str, *, by: Optional[str] = None) -> Person:
        if role not in ROLES:
            raise IdentityError(f"Unknown role: {role}")
        with self._lock:
            row = self._conn.execute("SELECT * FROM people WHERE id = ?", (person_id,)).fetchone()
            if not row:
                raise IdentityError("No such person.")
            if row["role"] == "owner" and role != "owner":
                raise IdentityError("The owner cannot demote themselves. Transfer ownership first.")
            self._conn.execute("UPDATE people SET role = ? WHERE id = ?", (role, person_id))
            self._conn.execute(
                "INSERT INTO audit (at, person_id, action, detail) VALUES (?, ?, ?, ?)",
                (time.time(), person_id, "person.role", f"{row['role']} -> {role}"),
            )
            self._conn.commit()
            fresh = self._conn.execute("SELECT * FROM people WHERE id = ?", (person_id,)).fetchone()
        return _person(fresh)

    # ── invitations ─────────────────────────────────────────────────────────

    def issue_invitation(self, person_id: str, *, by: Optional[str] = None) -> str:
        token = _new_token()
        now = time.time()
        with self._lock:
            if not self._conn.execute("SELECT 1 FROM people WHERE id = ?", (person_id,)).fetchone():
                raise IdentityError("No such person.")
            self._conn.execute(
                "INSERT INTO invitations (token_hash, person_id, created_at, expires_at, created_by)"
                " VALUES (?, ?, ?, ?, ?)",
                (
                    _hash_token(token),
                    person_id,
                    now,
                    now + INVITATION_MINUTES * 60,
                    by,
                ),
            )
            self._conn.execute(
                "INSERT INTO audit (at, person_id, action, detail) VALUES (?, ?, ?, ?)",
                (now, person_id, "invitation.issued", f"by {by or 'unknown'}"),
            )
            self._conn.commit()
        return token

    def person_for_invitation(self, token: str) -> Person:
        with self._lock:
            row = self._conn.execute(
                "SELECT * FROM invitations WHERE token_hash = ?", (_hash_token(token or ""),)
            ).fetchone()
            if not row:
                raise IdentityError("That link is not valid.")
            if row["redeemed_at"]:
                raise IdentityError("That link has already been used.")
            if row["expires_at"] < time.time():
                raise IdentityError("That link has expired. Ask for a fresh one.")
            person = self._conn.execute(
                "SELECT * FROM people WHERE id = ?", (row["person_id"],)
            ).fetchone()
        if not person:
            raise IdentityError("That link points at nobody.")
        return _person(person)

    def redeem_invitation(self, token: str) -> Person:
        person = self.person_for_invitation(token)
        with self._lock:
            self._conn.execute(
                "UPDATE invitations SET redeemed_at = ? WHERE token_hash = ?",
                (time.time(), _hash_token(token)),
            )
            self._conn.commit()
        return person

    # ── credentials ─────────────────────────────────────────────────────────

    def add_credential(
        self,
        person_id: str,
        credential_id: str,
        public_key: bytes,
        *,
        sign_count: int = 0,
        label: str = "",
        transports: Optional[List[str]] = None,
        algorithm: Optional[int] = None,
    ) -> None:
        now = time.time()
        with self._lock:
            if not self._conn.execute("SELECT 1 FROM people WHERE id = ?", (person_id,)).fetchone():
                raise IdentityError("No such person.")
            self._conn.execute(
                "INSERT OR REPLACE INTO credentials"
                " (id, person_id, public_key, sign_count, algorithm, label, transports, created_at)"
                " VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    credential_id,
                    person_id,
                    public_key,
                    sign_count,
                    algorithm,
                    label,
                    json.dumps(transports or []),
                    now,
                ),
            )
            self._conn.execute(
                "INSERT INTO audit (at, person_id, action, detail) VALUES (?, ?, ?, ?)",
                (now, person_id, "passkey.added", label or credential_id[:12]),
            )
            self._conn.commit()

    def credentials_for(self, person_id: str) -> List[Dict[str, Any]]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT * FROM credentials WHERE person_id = ? AND revoked_at IS NULL",
                (person_id,),
            ).fetchall()
        return [dict(r) for r in rows]

    def credential_by_id(self, credential_id: str) -> Optional[Dict[str, Any]]:
        with self._lock:
            row = self._conn.execute(
                "SELECT * FROM credentials WHERE id = ? AND revoked_at IS NULL",
                (credential_id,),
            ).fetchone()
        return dict(row) if row else None

    def touch_credential(self, credential_id: str, sign_count: int) -> None:
        with self._lock:
            self._conn.execute(
                "UPDATE credentials SET sign_count = ?, last_used_at = ? WHERE id = ?",
                (sign_count, time.time(), credential_id),
            )
            self._conn.commit()

    def revoke_credential(self, credential_id: str, *, by: Optional[str] = None) -> None:
        with self._lock:
            self._conn.execute(
                "UPDATE credentials SET revoked_at = ? WHERE id = ?",
                (time.time(), credential_id),
            )
            self._conn.execute(
                "INSERT INTO audit (at, person_id, action, detail) VALUES (?, ?, ?, ?)",
                (time.time(), by, "passkey.revoked", credential_id[:12]),
            )
            self._conn.commit()

    # ── sessions ────────────────────────────────────────────────────────────

    def open_session(self, person_id: str, *, user_agent: str = "") -> str:
        token = _new_token()
        now = time.time()
        with self._lock:
            self._conn.execute(
                "INSERT INTO sessions (token_hash, person_id, created_at, last_seen_at,"
                " expires_at, user_agent) VALUES (?, ?, ?, ?, ?, ?)",
                (
                    _hash_token(token),
                    person_id,
                    now,
                    now,
                    now + SESSION_DAYS * 86400,
                    (user_agent or "")[:200],
                ),
            )
            self._conn.execute(
                "INSERT INTO audit (at, person_id, action, detail) VALUES (?, ?, ?, ?)",
                (now, person_id, "session.opened", ""),
            )
            self._conn.commit()
        return token

    def resolve_session(self, token: str) -> Optional[Person]:
        if not token:
            return None
        digest = _hash_token(token)
        with self._lock:
            row = self._conn.execute(
                "SELECT * FROM sessions WHERE token_hash = ?", (digest,)
            ).fetchone()
            if not row or row["closed_at"] or row["expires_at"] < time.time():
                return None
            self._conn.execute(
                "UPDATE sessions SET last_seen_at = ? WHERE token_hash = ?",
                (time.time(), digest),
            )
            self._conn.commit()
            person = self._conn.execute(
                "SELECT * FROM people WHERE id = ?", (row["person_id"],)
            ).fetchone()
        if not person or person["status"] != "active":
            return None
        return _person(person)

    def close_session(self, token: str) -> None:
        with self._lock:
            self._conn.execute(
                "UPDATE sessions SET closed_at = ? WHERE token_hash = ?",
                (time.time(), _hash_token(token or "")),
            )
            self._conn.commit()

    def close_all_sessions(self, person_id: str) -> None:
        with self._lock:
            self._conn.execute(
                "UPDATE sessions SET closed_at = ? WHERE person_id = ? AND closed_at IS NULL",
                (time.time(), person_id),
            )
            self._conn.commit()

    # ── throttle ────────────────────────────────────────────────────────────

    def allow_attempt(self, bucket: str, *, limit: int = 20, window_seconds: int = 60) -> bool:
        """Sliding-window counter kept in the database.

        Deliberately not in memory: a restart must not hand an attacker a fresh
        budget, and two processes must share one budget.
        """
        now = time.time()
        with self._lock:
            row = self._conn.execute("SELECT * FROM attempts WHERE bucket = ?", (bucket,)).fetchone()
            if not row or now - row["window_start"] > window_seconds:
                self._conn.execute(
                    "INSERT OR REPLACE INTO attempts (bucket, window_start, count) VALUES (?, ?, 1)",
                    (bucket, now),
                )
                self._conn.commit()
                return True
            if row["count"] >= limit:
                self._conn.commit()
                return False
            self._conn.execute(
                "UPDATE attempts SET count = count + 1 WHERE bucket = ?", (bucket,)
            )
            self._conn.commit()
            return True

    def note_refusal(self, person_id: Optional[str], detail: str) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT INTO audit (at, person_id, action, detail) VALUES (?, ?, ?, ?)",
                (time.time(), person_id, "signin.refused", detail[:200]),
            )
            self._conn.commit()

    # ── audit ───────────────────────────────────────────────────────────────

    def audit_log(self, limit: int = 50) -> List[Dict[str, Any]]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT * FROM audit ORDER BY id DESC LIMIT ?", (limit,)
            ).fetchall()
        return [dict(r) for r in rows]
