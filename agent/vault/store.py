"""Vault SQLite store — sealed CRUD, FTS rebuild while unlocked."""

from __future__ import annotations

import hashlib
import json
import sqlite3
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

from centurion_state import apply_wal_with_fallback

from agent.vault.audit import append_audit
from agent.vault.crypto import (
    LockState,
    VaultLockedError,
    require_unlocked,
    seal,
    unseal,
)
from agent.vault.paths import db_path, ensure_vault_dir, secure_file
from agent.vault.schema import migrate
from agent.vault.types import (
    MemoryType,
    ProposalStatus,
    VaultEntry,
    VaultProposal,
)


def _utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def content_hash(text: str) -> str:
    return hashlib.sha256(text.strip().encode("utf-8")).hexdigest()


def _aad(entry_id: str, memory_type: str, created_at: str) -> bytes:
    return hashlib.sha256(
        f"{entry_id}|{memory_type}|{created_at}".encode("utf-8")
    ).digest()


class VaultStore:
    """Encrypted Vault backed by SQLite. Requires unlock for read/write."""

    def __init__(self, lock_state: Optional[LockState] = None):
        ensure_vault_dir()
        self._path = db_path()
        self._conn = sqlite3.connect(str(self._path), check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        apply_wal_with_fallback(self._conn, db_label="vault.db")
        migrate(self._conn)
        secure_file(self._path)
        self._lock = lock_state

    @property
    def is_unlocked(self) -> bool:
        return bool(self._lock and self._lock.unlocked and self._lock.dek)

    def set_lock_state(self, state: Optional[LockState]) -> None:
        if self._lock and self._lock is not state:
            self._lock.zeroize()
        self._lock = state
        if state and state.unlocked:
            append_audit(self._conn, "unlock", {})
            self._conn.commit()
            self.rebuild_fts()
        else:
            self.clear_fts()
            append_audit(self._conn, "lock", {})
            self._conn.commit()

    def lock(self) -> None:
        self.set_lock_state(None)

    def close(self) -> None:
        if self._lock:
            self._lock.zeroize()
            self._lock = None
        self._conn.close()

    def _dek(self) -> bytes:
        return require_unlocked(self._lock).dek

    def status(self) -> dict[str, Any]:
        counts = {"core": 0, "experiential": 0, "pattern": 0}
        for row in self._conn.execute(
            "SELECT memory_type, COUNT(*) AS n FROM entries GROUP BY memory_type"
        ):
            counts[row["memory_type"]] = row["n"]
        pending = self._conn.execute(
            "SELECT COUNT(*) FROM proposals WHERE status = 'pending'"
        ).fetchone()[0]
        return {
            "initialized": self._path.exists(),
            "unlocked": self.is_unlocked,
            "path": str(self._path),
            "counts": counts,
            "pending_proposals": pending,
            "total_entries": sum(counts.values()),
        }

    # --- proposals ---------------------------------------------------------

    def propose(
        self,
        *,
        memory_type: MemoryType,
        text: str,
        rationale: str = "",
        tags: Optional[list[str]] = None,
        importance: int = 5,
        source_session: Optional[str] = None,
    ) -> VaultProposal:
        dek = self._dek()
        now = _utc_now()
        pid = str(uuid.uuid4())
        ch = content_hash(text)
        body = {
            "text": text.strip(),
            "rationale": (rationale or "").strip(),
            "tags": list(tags or []),
            "importance": importance,
        }
        nonce, ciphertext = seal(dek, json.dumps(body).encode("utf-8"), aad=b"proposal")
        self._conn.execute(
            "INSERT INTO proposals(id, memory_type, ciphertext, nonce, status, "
            "created_at, content_hash, source_session, importance) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                pid,
                memory_type.value,
                ciphertext,
                nonce,
                ProposalStatus.PENDING.value,
                now,
                ch,
                source_session,
                importance,
            ),
        )
        append_audit(
            self._conn,
            "propose",
            {"id": pid, "type": memory_type.value, "hash": ch},
        )
        self._conn.commit()
        return VaultProposal(
            id=pid,
            memory_type=memory_type,
            text=body["text"],
            rationale=body["rationale"],
            tags=body["tags"],
            importance=importance,
            status=ProposalStatus.PENDING,
            created_at=now,
            content_hash=ch,
            source_session=source_session,
        )

    def _decrypt_proposal_row(self, row: sqlite3.Row) -> VaultProposal:
        dek = self._dek()
        raw = unseal(dek, bytes(row["nonce"]), bytes(row["ciphertext"]), aad=b"proposal")
        body = json.loads(raw.decode("utf-8"))
        return VaultProposal(
            id=row["id"],
            memory_type=MemoryType.parse(row["memory_type"]),
            text=body.get("text", ""),
            rationale=body.get("rationale", ""),
            tags=list(body.get("tags") or []),
            importance=int(row["importance"]),
            status=ProposalStatus(row["status"]),
            created_at=row["created_at"],
            decided_at=row["decided_at"],
            content_hash=row["content_hash"],
            source_session=row["source_session"],
        )

    def list_proposals(self, status: str = "pending") -> list[VaultProposal]:
        self._dek()
        rows = self._conn.execute(
            "SELECT * FROM proposals WHERE status = ? ORDER BY created_at DESC",
            (status,),
        ).fetchall()
        return [self._decrypt_proposal_row(r) for r in rows]

    def get_proposal(self, proposal_id: str) -> Optional[VaultProposal]:
        self._dek()
        row = self._conn.execute(
            "SELECT * FROM proposals WHERE id = ?", (proposal_id,)
        ).fetchone()
        if not row:
            return None
        return self._decrypt_proposal_row(row)

    def reject_proposal(self, proposal_id: str) -> VaultProposal:
        prop = self.get_proposal(proposal_id)
        if not prop:
            raise KeyError(f"Proposal not found: {proposal_id}")
        if prop.status != ProposalStatus.PENDING:
            raise ValueError(f"Proposal is already {prop.status.value}")
        now = _utc_now()
        self._conn.execute(
            "UPDATE proposals SET status = ?, decided_at = ? WHERE id = ?",
            (ProposalStatus.REJECTED.value, now, proposal_id),
        )
        append_audit(self._conn, "reject", {"id": proposal_id})
        self._conn.commit()
        prop.status = ProposalStatus.REJECTED
        prop.decided_at = now
        return prop

    def commit_proposal(self, proposal_id: str) -> VaultEntry:
        prop = self.get_proposal(proposal_id)
        if not prop:
            raise KeyError(f"Proposal not found: {proposal_id}")
        if prop.status != ProposalStatus.PENDING:
            raise ValueError(f"Proposal is already {prop.status.value}")

        # Dedupe
        existing = self._conn.execute(
            "SELECT id FROM entries WHERE content_hash = ?", (prop.content_hash,)
        ).fetchone()
        if existing:
            raise ValueError(
                f"Duplicate content already stored as entry {existing['id']}"
            )

        entry = self._insert_entry(
            memory_type=prop.memory_type,
            text=prop.text,
            rationale=prop.rationale,
            tags=prop.tags,
            importance=prop.importance,
            source_session=prop.source_session,
            content_hash_value=prop.content_hash,
        )
        now = _utc_now()
        self._conn.execute(
            "UPDATE proposals SET status = ?, decided_at = ? WHERE id = ?",
            (ProposalStatus.COMMITTED.value, now, proposal_id),
        )
        append_audit(
            self._conn,
            "commit",
            {"proposal_id": proposal_id, "entry_id": entry.id},
        )
        self._conn.commit()
        return entry

    # --- entries -----------------------------------------------------------

    def _insert_entry(
        self,
        *,
        memory_type: MemoryType,
        text: str,
        rationale: str = "",
        tags: Optional[list[str]] = None,
        importance: int = 5,
        source_session: Optional[str] = None,
        content_hash_value: Optional[str] = None,
    ) -> VaultEntry:
        dek = self._dek()
        now = _utc_now()
        eid = str(uuid.uuid4())
        ch = content_hash_value or content_hash(text)
        tags = list(tags or [])
        body = {
            "text": text.strip(),
            "rationale": (rationale or "").strip(),
            "tags": tags,
            "refs": {},
        }
        aad = _aad(eid, memory_type.value, now)
        nonce, ciphertext = seal(
            dek, json.dumps(body).encode("utf-8"), aad=aad
        )
        sealed_tags = None
        if tags:
            t_nonce, t_ct = seal(
                dek, json.dumps(tags).encode("utf-8"), aad=b"tags"
            )
            sealed_tags = t_nonce + t_ct  # store concatenated; rare path

        self._conn.execute(
            "INSERT INTO entries(id, memory_type, ciphertext, nonce, aad_hash, "
            "content_hash, created_at, updated_at, source_session, importance, sealed_tags) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                eid,
                memory_type.value,
                ciphertext,
                nonce,
                aad,
                ch,
                now,
                now,
                source_session,
                importance,
                sealed_tags,
            ),
        )
        # FTS while unlocked
        self._conn.execute(
            "INSERT INTO entries_fts(entry_id, memory_type, body) VALUES (?, ?, ?)",
            (eid, memory_type.value, body["text"]),
        )
        return VaultEntry(
            id=eid,
            memory_type=memory_type,
            text=body["text"],
            rationale=body["rationale"],
            tags=tags,
            importance=importance,
            created_at=now,
            updated_at=now,
            source_session=source_session,
            content_hash=ch,
        )

    def _decrypt_entry_row(self, row: sqlite3.Row) -> VaultEntry:
        dek = self._dek()
        aad = bytes(row["aad_hash"])
        raw = unseal(dek, bytes(row["nonce"]), bytes(row["ciphertext"]), aad=aad)
        body = json.loads(raw.decode("utf-8"))
        return VaultEntry(
            id=row["id"],
            memory_type=MemoryType.parse(row["memory_type"]),
            text=body.get("text", ""),
            rationale=body.get("rationale", ""),
            tags=list(body.get("tags") or []),
            importance=int(row["importance"]),
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            source_session=row["source_session"],
            content_hash=row["content_hash"],
            refs=dict(body.get("refs") or {}),
        )

    def get_entry(self, entry_id: str) -> Optional[VaultEntry]:
        self._dek()
        row = self._conn.execute(
            "SELECT * FROM entries WHERE id = ?", (entry_id,)
        ).fetchone()
        if not row:
            return None
        return self._decrypt_entry_row(row)

    def list_entry_ids(
        self, memory_type: Optional[MemoryType] = None
    ) -> list[sqlite3.Row]:
        if memory_type:
            return self._conn.execute(
                "SELECT id, memory_type, created_at, importance, content_hash "
                "FROM entries WHERE memory_type = ? ORDER BY created_at DESC",
                (memory_type.value,),
            ).fetchall()
        return self._conn.execute(
            "SELECT id, memory_type, created_at, importance, content_hash "
            "FROM entries ORDER BY created_at DESC"
        ).fetchall()

    def all_entries(self) -> list[VaultEntry]:
        self._dek()
        rows = self._conn.execute("SELECT * FROM entries").fetchall()
        return [self._decrypt_entry_row(r) for r in rows]

    # --- FTS ---------------------------------------------------------------

    def clear_fts(self) -> None:
        try:
            self._conn.execute("DELETE FROM entries_fts")
            self._conn.commit()
        except sqlite3.Error:
            pass

    def rebuild_fts(self) -> int:
        """Decrypt all entries and rebuild FTS. Requires unlock."""
        if not self.is_unlocked:
            raise VaultLockedError("Cannot rebuild FTS while locked")
        self._conn.execute("DELETE FROM entries_fts")
        count = 0
        for entry in self.all_entries():
            self._conn.execute(
                "INSERT INTO entries_fts(entry_id, memory_type, body) VALUES (?, ?, ?)",
                (entry.id, entry.memory_type.value, entry.text),
            )
            count += 1
        self._conn.commit()
        return count

    def fts_search(
        self,
        query: str,
        *,
        memory_type: Optional[MemoryType] = None,
        limit: int = 8,
    ) -> list[tuple[str, str, float]]:
        """Return list of (entry_id, snippet, bm25_score). Requires unlocked FTS."""
        self._dek()
        q = _sanitize_fts5(query)
        if not q:
            return []
        sql = (
            "SELECT entry_id, memory_type, snippet(entries_fts, 2, '', '', '…', 24) AS snip, "
            "bm25(entries_fts) AS score "
            "FROM entries_fts WHERE entries_fts MATCH ?"
        )
        params: list[Any] = [q]
        if memory_type:
            sql += " AND memory_type = ?"
            params.append(memory_type.value)
        sql += " ORDER BY score LIMIT ?"
        params.append(limit)
        rows = self._conn.execute(sql, params).fetchall()
        # bm25 is lower-is-better; convert to positive relevance
        out = []
        for r in rows:
            raw = float(r["score"])
            relevance = 1.0 / (1.0 + abs(raw))
            out.append((r["entry_id"], r["snip"] or "", relevance))
        return out

    # --- embeddings storage ------------------------------------------------

    def store_embedding(
        self,
        entry_id: str,
        vector: list[float],
        model_id: str,
    ) -> None:
        dek = self._dek()
        import struct

        packed = struct.pack(f"{len(vector)}f", *vector)
        nonce, ciphertext = seal(dek, packed, aad=b"embedding")
        self._conn.execute(
            "INSERT OR REPLACE INTO embeddings(entry_id, dim, ciphertext, nonce, model_id) "
            "VALUES (?, ?, ?, ?, ?)",
            (entry_id, len(vector), ciphertext, nonce, model_id),
        )
        self._conn.commit()

    def load_embedding(self, entry_id: str) -> Optional[tuple[list[float], str]]:
        dek = self._dek()
        import struct

        row = self._conn.execute(
            "SELECT dim, ciphertext, nonce, model_id FROM embeddings WHERE entry_id = ?",
            (entry_id,),
        ).fetchone()
        if not row:
            return None
        packed = unseal(
            dek, bytes(row["nonce"]), bytes(row["ciphertext"]), aad=b"embedding"
        )
        dim = int(row["dim"])
        vector = list(struct.unpack(f"{dim}f", packed))
        return vector, row["model_id"]

    def all_embeddings(self) -> list[tuple[str, list[float], str]]:
        dek = self._dek()
        import struct

        out = []
        for row in self._conn.execute(
            "SELECT entry_id, dim, ciphertext, nonce, model_id FROM embeddings"
        ):
            packed = unseal(
                dek, bytes(row["nonce"]), bytes(row["ciphertext"]), aad=b"embedding"
            )
            dim = int(row["dim"])
            vector = list(struct.unpack(f"{dim}f", packed))
            out.append((row["entry_id"], vector, row["model_id"]))
        return out


def _sanitize_fts5(query: str) -> str:
    """Strip FTS5 special chars; wrap tokens as phrases."""
    cleaned = "".join(
        ch if ch.isalnum() or ch.isspace() or ch in "-_" else " " for ch in query
    )
    tokens = [t for t in cleaned.split() if t]
    if not tokens:
        return ""
    return " ".join(f'"{t}"' for t in tokens[:12])
