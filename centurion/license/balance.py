"""Rent-to-own balance tracking — server is source of truth; local mirror for UI."""

from __future__ import annotations

import logging
from typing import Optional, Tuple

from centurion.license.audit import append_audit
from centurion.license.states import LicenseState
from centurion.license.store import (
    DEFAULT_RTO_TARGET_GBP,
    Entitlement,
    save_entitlement,
)
from centurion.license.tokens import verify_attestation

logger = logging.getLogger(__name__)


def remaining_gbp(entitlement: Entitlement) -> float:
    target = float(entitlement.balance_target_gbp or DEFAULT_RTO_TARGET_GBP)
    paid = float(entitlement.balance_paid_gbp or 0.0)
    return max(0.0, target - paid)


def progress_ratio(entitlement: Entitlement) -> float:
    target = float(entitlement.balance_target_gbp or DEFAULT_RTO_TARGET_GBP)
    if target <= 0:
        return 1.0
    paid = float(entitlement.balance_paid_gbp or 0.0)
    return min(1.0, max(0.0, paid / target))


def is_paid_off(entitlement: Entitlement) -> bool:
    return remaining_gbp(entitlement) <= 0.0 or entitlement.license_state() in {
        LicenseState.RENT_TO_OWN_PAID_OFF,
        LicenseState.OUTRIGHT_OWNED,
    }


def apply_server_balance(
    entitlement: Entitlement,
    *,
    balance_paid_gbp: float,
    balance_target_gbp: Optional[float] = None,
) -> Entitlement:
    """Update local mirror from phone-home response (does not unlock by itself)."""
    entitlement.balance_paid_gbp = float(balance_paid_gbp)
    if balance_target_gbp is not None:
        entitlement.balance_target_gbp = float(balance_target_gbp)
    append_audit(
        "balance_updated",
        license_id=entitlement.license_id,
        balance_paid_gbp=entitlement.balance_paid_gbp,
        balance_target_gbp=entitlement.balance_target_gbp,
    )
    save_entitlement(entitlement)
    return entitlement


def apply_paid_off_attestation(
    entitlement: Entitlement,
    attestation_token: str,
    *,
    public_key: Optional[bytes] = None,
    config: Optional[dict] = None,
) -> Entitlement:
    """Unlock rent-to-own only when a valid paid_off attestation is presented."""
    from centurion.license.fingerprint import compute_fingerprint

    fp = entitlement.machine_fingerprint or compute_fingerprint()
    attested = verify_attestation(
        attestation_token,
        public_key=public_key,
        expected_fingerprint=fp,
        config=config,
    )
    if attested.kind not in {"paid_off", "outright"} and attested.state not in {
        LicenseState.RENT_TO_OWN_PAID_OFF.value,
        LicenseState.OUTRIGHT_OWNED.value,
    }:
        raise ValueError(f"Attestation kind {attested.kind!r} cannot unlock ownership")

    if attested.balance_paid_gbp is not None:
        entitlement.balance_paid_gbp = float(attested.balance_paid_gbp)
    if attested.balance_target_gbp is not None:
        entitlement.balance_target_gbp = float(attested.balance_target_gbp)

    # Require balance >= target OR explicit paid_off/outright state in attestation.
    if attested.state == LicenseState.OUTRIGHT_OWNED.value or attested.kind == "outright":
        new_state = LicenseState.OUTRIGHT_OWNED
    else:
        if not is_paid_off(entitlement) and attested.state != LicenseState.RENT_TO_OWN_PAID_OFF.value:
            # Attestation may set paid equal to target.
            target = float(entitlement.balance_target_gbp or DEFAULT_RTO_TARGET_GBP)
            entitlement.balance_paid_gbp = max(float(entitlement.balance_paid_gbp or 0.0), target)
        new_state = LicenseState.RENT_TO_OWN_PAID_OFF

    entitlement.signed_attestation = attestation_token
    entitlement.state = new_state.value
    entitlement.grace_started_at = None
    entitlement.revoke_reason = None
    if attested.license_id:
        entitlement.license_id = attested.license_id
    append_audit(
        "paid_off_applied",
        license_id=entitlement.license_id,
        state=entitlement.state,
        kind=attested.kind,
    )
    save_entitlement(entitlement)
    return entitlement


def summarize_balance(entitlement: Entitlement) -> Tuple[float, float, float]:
    """Return (paid, target, remaining)."""
    paid = float(entitlement.balance_paid_gbp or 0.0)
    target = float(entitlement.balance_target_gbp or DEFAULT_RTO_TARGET_GBP)
    return paid, target, max(0.0, target - paid)
