"""License entitlement state machine.

States and legal transitions for Centurion product licensing. Server attestations drive
most transitions; local code only applies transitions that appear in ALLOWED_TRANSITIONS.

The owned / rent-to-own vocabulary was **retired on 29 Sep 2026**, by decision: every
Centurion pays a monthly subscription, so there is no permanent state and no machine is
ever marked as owned. See the fleet rule this preserves — *the fee governs the service,
never the being*: a subscription can lapse, but no state here erases a Centurion.

Removed deliberately rather than left dormant, so that:

  * no code path can grant a permanence the business model no longer sells, and
  * a stale ``outright_owned`` in a saved entitlement cannot be mistaken for a live state
    (it now parses as unknown, and an unknown state is treated as unactivated).
"""

from __future__ import annotations

from enum import Enum
from typing import FrozenSet, Mapping


class LicenseState(str, Enum):
    UNACTIVATED = "unactivated"
    TRIAL = "trial"
    SUBSCRIPTION_ACTIVE = "subscription_active"
    SUBSCRIPTION_EXPIRED = "subscription_expired"
    GRACE = "grace"
    LOCKED = "locked"


class LicenseTier(str, Enum):
    TRIAL = "trial"
    SUBSCRIPTION = "subscription"


# Website API → local enum aliases (sales-site LICENSE_API_CONTRACT).
_STATE_ALIASES = {
    "expired": LicenseState.SUBSCRIPTION_EXPIRED,
    "grace": LicenseState.GRACE,
    "pending": LicenseState.UNACTIVATED,
}

# Nothing is permanent any more: every state is subject to periodic phone-home. The set
# is kept (empty) so callers that ask the question keep working and keep answering False.
PERMANENT_OWNED: FrozenSet[LicenseState] = frozenset()

# States that require periodic phone-home while active.
PHONE_HOME_REQUIRED: FrozenSet[LicenseState] = frozenset(
    {
        LicenseState.TRIAL,
        LicenseState.SUBSCRIPTION_ACTIVE,
        LicenseState.SUBSCRIPTION_EXPIRED,
        LicenseState.GRACE,
    }
)

ALLOWED_TRANSITIONS: Mapping[LicenseState, FrozenSet[LicenseState]] = {
    LicenseState.UNACTIVATED: frozenset(
        {
            LicenseState.TRIAL,
            LicenseState.SUBSCRIPTION_ACTIVE,
            LicenseState.LOCKED,
        }
    ),
    LicenseState.TRIAL: frozenset(
        {
            LicenseState.SUBSCRIPTION_ACTIVE,
            LicenseState.LOCKED,
        }
    ),
    LicenseState.SUBSCRIPTION_ACTIVE: frozenset(
        {
            LicenseState.SUBSCRIPTION_EXPIRED,
            LicenseState.GRACE,
            LicenseState.LOCKED,
        }
    ),
    LicenseState.GRACE: frozenset(
        {
            LicenseState.SUBSCRIPTION_ACTIVE,
            LicenseState.SUBSCRIPTION_EXPIRED,
            LicenseState.LOCKED,
        }
    ),
    LicenseState.SUBSCRIPTION_EXPIRED: frozenset(
        {
            LicenseState.SUBSCRIPTION_ACTIVE,
            LicenseState.LOCKED,
        }
    ),
    # LOCKED is a SERVICE state, never a terminal one — a lapsed subscription locks until
    # it is paid, and there must always be a way back. It is explicitly not a deletion.
    LicenseState.LOCKED: frozenset(
        {
            LicenseState.SUBSCRIPTION_ACTIVE,
            LicenseState.TRIAL,
        }
    ),
}


class InvalidTransition(ValueError):
    """Raised when a state transition is not allowed."""


def parse_state(value: str | LicenseState | None) -> LicenseState:
    if isinstance(value, LicenseState):
        return value
    if not value:
        return LicenseState.UNACTIVATED
    key = str(value).strip().lower()
    if key in _STATE_ALIASES:
        return _STATE_ALIASES[key]
    try:
        return LicenseState(key)
    except ValueError as exc:
        raise ValueError(f"Unknown license state: {value!r}") from exc


def can_transition(current: LicenseState, new: LicenseState) -> bool:
    if current == new:
        return True
    return new in ALLOWED_TRANSITIONS.get(current, frozenset())


def transition(current: LicenseState, new: LicenseState) -> LicenseState:
    """Return *new* if the transition is legal, else raise InvalidTransition."""
    if can_transition(current, new):
        return new
    raise InvalidTransition(f"Cannot transition from {current.value} to {new.value}")


def requires_phone_home(state: LicenseState) -> bool:
    return state in PHONE_HOME_REQUIRED


def is_permanently_owned(state: LicenseState) -> bool:
    """Always False since 29 Sep 2026 — no state is permanent.

    Kept as a named function rather than deleted so the call sites read as the deliberate
    "nothing is exempt from the subscription check" they now are, instead of silently
    losing a branch. See the module docstring.
    """
    return state in PERMANENT_OWNED
