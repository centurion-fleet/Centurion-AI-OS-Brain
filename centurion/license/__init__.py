"""Centurion product licensing — three-tier commercial entitlements.

Tiers: subscription (£50/mo), rent-to-own (£250/mo → £5,000), outright (£4,250).
Payment and Stripe live on personalcenturion.com; this package is the OS client.
"""

from __future__ import annotations

from centurion.license.activate import (
    ActivateResult,
    activate_from_server,
    activate_trial,
    redeem_outright_token,
    request_reissue,
)
from centurion.license.balance import (
    apply_paid_off_attestation,
    apply_server_balance,
    is_paid_off,
    progress_ratio,
    remaining_gbp,
    summarize_balance,
)
from centurion.license.enforcement import (
    EnforcementDecision,
    EnforcementMode,
    enforcement_enabled,
    evaluate,
    gate_agent_turn,
    locked_user_message,
)
from centurion.license.fingerprint import (
    collect_identity_parts,
    compute_fingerprint,
    fingerprint_short,
)
from centurion.license.phone_home import (
    CheckinResult,
    is_phone_home_due,
    maybe_phone_home_on_startup,
    phone_home,
)
from centurion.license.states import (
    LicenseState,
    LicenseTier,
    can_transition,
    is_permanently_owned,
    requires_phone_home,
    transition,
)
from centurion.license.store import (
    Entitlement,
    load_entitlement,
    save_entitlement,
    seed_entitlement,
)

__all__ = [
    "ActivateResult",
    "CheckinResult",
    "EnforcementDecision",
    "EnforcementMode",
    "Entitlement",
    "LicenseState",
    "LicenseTier",
    "activate_from_server",
    "activate_trial",
    "apply_paid_off_attestation",
    "apply_server_balance",
    "can_transition",
    "collect_identity_parts",
    "compute_fingerprint",
    "enforcement_enabled",
    "evaluate",
    "fingerprint_short",
    "gate_agent_turn",
    "is_paid_off",
    "is_permanently_owned",
    "is_phone_home_due",
    "load_entitlement",
    "locked_user_message",
    "maybe_phone_home_on_startup",
    "phone_home",
    "progress_ratio",
    "redeem_outright_token",
    "remaining_gbp",
    "request_reissue",
    "requires_phone_home",
    "save_entitlement",
    "seed_entitlement",
    "summarize_balance",
    "transition",
]
