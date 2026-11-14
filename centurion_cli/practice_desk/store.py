"""The practice desk's own record: people, credentials, sessions, conversations.

Separate database from the session store on purpose. `SessionDB` is the
Centurion's conversational memory; this is the practice's register of *who exists*
and *what they were allowed to do*. Mixing the two would mean a chat export
carries the practice's user list, and the user list is the thing that has to
survive a machine being rebuilt.

Schema decisions worth naming:

* **No passwords are stored, and no column exists to store one.** A passkey's
  public key is the whole credential. There is nothing in this file that a
  stolen copy can be used to log in with.
* **Invitations store a hash of the token, never the token.** Same reason as
  sessions: a readable database must not be a working set of live links.
* **`scope` and `client_id` exist on conversations from the first version.**
  Build A only writes `private`, but the column is here because a practice that
  starts on private threads and later adds client threads must not face a
  migration over their own history.
* **Capacity is asked of the licence, never re-implemented.** `admit_person`
  calls `current_edition().refusal(...)`, so the eleventh-user message a partner
  reads is the licence's own published sentence and cannot drift from it.
"""

from __future__ import annotations

import hashlib
import json
import os
import secrets
import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

SCHEMA_VERSION = 1

ROLES = ("partner", "manager", "associate", "administrator")

# Status is a small closed set. 'invited' is not yet a user: the seat is
# reserved, the person cannot log in, and a suspension can return to 'invited'.
STATUSES = ("invited", "active", "suspended", "departed")

SCOPES = ("private", "client", "practice")

SESSION_TTL_SECONDS = 15 * 60  # the desk locks after a quarter of an hour idle
INVITE_TTL_SECONDS = 15 * 60


class DeskError(Exception):
    """A refusal a human should read. The message is the sentence on screen."""


def default_db_path() -> Path:
    from centurion_constants import get_centurion_home

    path = Path(get_centurion_home()) / "practice"
    path.mkdir(parents=True, exist_ok=True)
    return path / "practice.db"


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def new_token() -> str:
    return secrets.token_urlsafe(32)


def _now() -> float:
    return time.time()


@dataclass
class Person:
    id: str
    name: str
    email: str
    role: str
    status: str
    created_at: float
    created_by: Optional[str]
    enrolled_at: Optional[float]
    last_seen_at: Optional[float]

    @property
    def is_active(self) -> bool:
        return self.status == "active"


