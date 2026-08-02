"""Hermetic fake license server helpers for unit tests."""

from __future__ import annotations

import base64
import json
from typing import Any, Dict, Optional

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from centurion.license.tokens import sign_attestation


def generate_test_ca() -> tuple[bytes, bytes, str]:
    """Return (private_key_bytes, public_key_bytes, public_key_b64)."""
    private = Ed25519PrivateKey.generate()
    private_bytes = private.private_bytes_raw()
    public_bytes = private.public_key().public_bytes_raw()
    return private_bytes, public_bytes, base64.b64encode(public_bytes).decode("ascii")


def make_paid_off_attestation(
    private_key: bytes,
    *,
    license_id: str,
    fingerprint: str,
    balance_paid_gbp: float = 5000.0,
    balance_target_gbp: float = 5000.0,
) -> str:
    payload = {
        "kind": "paid_off",
        "license_id": license_id,
        "machine_fingerprint": fingerprint,
        "state": "rent_to_own_paid_off",
        "tier": "rent_to_own",
        "balance_paid_gbp": balance_paid_gbp,
        "balance_target_gbp": balance_target_gbp,
        "issued_at": 1_700_000_000,
        "expires_at": None,
    }
    return sign_attestation(payload, private_key)


def make_outright_attestation(
    private_key: bytes,
    *,
    license_id: str,
    fingerprint: str,
    token_id: str = "pop_test",
) -> str:
    payload = {
        "kind": "outright",
        "license_id": license_id,
        "machine_fingerprint": fingerprint,
        "state": "outright_owned",
        "tier": "outright",
        "token_id": token_id,
        "issued_at": 1_700_000_000,
        "expires_at": None,
    }
    return sign_attestation(payload, private_key)


def checkin_response(
    *,
    state: str = "subscription_active",
    tier: str = "subscription",
    balance_paid_gbp: Optional[float] = None,
    signed_attestation: Optional[str] = None,
    revoke_reason: Optional[str] = None,
    next_check_by: Optional[float] = None,
) -> Dict[str, Any]:
    return {
        "ok": revoke_reason is None,
        "state": state if revoke_reason is None else "locked",
        "tier": tier,
        "balance_paid_gbp": balance_paid_gbp,
        "balance_target_gbp": 5000.0 if balance_paid_gbp is not None else None,
        "next_check_by": next_check_by or (1_700_000_000 + 30 * 86400),
        "grace_until": None,
        "signed_attestation": signed_attestation,
        "revoke_reason": revoke_reason,
    }


def dumps(data: Dict[str, Any]) -> bytes:
    return json.dumps(data).encode("utf-8")
