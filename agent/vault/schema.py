"""Vault SQLite schema and migrations."""

from __future__ import annotations

import sqlite3

SCHEMA_VERSION = 1

DDL = """
CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS entries (
  id              TEXT PRIMARY KEY,
  memory_type     TEXT NOT NULL CHECK (memory_type IN ('core','experiential','pattern')),
  ciphertext      BLOB NOT NULL,
  nonce           BLOB NOT NULL,
  aad_hash        BLOB NOT NULL,
  content_hash    TEXT NOT NULL,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  source_session  TEXT,
  importance      INTEGER NOT NULL DEFAULT 5 CHECK (importance BETWEEN 1 AND 10),
  sealed_tags     BLOB
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_entries_content_hash ON entries(content_hash);

CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
  entry_id UNINDEXED,
  memory_type UNINDEXED,
  body,
  tokenize = 'porter unicode61'
);

CREATE TABLE IF NOT EXISTS embeddings (
  entry_id     TEXT PRIMARY KEY REFERENCES entries(id) ON DELETE CASCADE,
  dim          INTEGER NOT NULL,
  ciphertext   BLOB NOT NULL,
  nonce        BLOB NOT NULL,
  model_id     TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS proposals (
  id              TEXT PRIMARY KEY,
  memory_type     TEXT NOT NULL CHECK (memory_type IN ('core','experiential','pattern')),
  ciphertext      BLOB NOT NULL,
  nonce           BLOB NOT NULL,
  status          TEXT NOT NULL CHECK (status IN ('pending','committed','rejected')),
  created_at      TEXT NOT NULL,
  decided_at      TEXT,
  content_hash    TEXT NOT NULL,
  source_session  TEXT,
  importance      INTEGER NOT NULL DEFAULT 5
);

CREATE TABLE IF NOT EXISTS audit_events (
  seq          INTEGER PRIMARY KEY AUTOINCREMENT,
  ts           TEXT NOT NULL,
  event_type   TEXT NOT NULL,
  payload_hash TEXT NOT NULL,
  prev_hash    TEXT NOT NULL,
  entry_hash   TEXT NOT NULL
);
"""


def migrate(conn: sqlite3.Connection) -> int:
    """Apply DDL and set schema_version. Returns current version."""
    conn.executescript(DDL)
    row = conn.execute(
        "SELECT value FROM meta WHERE key = 'schema_version'"
    ).fetchone()
    if row is None:
        conn.execute(
            "INSERT INTO meta(key, value) VALUES ('schema_version', ?)",
            (str(SCHEMA_VERSION),),
        )
        conn.execute(
            "INSERT OR IGNORE INTO meta(key, value) VALUES ('created_at', datetime('now'))"
        )
    else:
        current = int(row[0])
        if current > SCHEMA_VERSION:
            raise RuntimeError(
                f"Vault DB schema {current} is newer than code {SCHEMA_VERSION}"
            )
        # Future migrations go here (current < SCHEMA_VERSION)
        if current < SCHEMA_VERSION:
            conn.execute(
                "UPDATE meta SET value = ? WHERE key = 'schema_version'",
                (str(SCHEMA_VERSION),),
            )
    conn.commit()
    return SCHEMA_VERSION
