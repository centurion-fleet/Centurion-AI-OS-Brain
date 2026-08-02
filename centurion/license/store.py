"""Encrypted local entitlement store under CENTURION_HOME/license/."""

from __future__ import annotations

import json
import logging
import os
import secrets
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, Optional

from centurion.license.audit import append_audit
from centurion.license.states import (
    LicenseState,
    InvalidTransition,
    parse_state,
    transition,
)

logger = logging.getLogger(__name__)

ENTITLEMENT_FILENAME = "entitlement.json.enc"
DEVICE_KEY_FILENAME = "device.key"
STORE_VERSION = 1
DEFAULT_RTO_TARGET_GBP = 5000.0
NONCE_BYTES = 12
KEY_BYTES = 32


@dataclass
class Entitlement:
    """Local mirror of license entitlement. Server attestations are authoritative."""

    state: str = LicenseState.UNACTIVATED.value
    tier: Optional[str] = None
    license_id: Optional[str] = None
    machine_fingerprint: Optional[str] = None
    last_verified_at: Optional[float] = None
    grace_started_at: Optional[float] = None
    balance_paid_gbp: float = 0.0
    balance_target_gbp: float = DEFAULT_RTO_TARGET_GBP
    signed_attestation: Optional[str] = None
    token_id: Optional[str] = None
    next_check_by: Optional[float] = None
    customer_name: Optional[str] = None
    shipment_id: Optional[str] = None
    trial_expires_at: Optional[float] = None
    revoke_reason: Optional[str] = None
    updated_at: float = field(default_factory=time.time)
    version: int = STORE_VERSION

    def license_state(self) -> LicenseState:
        return parse_state(self.state)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Entitlement":
        known = {f.name for f in cls.__dataclass_fields__.values()}  # type: ignore[attr-defined]
        filtered = {k: v for k, v in data.items() if k in known}
        if "state" in filtered:
            filtered["state"] = parse_state(filtered["state"]).value
        return cls(**filtered)


def license_dir() -> Path:
    from centurion_constants import get_centurion_home

    path = get_centurion_home() / "license"
    path.mkdir(parents=True, exist_ok=True)
    return path


def entitlement_path() -> Path:
    return license_dir() / ENTITLEMENT_FILENAME


def device_key_path() -> Path:
    return license_dir() / DEVICE_KEY_FILENAME


def _secure_chmod(path: Path) -> None:
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


def _ensure_device_key() -> bytes:
    path = device_key_path()
    if path.exists():
        raw = path.read_bytes()
        if len(raw) >= KEY_BYTES:
            return raw[:KEY_BYTES]
    key = secrets.token_bytes(KEY_BYTES)
    path.write_bytes(key)
    _secure_chmod(path)
    return key


def _derive_aes_key(device_key: bytes, fingerprint: str) -> bytes:
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF

    hkdf = HKDF(
        algorithm=hashes.SHA256(),
        length=KEY_BYTES,
        salt=b"centurion-license-v1",
        info=fingerprint.encode("utf-8") or b"unknown",
    )
    return hkdf.derive(device_key)


def _encrypt_blob(plaintext: bytes, aes_key: bytes) -> bytes:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    nonce = secrets.token_bytes(NONCE_BYTES)
    aesgcm = AESGCM(aes_key)
    ct = aesgcm.encrypt(nonce, plaintext, b"centurion-entitlement-v1")
    return nonce + ct


def _decrypt_blob(blob: bytes, aes_key: bytes) -> bytes:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    if len(blob) < NONCE_BYTES + 16:
        raise ValueError("Entitlement blob too short")
    nonce, ct = blob[:NONCE_BYTES], blob[NONCE_BYTES:]
    aesgcm = AESGCM(aes_key)
    return aesgcm.decrypt(nonce, ct, b"centurion-entitlement-v1")


def _fingerprint_for_key() -> str:
    try:
        from centurion.license.fingerprint import compute_fingerprint

        return compute_fingerprint(include_remote=False)
    except Exception:
        return "unknown"


def load_entitlement() -> Entitlement:
    """Load entitlement or return a fresh unactivated one."""
    path = entitlement_path()
    if not path.exists():
        return Entitlement()
    try:
        device_key = _ensure_device_key()
        aes_key = _derive_aes_key(device_key, _fingerprint_for_key())
        plaintext = _decrypt_blob(path.read_bytes(), aes_key)
        data = json.loads(plaintext.decode("utf-8"))
        if not isinstance(data, dict):
            raise ValueError("Entitlement JSON is not an object")
        return Entitlement.from_dict(data)
    except Exception as exc:
        logger.warning("Failed to load license entitlement (%s); treating as unactivated", exc)
        append_audit("entitlement_load_failed", error=str(exc))
        return Entitlement()


def save_entitlement(entitlement: Entitlement) -> None:
    """Atomically write encrypted entitlement."""
    from utils import atomic_replace

    entitlement.updated_at = time.time()
    device_key = _ensure_device_key()
    aes_key = _derive_aes_key(device_key, _fingerprint_for_key())
    plaintext = json.dumps(entitlement.to_dict(), ensure_ascii=False, sort_keys=True).encode(
        "utf-8"
    )
    blob = _encrypt_blob(plaintext, aes_key)
    path = entitlement_path()
    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(blob)
    atomic_replace(tmp, path)
    _secure_chmod(path)


def apply_state(
    entitlement: Entitlement,
    new_state: LicenseState | str,
    *,
    reason: Optional[str] = None,
) -> Entitlement:
    """Transition state if allowed and persist."""
    current = entitlement.license_state()
    target = parse_state(new_state)
    try:
        transition(current, target)
    except InvalidTransition:
        append_audit(
            "invalid_transition",
            from_state=current.value,
            to_state=target.value,
            reason=reason,
        )
        raise
    if current != target:
        entitlement.state = target.value
        append_audit(
            "state_transition",
            from_state=current.value,
            to_state=target.value,
            reason=reason,
            license_id=entitlement.license_id,
        )
        save_entitlement(entitlement)
    return entitlement


def seed_entitlement(data: Dict[str, Any]) -> Entitlement:
    """Factory / DIF Y seed: write a pre-configured entitlement blob."""
    ent = Entitlement.from_dict(data)
    if not ent.machine_fingerprint:
        from centurion.license.fingerprint import compute_fingerprint

        ent.machine_fingerprint = compute_fingerprint()
    save_entitlement(ent)
    append_audit(
        "entitlement_seeded",
        state=ent.state,
        tier=ent.tier,
        license_id=ent.license_id,
        shipment_id=ent.shipment_id,
    )
    return ent
