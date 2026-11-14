"""Centurion product licensing — commercial entitlements.

Monthly subscription only. The rent-to-own / outright / owned vocabulary was retired
on 29 Sep 2026; a subscription can lapse and a Brain can be locked, but no licence
state erases a Centurion. Payment and Stripe live on personalcenturion.com; this
package is the OS client.
"""

from __future__ import annotations

from centurion.license.activate import (
    ActivateResult,
    activate_from_server,
    activate_trial,
    redeem_purchase_token,
    request_reissue,
)
from centurion.license.edition import (
    Edition,
    current_edition,
    edition_label,
    rebind_refusal,
    resolve_edition,
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
    "Edition",
    "EnforcementDecision",
    "EnforcementMode",
    "Entitlement",
    "LicenseState",
    "LicenseTier",
    "activate_from_server",
    "activate_trial",
    "can_transition",
    "collect_identity_parts",
    "compute_fingerprint",
    "current_edition",
    "edition_label",
    "enforcement_enabled",
    "evaluate",
    "fingerprint_short",
    "gate_agent_turn",
    "is_permanently_owned",
    "is_phone_home_due",
    "load_entitlement",
    "locked_user_message",
    "maybe_phone_home_on_startup",
    "phone_home",
    "redeem_purchase_token",
    "rebind_refusal",
    "request_reissue",
    "resolve_edition",
    "requires_phone_home",
    "save_entitlement",
    "seed_entitlement",
    "transition",
]
