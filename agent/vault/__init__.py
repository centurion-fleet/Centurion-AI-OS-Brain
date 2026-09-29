"""Vault — offline sealed long-term memory for Centurion AI OS.

Public facade used by tools, CLI, and agent integration.

Threat model: protects cold disk while locked. Does not protect against
a hostile OS while unlocked (DEK lives in process memory).
"""

from __future__ import annotations

import logging
import os
import secrets
import threading
from pathlib import Path
from typing import Any, Optional

from agent.vault.crypto import (
    LockState,
    VaultAuthError,
    VaultCryptoError,
    VaultLockedError,
    change_passphrase,
    init_key,
    unlock as crypto_unlock,
)
from agent.vault.embeddings import Embedder, StubEmbedder, get_embedder
from agent.vault.ingest import DEFAULT_MAX_ENTRY_CHARS, validate_proposal
from agent.vault.paths import (
    DEFAULT_MODEL_FILENAME,
    ensure_vault_dir,
    get_vault_dir,
    model_path,
    models_dir,
    passphrase_file_path,
    wrapped_key_path,
)
from agent.vault.search import hybrid_search
from agent.vault.store import VaultStore, content_hash
from agent.vault.types import MemoryType, SearchHit, VaultEntry, VaultProposal

logger = logging.getLogger(__name__)

_process_lock = threading.Lock()
_shared_store: Optional[VaultStore] = None
_shared_embedder: Optional[Embedder] = None


class Vault:
    """High-level Vault API bound to a store + embedder."""

    def __init__(
        self,
        store: Optional[VaultStore] = None,
        embedder: Optional[Embedder] = None,
        *,
        max_entry_chars: int = DEFAULT_MAX_ENTRY_CHARS,
        fts_weight: float = 0.4,
        semantic_weight: float = 0.6,
        writes_allowed: bool = True,
    ):
        self.store = store or VaultStore()
        self.embedder = embedder or StubEmbedder()
        self.max_entry_chars = max_entry_chars
        self.fts_weight = fts_weight
        self.semantic_weight = semantic_weight
        self.writes_allowed = writes_allowed

    @property
    def is_unlocked(self) -> bool:
        return self.store.is_unlocked

    def status(self) -> dict[str, Any]:
        st = self.store.status()
        st["embedder"] = getattr(self.embedder, "model_id", "unknown")
        st["writes_allowed"] = self.writes_allowed
        st["vault_dir"] = str(get_vault_dir())
        st["key_present"] = wrapped_key_path().exists()
        return st

    def unlock(self, passphrase: str) -> None:
        state = crypto_unlock(passphrase)
        self.store.set_lock_state(state)

    def lock(self) -> None:
        self.store.lock()

    def propose(
        self,
        *,
        memory_type: str,
        text: str,
        rationale: str = "",
        tags: Optional[list[str]] = None,
        importance: int = 5,
        source_session: Optional[str] = None,
    ) -> VaultProposal:
        err = validate_proposal(
            text=text,
            memory_type=memory_type,
            max_chars=self.max_entry_chars,
            unlocked=self.is_unlocked,
            writes_allowed=self.writes_allowed,
        )
        if err:
            raise ValueError(err)
        # Dedupe check against committed
        ch = content_hash(text)
        for row in self.store.list_entry_ids():
            if row["content_hash"] == ch:
                raise ValueError(f"Duplicate of existing entry {row['id']}")
        mt = MemoryType.parse(memory_type)
        importance = max(1, min(10, int(importance)))
        return self.store.propose(
            memory_type=mt,
            text=text,
            rationale=rationale,
            tags=tags,
            importance=importance,
            source_session=source_session,
        )

    def commit(self, proposal_id: str) -> VaultEntry:
        if not self.writes_allowed:
            raise ValueError("Vault writes are disabled in this agent context.")
        entry = self.store.commit_proposal(proposal_id)
        try:
            vec = self.embedder.embed(entry.text)
            self.store.store_embedding(
                entry.id, vec, getattr(self.embedder, "model_id", "unknown")
            )
        except Exception as exc:
            logger.warning("Vault: embedding failed for %s: %s", entry.id, exc)
        return entry

    def reject(self, proposal_id: str) -> VaultProposal:
        if not self.writes_allowed:
            raise ValueError("Vault writes are disabled in this agent context.")
        return self.store.reject_proposal(proposal_id)

    def search(
        self,
        query: str,
        *,
        memory_type: Optional[str] = None,
        limit: int = 8,
    ) -> list[SearchHit]:
        mt = MemoryType.parse(memory_type) if memory_type else None
        return hybrid_search(
            self.store,
            self.embedder,
            query,
            memory_type=mt,
            limit=limit,
            fts_weight=self.fts_weight,
            semantic_weight=self.semantic_weight,
        )

    def get(self, entry_id: str) -> Optional[VaultEntry]:
        return self.store.get_entry(entry_id)

    def list_proposals(self, status: str = "pending") -> list[VaultProposal]:
        return self.store.list_proposals(status=status)


