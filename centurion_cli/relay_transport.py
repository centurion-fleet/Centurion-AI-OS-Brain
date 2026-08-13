"""RelayTransport — Supabase Realtime away path for Crypto Chat.

LAN TCP (:9119) stays untouched. This module owns the Realtime *envelope*:
chunking, id correlation, and reconnect=re-KX semantics. It does not decrypt
chat content — body bytes are opaque (secretbox after KX, or raw KX bytes).

See brain/linux/docs/REMOTE_RELAY.md for product architecture.
"""

from __future__ import annotations

import base64
import math
import uuid
from dataclasses import dataclass, field
from typing import Any, Iterable, Iterator, Literal

# Supabase Realtime practical payload budget (JSON event). Stay under this
# for body_b64 + envelope overhead.
DEFAULT_CHUNK_BYTES = 180_000
# Soft policy max for reassembled ciphertext on the away path (v1).
DEFAULT_MAX_REASSEMBLED = 1_048_576

EnvelopeKind = Literal["kx_client", "kx_server", "frame", "frame_chunk"]


@dataclass(frozen=True)
class RelayEnvelope:
    """One Realtime event on the Brain↔phone channel."""

    v: int
    conn: str
    id: str
    kind: EnvelopeKind
    chunk_i: int
    chunk_n: int
    body_b64: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "v": self.v,
            "conn": self.conn,
            "id": self.id,
            "kind": self.kind,
            "chunk_i": self.chunk_i,
            "chunk_n": self.chunk_n,
            "body_b64": self.body_b64,
        }

    @classmethod
    def from_dict(cls, raw: dict[str, Any]) -> "RelayEnvelope":
        kind = str(raw.get("kind") or "")
        if kind not in ("kx_client", "kx_server", "frame", "frame_chunk"):
            raise ValueError(f"invalid relay kind: {kind!r}")
        return cls(
            v=int(raw.get("v") or 1),
            conn=str(raw.get("conn") or ""),
            id=str(raw.get("id") or ""),
            kind=kind,  # type: ignore[arg-type]
            chunk_i=int(raw.get("chunk_i") or 0),
            chunk_n=int(raw.get("chunk_n") or 1),
            body_b64=str(raw.get("body_b64") or ""),
        )


def new_conn_id() -> str:
    """Mint a connection epoch. Call on every Realtime (re)connect — forces re-KX."""
    return uuid.uuid4().hex


def new_message_id() -> str:
    return str(uuid.uuid4())


def encode_body(raw: bytes) -> str:
    return base64.b64encode(raw).decode("ascii")


def decode_body(body_b64: str) -> bytes:
    return base64.b64decode(body_b64.encode("ascii"), validate=True)


def split_chunks(raw: bytes, chunk_bytes: int = DEFAULT_CHUNK_BYTES) -> list[bytes]:
    if chunk_bytes < 1:
        raise ValueError("chunk_bytes must be >= 1")
    if not raw:
        return [b""]
    n = max(1, math.ceil(len(raw) / chunk_bytes))
    return [raw[i * chunk_bytes : (i + 1) * chunk_bytes] for i in range(n)]


def build_envelopes(
    *,
    conn: str,
    msg_id: str,
    kind: EnvelopeKind,
    body: bytes,
    chunk_bytes: int = DEFAULT_CHUNK_BYTES,
    max_reassembled: int = DEFAULT_MAX_REASSEMBLED,
) -> list[RelayEnvelope]:
    """Frame opaque bytes into one or more Realtime envelopes."""
    if len(body) > max_reassembled:
        raise ValueError(
            f"payload {len(body)} bytes exceeds away-path max {max_reassembled}"
        )
    chunks = split_chunks(body, chunk_bytes=chunk_bytes)
    n = len(chunks)
    out_kind: EnvelopeKind = kind if n == 1 and kind != "frame_chunk" else (
        "frame_chunk" if kind in ("frame", "frame_chunk") else kind
    )
    # KX is expected small; if somehow chunked, keep the kx_* kind on each part.
    if kind in ("kx_client", "kx_server"):
        out_kind = kind
    envelopes: list[RelayEnvelope] = []
    for i, chunk in enumerate(chunks):
        envelopes.append(
            RelayEnvelope(
                v=1,
                conn=conn,
                id=msg_id,
                kind=out_kind if n == 1 else (
                    "frame_chunk" if kind in ("frame", "frame_chunk") else kind
                ),
                chunk_i=i,
                chunk_n=n,
                body_b64=encode_body(chunk),
            )
        )
    return envelopes


