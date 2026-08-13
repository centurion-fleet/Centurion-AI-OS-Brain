"""Relay Crypto Chat helpers — PyNaCl KX + secretbox matching centurion-remote.

Used when the Brain handles KX in-process. The preferred Away path splices
opaque frames to localhost:9119 (see ``remote_relay_splice.py``); this module
covers identity load + optional in-process session for tests and fallback.
"""

from __future__ import annotations

import hashlib
import logging
import os
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

KEY_EXCHANGE_TYPE = 0x01
PUBLIC_KEY_BYTES = 32
KEY_EXCHANGE_FRAME_BYTES = 1 + PUBLIC_KEY_BYTES
NONCE_BYTES = 24


class RelayCryptoError(Exception):
    """KX or secretbox failure on the Away path."""


def _centurion_home() -> Path:
    raw = os.environ.get("CENTURION_HOME", "").strip()
    if raw:
        return Path(raw)
    return Path.home() / ".centurion"


def server_identity_path() -> Path:
    return _centurion_home() / "remote" / "server-identity.bin"


def devices_registry_path() -> Path:
    return _centurion_home() / "remote" / "devices.json"


def fingerprint_public_key(public_key: bytes) -> str:
    digest = hashlib.sha256(public_key).digest()
    return digest[:16].hex()


def encode_key_exchange(public_key: bytes) -> bytes:
    if len(public_key) != PUBLIC_KEY_BYTES:
        raise RelayCryptoError("invalid public key length")
    return bytes([KEY_EXCHANGE_TYPE]) + public_key


def decode_key_exchange(frame: bytes) -> bytes:
    if len(frame) != KEY_EXCHANGE_FRAME_BYTES or frame[0] != KEY_EXCHANGE_TYPE:
        raise RelayCryptoError("invalid key exchange frame")
    return bytes(frame[1:])


def load_or_create_server_identity(path: Path | None = None) -> tuple[bytes, bytes]:
    """Return ``(public_key, secret_key)`` matching Rust ``ServerIdentity`` layout."""
    from nacl import bindings

    path = path or server_identity_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file():
        raw = path.read_bytes()
        if len(raw) != PUBLIC_KEY_BYTES * 2:
            raise RelayCryptoError("invalid Centurion server identity")
        return raw[:PUBLIC_KEY_BYTES], raw[PUBLIC_KEY_BYTES:]
    public, secret = bindings.crypto_kx_keypair()
    path.write_bytes(public + secret)
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
    return public, secret


class ServerSession:
    """Server-side receive/transmit secretbox keys after KX."""

    def __init__(self, public: bytes, receive: bytes, transmit: bytes) -> None:
        self.public = public
        self.receive = receive
        self.transmit = transmit

    @classmethod
    def establish(cls, client_public_key: bytes, identity: tuple[bytes, bytes]) -> "ServerSession":
        from nacl import bindings

        server_pk, server_sk = identity
        if len(client_public_key) != PUBLIC_KEY_BYTES:
            raise RelayCryptoError("invalid peer public key")
        receive, transmit = bindings.crypto_kx_server_session_keys(
            server_pk, server_sk, client_public_key
        )
        return cls(public=server_pk, receive=receive, transmit=transmit)

    def decrypt(self, frame: bytes) -> bytes:
        from nacl import bindings

        if len(frame) < NONCE_BYTES + 16:
            raise RelayCryptoError("encrypted frame too short")
        nonce = frame[:NONCE_BYTES]
        ciphertext = frame[NONCE_BYTES:]
        try:
            return bindings.crypto_secretbox_open(ciphertext, nonce, self.receive)
        except Exception as exc:
            raise RelayCryptoError("message authentication failed") from exc

    def encrypt(self, plaintext: bytes) -> bytes:
        from nacl import bindings

        nonce = bindings.randombytes(NONCE_BYTES)
        ciphertext = bindings.crypto_secretbox(plaintext, nonce, self.transmit)
        return nonce + ciphertext


def is_device_approved(fingerprint: str) -> bool:
    """Read Rust ``devices.json`` registry (same file LAN Crypto Chat uses)."""
    import json

    path = devices_registry_path()
    if not path.is_file():
        return False
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return False
    devices = doc.get("devices") if isinstance(doc, dict) else None
    if not isinstance(devices, list):
        return False
    return any(
        isinstance(d, dict) and str(d.get("fingerprint") or "") == fingerprint
        for d in devices
    )


def note_pending_device(fingerprint: str, name: str = "iPhone (Away)") -> None:
    import json
    import time

    path = devices_registry_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    doc: dict[str, Any] = {"devices": [], "pending": []}
    if path.is_file():
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                doc = loaded
        except Exception:
            pass
    pending = list(doc.get("pending") or [])
    now = int(time.time())
    found = False
    for row in pending:
        if isinstance(row, dict) and row.get("fingerprint") == fingerprint:
            row["name"] = name
            row["last_seen_at"] = now
            found = True
            break
    if not found:
        pending.append(
            {"fingerprint": fingerprint, "name": name, "last_seen_at": now}
        )
    doc["pending"] = pending
    if "devices" not in doc:
        doc["devices"] = []
    path.write_text(json.dumps(doc, indent=2), encoding="utf-8")