class PracticeStore:
    """The practice register. One connection per call; SQLite handles the locking."""

    def __init__(self, path: Optional[Path] = None) -> None:
        self.path = Path(path) if path else default_db_path()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._init_schema()

    # ── plumbing ────────────────────────────────────────────────────────────

    def connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(str(self.path), timeout=10.0)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA foreign_keys=ON")
        return conn

    def _init_schema(self) -> None:
        with self.connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS meta (
                    key   TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS people (
                    id           TEXT PRIMARY KEY,
                    name         TEXT NOT NULL,
                    email        TEXT NOT NULL UNIQUE,
                    role         TEXT NOT NULL,
                    status       TEXT NOT NULL DEFAULT 'invited',
                    created_at   REAL NOT NULL,
                    created_by   TEXT,
                    enrolled_at  REAL,
                    last_seen_at REAL
                );

                CREATE TABLE IF NOT EXISTS invitations (
                    token_hash TEXT PRIMARY KEY,
                    person_id  TEXT NOT NULL REFERENCES people(id),
                    issued_at  REAL NOT NULL,
                    expires_at REAL NOT NULL,
                    used_at    REAL
                );

                CREATE TABLE IF NOT EXISTS credentials (
                    id           TEXT PRIMARY KEY,
                    person_id    TEXT NOT NULL REFERENCES people(id),
                    public_key   BLOB NOT NULL,
                    algorithm    INTEGER NOT NULL,
                    sign_count   INTEGER NOT NULL DEFAULT 0,
                    label        TEXT,
                    created_at   REAL NOT NULL,
                    last_used_at REAL,
                    revoked_at   REAL
                );

                CREATE TABLE IF NOT EXISTS sessions (
                    token_hash   TEXT PRIMARY KEY,
                    person_id    TEXT NOT NULL REFERENCES people(id),
                    created_at   REAL NOT NULL,
                    expires_at   REAL NOT NULL,
                    last_seen_at REAL NOT NULL,
                    user_agent   TEXT
                );

                CREATE TABLE IF NOT EXISTS audit (
                    id        INTEGER PRIMARY KEY AUTOINCREMENT,
                    at        REAL NOT NULL,
                    person_id TEXT,
                    action    TEXT NOT NULL,
                    scope     TEXT,
                    client_id TEXT,
                    detail    TEXT
                );

                CREATE TABLE IF NOT EXISTS conversations (
                    id         TEXT PRIMARY KEY,
                    owner_id   TEXT NOT NULL REFERENCES people(id),
                    scope      TEXT NOT NULL DEFAULT 'private',
                    client_id  TEXT,
                    title      TEXT,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS messages (
                    id              INTEGER PRIMARY KEY AUTOINCREMENT,
                    conversation_id TEXT NOT NULL REFERENCES conversations(id),
                    role            TEXT NOT NULL,
                    content         TEXT NOT NULL,
                    at              REAL NOT NULL,
                    person_id       TEXT,
                    cites           TEXT,
                    unsettled       TEXT
                );

                CREATE INDEX IF NOT EXISTS idx_messages_conv
                    ON messages(conversation_id, id);
                CREATE INDEX IF NOT EXISTS idx_sessions_expiry
                    ON sessions(expires_at);
                CREATE TABLE IF NOT EXISTS assignments (
                    client_slug TEXT NOT NULL,
                    person_id   TEXT NOT NULL REFERENCES people(id),
                    created_at  REAL NOT NULL,
                    created_by  TEXT,
                    PRIMARY KEY (client_slug, person_id)
                );

                CREATE INDEX IF NOT EXISTS idx_audit_at ON audit(at);
                CREATE INDEX IF NOT EXISTS idx_assign_person
                    ON assignments(person_id);
                """
            )
            row = conn.execute("SELECT value FROM meta WHERE key = 'schema_version'").fetchone()
            if row is None:
                conn.execute(
                    "INSERT INTO meta(key, value) VALUES ('schema_version', ?)",
                    (str(SCHEMA_VERSION),),
                )

    # ── capacity: the licence owns the number ───────────────────────────────

    def seat_usage(self) -> Dict[str, Any]:
        """How many seats are taken, and by whom. 'invited' counts — the seat is held."""
        with self.connect() as conn:
            rows = conn.execute(
                "SELECT status, COUNT(*) AS n FROM people GROUP BY status"
            ).fetchall()
        counts = {r["status"]: r["n"] for r in rows}
        held = counts.get("invited", 0) + counts.get("active", 0) + counts.get("suspended", 0)
        return {
            "held": held,
            "by_status": counts,
            "active": counts.get("active", 0),
            "departed": counts.get("departed", 0),
        }

    def capacity_refusal(self, adding: int = 1) -> Optional[str]:
        """The licence's own sentence, or None if there is room.

        Deliberately reads the edition rather than a constant: the published
        eleventh-user refusal must be the same words in the register, in the CLI
        and in the agreement.
        """
        from centurion.license.edition import current_edition

        held = self.seat_usage()["held"]
        return current_edition().refusal(held + adding)

    # ── people ──────────────────────────────────────────────────────────────

    def admit_person(
        self,
        *,
        name: str,
        email: str,
        role: str,
        created_by: Optional[str] = None,
        now: Optional[float] = None,
    ) -> Person:
        """Reserve a seat and issue an invitation. Refuses before it writes."""
        name = (name or "").strip()
        email = (email or "").strip().lower()
        role = (role or "").strip().lower()
        if not name:
            raise DeskError("A named user needs a name.")
        if "@" not in email:
            raise DeskError("A named user needs a work email address.")
        if role not in ROLES:
            raise DeskError(f"Role must be one of: {', '.join(ROLES)}.")

        refusal = self.capacity_refusal(1)
        if refusal:
            raise DeskError(refusal)

        at = _now() if now is None else now
        person_id = secrets.token_urlsafe(9)
        with self.connect() as conn:
            exists = conn.execute(
                "SELECT 1 FROM people WHERE email = ?", (email,)
            ).fetchone()
            if exists:
                raise DeskError(f"{email} is already on this machine.")
            conn.execute(
                "INSERT INTO people(id, name, email, role, status, created_at, created_by)"
                " VALUES (?, ?, ?, ?, 'invited', ?, ?)",
                (person_id, name, email, role, at, created_by),
            )
            self._audit(conn, created_by, "person_admitted", detail=f"{name} <{email}> as {role}")
        return self.get_person(person_id)  # type: ignore[return-value]

    def get_person(self, person_id: str) -> Optional[Person]:
        with self.connect() as conn:
            row = conn.execute("SELECT * FROM people WHERE id = ?", (person_id,)).fetchone()
        return _person(row) if row else None

    def person_by_email(self, email: str) -> Optional[Person]:
        with self.connect() as conn:
            row = conn.execute(
                "SELECT * FROM people WHERE email = ?", ((email or "").strip().lower(),)
            ).fetchone()
        return _person(row) if row else None

    def list_people(self, include_departed: bool = False) -> List[Person]:
        sql = "SELECT * FROM people"
        if not include_departed:
            sql += " WHERE status != 'departed'"
        sql += " ORDER BY created_at ASC"
        with self.connect() as conn:
            rows = conn.execute(sql).fetchall()
        return [_person(r) for r in rows]

    def set_status(self, person_id: str, status: str, *, by: Optional[str] = None) -> None:
        if status not in STATUSES:
            raise DeskError(f"Unknown status: {status}")
        with self.connect() as conn:
            conn.execute("UPDATE people SET status = ? WHERE id = ?", (status, person_id))
            if status in ("suspended", "departed"):
                # Suspension must take effect on the next request, not at the next
                # login. Killing the sessions is the only version of this that is true.
                conn.execute("DELETE FROM sessions WHERE person_id = ?", (person_id,))
            self._audit(conn, by, f"person_{status}", detail=person_id)

    # ── invitations ─────────────────────────────────────────────────────────

    def issue_invitation(self, person_id: str, *, by: Optional[str] = None) -> str:
        """Returns the token. The caller shows it once; it is stored hashed."""
        token = new_token()
        at = _now()
        with self.connect() as conn:
            conn.execute(
                "INSERT INTO invitations(token_hash, person_id, issued_at, expires_at)"
                " VALUES (?, ?, ?, ?)",
                (_hash_token(token), person_id, at, at + INVITE_TTL_SECONDS),
            )
            self._audit(conn, by, "invitation_issued", detail=person_id)
        return token

    def redeem_invitation(self, token: str) -> Person:
        at = _now()
        with self.connect() as conn:
            row = conn.execute(
                "SELECT * FROM invitations WHERE token_hash = ?",
                (_hash_token(token or ""),),
            ).fetchone()
            if row is None:
                raise DeskError("That invitation is not recognised. Ask a partner for a new one.")
            if row["used_at"] is not None:
                raise DeskError("That invitation has already been used.")
            if row["expires_at"] < at:
                raise DeskError("That invitation has expired. Ask a partner for a new one.")
            conn.execute(
                "UPDATE invitations SET used_at = ? WHERE token_hash = ?",
                (at, row["token_hash"]),
            )
            person = conn.execute(
                "SELECT * FROM people WHERE id = ?", (row["person_id"],)
            ).fetchone()
        if person is None:
            raise DeskError("That invitation points at a person who is no longer here.")
        return _person(person)

    # ── credentials ─────────────────────────────────────────────────────────

    def add_credential(
        self,
        person_id: str,
        *,
        credential_id: str,
        public_key: bytes,
        algorithm: int,
        sign_count: int = 0,
        label: Optional[str] = None,
    ) -> None:
        at = _now()
        with self.connect() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO credentials(id, person_id, public_key, algorithm,"
                " sign_count, label, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (credential_id, person_id, public_key, algorithm, sign_count, label, at),
            )
            conn.execute(
                "UPDATE people SET status = 'active', enrolled_at = COALESCE(enrolled_at, ?)"
                " WHERE id = ?",
                (at, person_id),
            )
            self._audit(conn, person_id, "passkey_enrolled", detail=label or credential_id)

    def credentials_for(self, person_id: str) -> List[Dict[str, Any]]:
        with self.connect() as conn:
            rows = conn.execute(
                "SELECT * FROM credentials WHERE person_id = ? AND revoked_at IS NULL"
                " ORDER BY created_at ASC",
                (person_id,),
            ).fetchall()
            if not rows:
                # A person with no credential is not a person who can log in. The
                # caller needs to know which case it is.
                return []
            return [dict(r) for r in rows]

    def credential_by_id(self, credential_id: str) -> Optional[Dict[str, Any]]:
        with self.connect() as conn:
            row = conn.execute(
                "SELECT * FROM credentials WHERE id = ? AND revoked_at IS NULL",
                (credential_id,),
            ).fetchone()
        return dict(row) if row else None

    def touch_credential(self, credential_id: str, sign_count: int) -> None:
        with self.connect() as conn:
            conn.execute(
                "UPDATE credentials SET sign_count = ?, last_used_at = ? WHERE id = ?",
                (sign_count, _now(), credential_id),
            )

    def revoke_credential(self, credential_id: str, *, by: Optional[str] = None) -> None:
        with self.connect() as conn:
            conn.execute(
                "UPDATE credentials SET revoked_at = ? WHERE id = ?", (_now(), credential_id)
            )
            self._audit(conn, by, "passkey_revoked", detail=credential_id)

    def revoke_all_credentials(self, person_id: str, *, by: Optional[str] = None) -> None:
        with self.connect() as conn:
            conn.execute(
                "UPDATE credentials SET revoked_at = ? WHERE person_id = ? AND revoked_at IS NULL",
                (_now(), person_id),
            )
            conn.execute("DELETE FROM sessions WHERE person_id = ?", (person_id,))
            self._audit(conn, by, "all_passkeys_revoked", detail=person_id)

    # ── sessions ────────────────────────────────────────────────────────────

    def open_session(self, person_id: str, *, user_agent: str = "") -> str:
        token = new_token()
        at = _now()
        with self.connect() as conn:
            conn.execute(
                "INSERT INTO sessions(token_hash, person_id, created_at, expires_at,"
                " last_seen_at, user_agent) VALUES (?, ?, ?, ?, ?, ?)",
                (_hash_token(token), person_id, at, at + SESSION_TTL_SECONDS, at, user_agent[:200]),
            )
            conn.execute("UPDATE people SET last_seen_at = ? WHERE id = ?", (at, person_id))
            self._audit(conn, person_id, "signed_in")
        return token

    def resolve_session(self, token: str) -> Optional[Person]:
        """Slide the expiry forward on use. An expired or unknown token is nobody."""
        if not token:
            return None
        at = _now()
        with self.connect() as conn:
            row = conn.execute(
                "SELECT * FROM sessions WHERE token_hash = ?", (_hash_token(token),)
            ).fetchone()
            if row is None:
                return None
            if row["expires_at"] < at:
                conn.execute("DELETE FROM sessions WHERE token_hash = ?", (row["token_hash"],))
                return None
            person = conn.execute(
                "SELECT * FROM people WHERE id = ?", (row["person_id"],)
            ).fetchone()
            if person is None or person["status"] != "active":
                return None
            conn.execute(
                "UPDATE sessions SET expires_at = ?, last_seen_at = ? WHERE token_hash = ?",
                (at + SESSION_TTL_SECONDS, at, row["token_hash"]),
            )
        return _person(person)

    def close_session(self, token: str) -> None:
        with self.connect() as conn:
            conn.execute("DELETE FROM sessions WHERE token_hash = ?", (_hash_token(token),))

    def session_count(self) -> int:
        with self.connect() as conn:
            row = conn.execute(
                "SELECT COUNT(*) AS n FROM sessions WHERE expires_at > ?", (_now(),)
            ).fetchone()
        return int(row["n"]) if row else 0

    def sweep(self) -> None:
        """Drop what has expired. Called on start and hourly."""
        at = _now()
        with self.connect() as conn:
            conn.execute("DELETE FROM sessions WHERE expires_at < ?", (at,))
            conn.execute("DELETE FROM invitations WHERE expires_at < ? AND used_at IS NULL", (at,))

    # ── audit ───────────────────────────────────────────────────────────────

    def _audit(
        self,
        conn: sqlite3.Connection,
        person_id: Optional[str],
        action: str,
        *,
        scope: Optional[str] = None,
        client_id: Optional[str] = None,
        detail: Optional[str] = None,
    ) -> None:
        conn.execute(
            "INSERT INTO audit(at, person_id, action, scope, client_id, detail)"
            " VALUES (?, ?, ?, ?, ?, ?)",
            (_now(), person_id, action, scope, client_id, detail),
        )

    def record(
        self,
        person_id: Optional[str],
        action: str,
        *,
        scope: Optional[str] = None,
        client_id: Optional[str] = None,
        detail: Optional[str] = None,
    ) -> None:
        with self.connect() as conn:
            self._audit(
                conn, person_id, action, scope=scope, client_id=client_id, detail=detail
            )

    def audit_log(self, limit: int = 100) -> List[Dict[str, Any]]:
        with self.connect() as conn:
            rows = conn.execute(
                "SELECT * FROM audit ORDER BY id DESC LIMIT ?", (int(limit),)
            ).fetchall()
        return [dict(r) for r in rows]

    # ── assignments: who may see which client ───────────────────────────────

    def assign(self, client_slug: str, person_id: str, *, by: Optional[str] = None) -> None:
        slug = (client_slug or "").strip()
        if not slug:
            raise DeskError("An assignment needs a client.")
        if self.get_person(person_id) is None:
            raise DeskError("That person is not on this machine.")
        with self.connect() as conn:
            conn.execute(
                "INSERT OR IGNORE INTO assignments(client_slug, person_id, created_at, created_by)"
                " VALUES (?, ?, ?, ?)",
                (slug, person_id, _now(), by),
            )
            self._audit(conn, by, "client_assigned", client_id=slug, detail=person_id)

    def unassign(self, client_slug: str, person_id: str, *, by: Optional[str] = None) -> None:
        with self.connect() as conn:
            conn.execute(
                "DELETE FROM assignments WHERE client_slug = ? AND person_id = ?",
                (client_slug, person_id),
            )
            self._audit(conn, by, "client_unassigned", client_id=client_slug, detail=person_id)

    def assignees(self, client_slug: str) -> List[Person]:
        with self.connect() as conn:
            rows = conn.execute(
                "SELECT p.* FROM people p JOIN assignments a ON a.person_id = p.id"
                " WHERE a.client_slug = ? AND p.status != 'departed' ORDER BY p.name",
                (client_slug,),
            ).fetchall()
        return [_person(r) for r in rows]

    def assignments_for(self, person_id: str) -> List[str]:
        with self.connect() as conn:
            rows = conn.execute(
                "SELECT client_slug FROM assignments WHERE person_id = ? ORDER BY client_slug",
                (person_id,),
            ).fetchall()
        return [r["client_slug"] for r in rows]

    def may_see_client(self, person: Person, client_slug: str) -> bool:
        """The Firm rule, in one place.

        A partner sees every client — that is what a partner is. Everybody else
        sees only what they are assigned to. An administrator sees none of it:
        the role runs the machine, not the files.

        Deliberately fails closed on an unknown role, and a missing assignment is
        a refusal rather than a default.
        """
        if person.role == "partner":
            return True
        if person.role == "administrator":
            return False
        if not client_slug:
            return False
        return client_slug in self.assignments_for(person.id)

    # ── conversations ───────────────────────────────────────────────────────

    def conversation(
        self, conversation_id: str, *, person: Person
    ) -> Optional[Dict[str, Any]]:
        """Scoped read. Build A only writes private threads, but the permission
        check is written now so adding client threads cannot become a bypass."""
        with self.connect() as conn:
            row = conn.execute(
                "SELECT * FROM conversations WHERE id = ?", (conversation_id,)
            ).fetchone()
        if row is None:
            return None
        conv = dict(row)
        if conv["scope"] == "private" and conv["owner_id"] != person.id:
            return None
        if conv["scope"] == "client" and not self.may_see_client(person, conv.get("client_id")):
            return None
        return conv

    def ensure_conversation(
        self, *, person: Person, scope: str = "private", client_id: Optional[str] = None
    ) -> Dict[str, Any]:
        if scope not in SCOPES:
            raise DeskError(f"Unknown scope: {scope}")
        if scope != "private" and not client_id:
            raise DeskError("A shared thread must name its client.")
        at = _now()
        with self.connect() as conn:
            if scope == "private":
                row = conn.execute(
                    "SELECT * FROM conversations WHERE owner_id = ? AND scope = 'private'"
                    " ORDER BY created_at ASC LIMIT 1",
                    (person.id,),
                ).fetchone()
            elif scope == "client":
                row = conn.execute(
                    "SELECT * FROM conversations WHERE scope = 'client' AND client_id = ?"
                    " ORDER BY created_at ASC LIMIT 1",
                    (client_id,),
                ).fetchone()
            else:
                row = conn.execute(
                    "SELECT * FROM conversations WHERE scope = 'practice'"
                    " ORDER BY created_at ASC LIMIT 1"
                ).fetchone()
            if row is not None:
                return dict(row)
            conv_id = secrets.token_urlsafe(9)
            title = "Private thread" if scope == "private" else (client_id or "Practice")
            conn.execute(
                "INSERT INTO conversations(id, owner_id, scope, client_id, title,"
                " created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (conv_id, person.id, scope, client_id, title, at, at),
            )
        conv = self.conversation(conv_id, person=person)
        assert conv is not None
        return conv

    def append_message(
        self,
        conversation_id: str,
        *,
        role: str,
        content: str,
        person_id: Optional[str] = None,
        cites: Optional[List[str]] = None,
        unsettled: Optional[List[str]] = None,
    ) -> int:
        at = _now()
        with self.connect() as conn:
            cur = conn.execute(
                "INSERT INTO messages(conversation_id, role, content, at, person_id,"
                " cites, unsettled) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    conversation_id,
                    role,
                    content,
                    at,
                    person_id,
                    json.dumps(cites) if cites else None,
                    json.dumps(unsettled) if unsettled else None,
                ),
            )
            conn.execute(
                "UPDATE conversations SET updated_at = ? WHERE id = ?", (at, conversation_id)
            )
            return int(cur.lastrowid or 0)

    def messages(self, conversation_id: str, limit: int = 200) -> List[Dict[str, Any]]:
        with self.connect() as conn:
            rows = conn.execute(
                "SELECT * FROM messages WHERE conversation_id = ?"
                " ORDER BY id ASC LIMIT ?",
                (conversation_id, int(limit)),
            ).fetchall()
        out = []
        for r in rows:
            m = dict(r)
            m["cites"] = json.loads(m["cites"]) if m["cites"] else []
            m["unsettled"] = json.loads(m["unsettled"]) if m["unsettled"] else []
            out.append(m)
        return out


def _person(row: sqlite3.Row) -> Person:
    return Person(
        id=row["id"],
        name=row["name"],
        email=row["email"],
        role=row["role"],
        status=row["status"],
        created_at=row["created_at"],
        created_by=row["created_by"],
        enrolled_at=row["enrolled_at"],
        last_seen_at=row["last_seen_at"],
    )


def open_store(path: Optional[Path] = None) -> PracticeStore:
    """The store the service uses. Honours CENTURION_PRACTICE_DB for tests and demos."""
    if path is None:
        env = os.environ.get("CENTURION_PRACTICE_DB")
        if env:
            path = Path(env)
    return PracticeStore(path)