@dataclass
class ChunkAssembler:
    """Reassemble frame_chunk envelopes by id before decrypt."""

    max_reassembled: int = DEFAULT_MAX_REASSEMBLED
    _parts: dict[str, dict[int, bytes]] = field(default_factory=dict)
    _meta: dict[str, tuple[str, int, EnvelopeKind]] = field(default_factory=dict)

    def push(self, env: RelayEnvelope) -> bytes | None:
        """Accept one envelope. Returns full body when complete, else None."""
        if not env.id or not env.conn:
            raise ValueError("relay envelope missing id or conn")
        if env.chunk_n < 1 or env.chunk_i < 0 or env.chunk_i >= env.chunk_n:
            raise ValueError("invalid chunk indices")
        body = decode_body(env.body_b64)
        if env.chunk_n == 1:
            if len(body) > self.max_reassembled:
                raise ValueError("reassembled payload exceeds policy max")
            return body
        key = env.id
        meta = self._meta.get(key)
        if meta is None:
            self._meta[key] = (env.conn, env.chunk_n, env.kind)
            self._parts[key] = {}
        else:
            conn0, n0, kind0 = meta
            if conn0 != env.conn or n0 != env.chunk_n or kind0 != env.kind:
                raise ValueError("chunk metadata mismatch for id")
        parts = self._parts[key]
        if env.chunk_i in parts:
            raise ValueError("duplicate chunk index")
        parts[env.chunk_i] = body
        if len(parts) < env.chunk_n:
            return None
        ordered = b"".join(parts[i] for i in range(env.chunk_n))
        del self._parts[key]
        del self._meta[key]
        if len(ordered) > self.max_reassembled:
            raise ValueError("reassembled payload exceeds policy max")
        return ordered

    def clear_conn(self, conn: str) -> None:
        """Drop in-flight chunks for a dead connection epoch."""
        drop = [mid for mid, (c, _, _) in self._meta.items() if c == conn]
        for mid in drop:
            self._parts.pop(mid, None)
            self._meta.pop(mid, None)


@dataclass
class PendingById:
    """Client-side demux: wait for response envelopes matching request id."""

    _waiting: dict[str, list[RelayEnvelope]] = field(default_factory=dict)

    def expect(self, msg_id: str) -> None:
        self._waiting.setdefault(msg_id, [])

    def ingest(self, env: RelayEnvelope) -> list[RelayEnvelope] | None:
        """Return the buffered list when this id was expected; else None (push/unsolicited)."""
        if env.id not in self._waiting:
            return None
        buf = self._waiting[env.id]
        buf.append(env)
        return buf

    def take(self, msg_id: str) -> list[RelayEnvelope]:
        return self._waiting.pop(msg_id, [])

    def clear(self) -> None:
        self._waiting.clear()


def iter_request_envelopes(
    envelopes: Iterable[RelayEnvelope],
) -> Iterator[RelayEnvelope]:
    yield from envelopes


@dataclass
class RelaySession:
    """In-process RelayTransport session state (LAN TCP path never uses this).

    Realtime reconnect ⇒ call ``reset_connection()`` which mints a new ``conn``
    and clears demux/assembler state — callers MUST re-run KX before frames.
    """

    chunk_bytes: int = DEFAULT_CHUNK_BYTES
    max_reassembled: int = DEFAULT_MAX_REASSEMBLED
    conn: str = field(default_factory=new_conn_id)
    assembler: ChunkAssembler = field(default_factory=ChunkAssembler)
    pending: PendingById = field(default_factory=PendingById)
    session_keys_valid: bool = False

    def __post_init__(self) -> None:
        self.assembler = ChunkAssembler(max_reassembled=self.max_reassembled)

    def reset_connection(self) -> str:
        """New Realtime socket / epoch. Invalidates session keys (full re-KX)."""
        old = self.conn
        self.assembler.clear_conn(old)
        self.pending.clear()
        self.conn = new_conn_id()
        self.session_keys_valid = False
        return self.conn

    def mark_kx_complete(self) -> None:
        self.session_keys_valid = True

    def ensure_ready_for_frames(self) -> None:
        if not self.session_keys_valid:
            raise RuntimeError("relay session requires re-KX after reconnect")

    def outbound_frame(self, body: bytes, *, expect_response: bool = True) -> list[dict[str, Any]]:
        """Build Realtime events for one opaque ciphertext frame."""
        self.ensure_ready_for_frames()
        msg_id = new_message_id()
        if expect_response:
            self.pending.expect(msg_id)
        envs = build_envelopes(
            conn=self.conn,
            msg_id=msg_id,
            kind="frame",
            body=body,
            chunk_bytes=self.chunk_bytes,
            max_reassembled=self.max_reassembled,
        )
        return [e.to_dict() for e in envs]

    def outbound_kx(self, body: bytes, *, client: bool) -> list[dict[str, Any]]:
        """KX bytes before session keys exist (allowed without mark_kx_complete)."""
        msg_id = new_message_id()
        kind: EnvelopeKind = "kx_client" if client else "kx_server"
        envs = build_envelopes(
            conn=self.conn,
            msg_id=msg_id,
            kind=kind,
            body=body,
            chunk_bytes=self.chunk_bytes,
            max_reassembled=self.max_reassembled,
        )
        return [e.to_dict() for e in envs]

    def ingest_event(self, raw: dict[str, Any] | RelayEnvelope) -> tuple[str, bytes | None]:
        """Ingest one Realtime event.

        Returns ``(kind, body_or_none)`` where body is set only when a full
        message is reassembled. Raises if ``conn`` mismatches (stale epoch).
        """
        env = raw if isinstance(raw, RelayEnvelope) else RelayEnvelope.from_dict(raw)
        if env.conn != self.conn:
            raise ValueError("stale relay conn epoch — reconnect and re-KX")
        body = self.assembler.push(env)
        if body is None:
            return env.kind, None
        # Demux bookkeeping for request/response correlation.
        self.pending.ingest(env)
        return env.kind, body

    def fail_inflight_on_reconnect(self) -> list[str]:
        """Ids that must surface as retryable errors after reset_connection."""
        # Call before reset to snapshot waiting ids.
        return list(self.pending._waiting.keys())
