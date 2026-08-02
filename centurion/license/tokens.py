"""Proof-of-purchase token verification (ed25519) and attestation helpers.

Production attestations are signed by the Centurion license CA on
personalcenturion.com. The OS embeds the public key (or loads it from
config) and verifies signed payloads locally so offline forgery of
``outright_owned`` / ``rent_to_own_paid_off`` is not possible.
"""

from __future__ import annotations

import base64
import hashlib
import json
import logging
import time
from dataclasses import dataclass
from typing import Any, Dict, Optional, Tuple

logger = logging.getLogger(__name__)

# Centurion license CA public key (ed25519). Replace at release with the
# production key; tests inject their own via verify_attestation(public_key=...).
# This placeholder is a valid ed25519 public key encoding of 32 zero bytes —
# only useful for structural tests; production must override.
_PLACEHOLDER_PUBKEY_B64 = base64.b64encode(b"\x00" * 32).decode("ascii")


@dataclass
class AttestationPayload:
    """Decoded attestation fields."""

    kind: str  # "paid_off" | "outright" | "subscription" | "rto_active" | ...
    license_id: str
    machine_fingerprint: str
    state: str
    tier: Optional[str] = None
    balance_paid_gbp: Optional[float] = None
    balance_target_gbp: Optional[float] = None
    issued_at: Optional[float] = None
    expires_at: Optional[float] = None
    token_id: Optional[str] = None
    raw: Optional[Dict[str, Any]] = None


def get_ca_public_key_bytes(config: Optional[Dict[str, Any]] = None) -> bytes:
    """Resolve the ed25519 CA public key from config or built-in placeholder."""
    b64 = _PLACEHOLDER_PUBKEY_B64
    if config is None:
        try:
            from centurion_cli.config import load_config

            config = load_config() or {}
        except Exception:
            config = {}
    license_cfg = config.get("license") if isinstance(config.get("license"), dict) else {}
    override = (license_cfg or {}).get("ca_public_key_b64")
    if isinstance(override, str) and override.strip():
        b64 = override.strip()
    return base64.b64decode(b64)


def _canonical_json(payload: Dict[str, Any]) -> bytes:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode(
        "utf-8"
    )


def sign_attestation(
    payload: Dict[str, Any],
    private_key_bytes: bytes,
) -> str:
    """Sign *payload* and return ``base64(payload_json).base64(signature)``.

    Used by tests and the website; the OS client only verifies.
    """
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

    private_key = Ed25519PrivateKey.from_private_bytes(private_key_bytes)
    body = _canonical_json(payload)
    signature = private_key.sign(body)
    return (
        base64.urlsafe_b64encode(body).decode("ascii").rstrip("=")
        + "."
        + base64.urlsafe_b64encode(signature).decode("ascii").rstrip("=")
    )


def _b64url_decode(data: str) -> bytes:
    pad = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(data + pad)


def parse_attestation(token: str) -> Tuple[Dict[str, Any], bytes]:
    """Split signed attestation into payload dict + raw signature bytes."""
    parts = token.split(".")
    if len(parts) != 2:
        raise ValueError("Attestation must be payload.signature")
    body = _b64url_decode(parts[0])
    signature = _b64url_decode(parts[1])
    payload = json.loads(body.decode("utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("Attestation payload must be an object")
    return payload, signature


def verify_attestation(
    token: str,
    *,
    public_key: Optional[bytes] = None,
    expected_fingerprint: Optional[str] = None,
    config: Optional[Dict[str, Any]] = None,
    now: Optional[float] = None,
) -> AttestationPayload:
    """Verify ed25519 signature and optional fingerprint / expiry checks."""
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    from cryptography.exceptions import InvalidSignature

    payload, signature = parse_attestation(token)
    body = _canonical_json(payload)
    pubkey_bytes = public_key if public_key is not None else get_ca_public_key_bytes(config)
    public = Ed25519PublicKey.from_public_bytes(pubkey_bytes)
    try:
        public.verify(signature, body)
    except InvalidSignature as exc:
        raise ValueError("Invalid attestation signature") from exc

    fp = str(payload.get("machine_fingerprint") or "")
    if expected_fingerprint and fp and fp != expected_fingerprint:
        raise ValueError("Attestation fingerprint mismatch")

    expires_at = payload.get("expires_at")
    if expires_at is not None:
        ts = float(expires_at)
        if (now if now is not None else time.time()) > ts:
            raise ValueError("Attestation expired")

    return AttestationPayload(
        kind=str(payload.get("kind") or ""),
        license_id=str(payload.get("license_id") or ""),
        machine_fingerprint=fp,
        state=str(payload.get("state") or ""),
        tier=payload.get("tier"),
        balance_paid_gbp=_optional_float(payload.get("balance_paid_gbp")),
        balance_target_gbp=_optional_float(payload.get("balance_target_gbp")),
        issued_at=_optional_float(payload.get("issued_at")),
        expires_at=_optional_float(expires_at),
        token_id=payload.get("token_id"),
        raw=payload,
    )


def _optional_float(value: Any) -> Optional[float]:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def proof_of_purchase_digest(token_id: str, secret: str) -> str:
    """SHA-256 hex of token_id:secret — used when presenting PoP without raw secret."""
    return hashlib.sha256(f"{token_id}:{secret}".encode("utf-8")).hexdigest()