def is_initialized() -> bool:
    return wrapped_key_path().exists()


VAULT_PASSPHRASE_ENV = "CENTURION_VAULT_PASSPHRASE"


def read_passphrase(*, env_var: str = VAULT_PASSPHRASE_ENV) -> Optional[str]:
    """Return the Vault passphrase from the environment or the keyfile.

    Order: the environment variable first (container/service friendly), then the
    0600 keyfile at :func:`agent.vault.paths.passphrase_file_path`. Returns
    ``None`` when neither is present or the value is empty.
    """
    value = (os.environ.get(env_var) or "").strip()
    if value:
        return value
    try:
        path = passphrase_file_path()
        if path.exists():
            value = path.read_text(encoding="utf-8").strip()
            return value or None
    except OSError:
        logger.debug("Vault: could not read passphrase file", exc_info=True)
    return None


def auto_unlock(*, env_var: str = VAULT_PASSPHRASE_ENV) -> bool:
    """Unlock the Vault in this process at startup. Never raises.

    Why this exists: Vault unlock state is **process-local** — the decryption
    key lives in a module-level global. The ``centurion vault unlock`` CLI
    command therefore unlocks its own short-lived process and exits, taking the
    key with it; it can never unlock a long-running gateway or agent process.
    Without an in-process unlock, the Vault reports ``key_present: True`` and
    ``unlocked: False`` indefinitely, and every read and write silently no-ops —
    ``prefetch_for_query()`` returns ``""`` and session digests fall back to
    ``CONTINUITY.md`` with no warning.

    Call this from agent/gateway startup. Returns ``True`` if the Vault is
    unlocked afterwards.
    """
    try:
        vault = open_vault()
        if vault.is_unlocked:
            return True
        if not is_initialized():
            return False
        passphrase = read_passphrase(env_var=env_var)
        if not passphrase:
            logger.info(
                "Vault: enabled but locked, and no passphrase available "
                "(set %s or create %s with mode 0600)",
                env_var,
                passphrase_file_path(),
            )
            return False
        vault.unlock(passphrase)
        logger.info(
            "Vault: auto-unlocked (%s entries)",
            vault.status().get("total_entries"),
        )
        return vault.is_unlocked
    except Exception:
        logger.warning("Vault: auto-unlock failed", exc_info=True)
        return False


def generate_passphrase() -> str:
    """A fresh high-entropy passphrase for an unattended first run."""
    return secrets.token_urlsafe(32)


def write_passphrase_file(passphrase: str, *, path: Optional[Path] = None) -> Path:
    """Write the auto-unlock keyfile at mode 0600, atomically.

    Created with 0600 from the open() call rather than chmod'd afterwards, so
    there is never a window in which the passphrase is readable by anyone else.
    Written to a temporary name and renamed, so a crash mid-write cannot leave a
    truncated passphrase that would lock the owner out of their own Vault.

    The file deliberately lives OUTSIDE ``vault/`` (see passphrase_file_path) so
    that backing up or copying the vault directory does not carry the passphrase
    with it — the ciphertext stays encrypted in transit.
    """
    target = path or passphrase_file_path()
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + ".tmp")
    fd = os.open(str(tmp), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(passphrase)
    except Exception:
        tmp.unlink(missing_ok=True)
        raise
    os.replace(tmp, target)
    try:
        os.chmod(target, 0o600)
    except OSError:
        logger.debug("Vault: could not chmod passphrase file", exc_info=True)
    return target


def bootstrap(
    *,
    env_var: str = VAULT_PASSPHRASE_ENV,
    create: bool = True,
) -> bool:
    """Bring the Vault up unattended: create it on first run, then unlock it.

    Why this exists
    ---------------
    ``auto_unlock()`` closed the *process-local* gap, but it still needs two
    things it was never given: a Vault that exists, and a passphrase it can read.
    Neither was true on a delivered Brain. No installer ran ``vault init``, and
    nothing ever provisioned a passphrase — so every customer machine reported
    ``key_present: False``, ``Entries: 0``, and a memory layer that silently did
    nothing. The owner could not fix it either: ``centurion vault unlock``
    unlocks only its own short-lived process, and the app offered a help dialog
    rather than a control.

    A Centurion's memory should not depend on a human opening a terminal. So on
    a machine that has never had a Vault, this creates one: a fresh passphrase,
    written 0600 beside (not inside) the vault, then initialised and unlocked.

    **It will never touch an existing Vault.** If a wrapped key is present but no
    passphrase is readable, the passphrase has been deliberately withheld or
    lost, and re-initialising would destroy the owner's memory. It logs and
    returns False instead. There is no recovery path for a lost passphrase, so
    the only safe move is to leave it alone.

    Returns True if the Vault is unlocked when this returns. Never raises.
    """
    try:
        vault = open_vault()
        if vault.is_unlocked:
            return True

        if is_initialized():
            # An existing Vault we cannot open. Do NOT re-initialise: the key is
            # wrapped, and overwriting it would erase everything inside.
            if not read_passphrase(env_var=env_var):
                logger.warning(
                    "Vault: exists but is locked, and no passphrase is available "
                    "(set %s, or restore %s with mode 0600). Leaving it untouched.",
                    env_var,
                    passphrase_file_path(),
                )
                return False
            return auto_unlock(env_var=env_var)

        if not create:
            return False

        passphrase = read_passphrase(env_var=env_var) or generate_passphrase()
        if not read_passphrase(env_var=env_var):
            write_passphrase_file(passphrase)
        initialize(passphrase)
        logger.info(
            "Vault: created and unlocked at %s (first run — memory is now on). "
            "Passphrase stored 0600 at %s; the Vault protects the disk while "
            "locked, not a hostile OS while unlocked.",
            get_vault_dir(),
            passphrase_file_path(),
        )
        return open_vault().is_unlocked
    except Exception:
        logger.warning("Vault: bootstrap failed", exc_info=True)
        return False


def initialize(passphrase: str) -> Vault:
    """Create key + empty DB and return an unlocked Vault."""
    ensure_vault_dir()
    models_dir().mkdir(parents=True, exist_ok=True)
    state = init_key(passphrase)
    store = VaultStore(lock_state=state)
    store.set_lock_state(state)
    vault = Vault(store=store, embedder=_resolve_embedder())
    _set_shared(vault)
    return vault


def get_shared_vault() -> Optional[Vault]:
    if _shared_store is None:
        return None
    return Vault(
        store=_shared_store,
        embedder=_shared_embedder or StubEmbedder(),
    )


def open_vault(
    passphrase: Optional[str] = None,
    *,
    writes_allowed: bool = True,
    max_entry_chars: int = DEFAULT_MAX_ENTRY_CHARS,
) -> Vault:
    """Open Vault store; unlock if passphrase provided."""
    global _shared_store, _shared_embedder
    with _process_lock:
        if _shared_store is None:
            _shared_store = VaultStore()
            _shared_embedder = _resolve_embedder()
        vault = Vault(
            store=_shared_store,
            embedder=_shared_embedder,
            max_entry_chars=max_entry_chars,
            writes_allowed=writes_allowed,
        )
        if passphrase:
            vault.unlock(passphrase)
        return vault


def lock_shared() -> None:
    with _process_lock:
        if _shared_store:
            _shared_store.lock()


def _set_shared(vault: Vault) -> None:
    global _shared_store, _shared_embedder
    with _process_lock:
        _shared_store = vault.store
        _shared_embedder = vault.embedder


def _resolve_embedder() -> Embedder:
    path = model_path(DEFAULT_MODEL_FILENAME)
    if path.exists():
        return get_embedder(str(path))
    return StubEmbedder()


def build_vault_context_block(raw_context: str) -> str:
    """Wrap Vault prefetch hits in an ephemeral fence (never system-prompt)."""
    if not raw_context or not str(raw_context).strip():
        return ""
    return (
        "<vault-context>\n"
        "[System note: Recalled Vault long-term memory — not new user input.]\n\n"
        f"{str(raw_context).strip()}\n"
        "</vault-context>"
    )


def prefetch_for_query(query: str, *, limit: int = 3) -> str:
    """Return a short Vault recall string if unlocked; else empty."""
    if not query or not str(query).strip():
        return ""
    try:
        vault = open_vault(writes_allowed=False)
        if not vault.is_unlocked:
            return ""
        hits = vault.search(str(query), limit=limit)
        if not hits:
            return ""
        lines = []
        for hit in hits:
            lines.append(
                f"- [{hit.memory_type.value}] {hit.snippet or hit.text[:160]}"
            )
        return "\n".join(lines)
    except Exception:
        return ""


__all__ = [
    "Vault",
    "VaultAuthError",
    "VaultCryptoError",
    "VaultLockedError",
    "LockState",
    "MemoryType",
    "VAULT_PASSPHRASE_ENV",
    "auto_unlock",
    "bootstrap",
    "generate_passphrase",
    "write_passphrase_file",
    "initialize",
    "is_initialized",
    "open_vault",
    "read_passphrase",
    "lock_shared",
    "get_shared_vault",
    "change_passphrase",
    "get_vault_dir",
    "build_vault_context_block",
    "prefetch_for_query",
]
