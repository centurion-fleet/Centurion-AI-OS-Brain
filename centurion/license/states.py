"""License entitlement state machine.

States and legal transitions for Centurion product licensing (subscription,
rent-to-own, outright). Server attestations drive most transitions; local
code only applies transitions that appear in ALLOWED_TRANSITIONS.
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
    RENT_TO_OWN_ACTIVE = "rent_to_own_active"
    RENT_TO_OWN_PAID_OFF = "rent_to_own_paid_off"
    OUTRIGHT_OWNED = "outright_owned"
    LOCKED = "locked"


class LicenseTier(str, Enum):
    TRIAL = "trial"
    SUBSCRIPTION = "subscription"
    RENT_TO_OWN = "rent_to_own"
    OUTRIGHT = "outright"
    OWNED = "owned"  # website alias for outright


# Website API → local enum aliases (sales-site LICENSE_API_CONTRACT).
_STATE_ALIASES = {
    "owned": LicenseState.OUTRIGHT_OWNED,
    "outright_owned": LicenseState.OUTRIGHT_OWNED,
    "expired": LicenseState.SUBSCRIPTION_EXPIRED,
    "grace": LicenseState.GRACE,
    "pending": LicenseState.UNACTIVATED,
}


# Terminal ownership states — never phone-home, never degrade.
PERMANENT_OWNED: FrozenSet[LicenseState] = frozenset(
    {
        LicenseState.RENT_TO_OWN_PAID_OFF,
        LicenseState.OUTRIGHT_OWNED,
    }
)

# States that require periodic phone-home while active.
PHONE_HOME_REQUIRED: FrozenSet[LicenseState] = frozenset(
    {
        LicenseState.TRIAL,
        LicenseState.SUBSCRIPTION_ACTIVE,
        LicenseState.SUBSCRIPTION_EXPIRED,
        LicenseState.GRACE,
        LicenseState.RENT_TO_OWN_ACTIVE,
    }
)

ALLOWED_TRANSITIONS: Mapping[LicenseState, FrozenSet[LicenseState]] = {
    LicenseState.UNACTIVATED: frozenset(
        {
            LicenseState.TRIAL,
            LicenseState.SUBSCRIPTION_ACTIVE,
            LicenseState.RENT_TO_OWN_ACTIVE,
            LicenseState.OUTRIGHT_OWNED,
            LicenseState.LOCKED,
        }
    ),
    LicenseState.TRIAL: frozenset(
        {
            LicenseState.SUBSCRIPTION_ACTIVE,
            LicenseState.RENT_TO_OWN_ACTIVE,
            LicenseState.OUTRIGHT_OWNED,
            LicenseState.LOCKED,
        }
    ),
    LicenseState.SUBSCRIPTION_ACTIVE: frozenset(
        {
            LicenseState.SUBSCRIPTION_EXPIRED,
            LicenseState.GRACE,
            LicenseState.RENT_TO_OWN_ACTIVE,
            LicenseState.OUTRIGHT_OWNED,
            LicenseState.LOCKED,
        }
    ),
    LicenseState.GRACE: frozenset(
        {
            LicenseState.SUBSCRIPTION_ACTIVE,
            LicenseState.SUBSCRIPTION_EXPIRED,
            LicenseState.LOCKED,
            LicenseState.OUTRIGHT_OWNED,
        }
    ),
    LicenseState.SUBSCRIPTION_EXPIRED: frozenset(
        {
            LicenseState.SUBSCRIPTION_ACTIVE,
            LicenseState.LOCKED,
            LicenseState.OUTRIGHT_OWNED,
            LicenseState.RENT_TO_OWN_ACTIVE,
        }
    ),
    LicenseState.RENT_TO_OWN_ACTIVE: frozenset(
        {
            LicenseState.RENT_TO_OWN_PAID_OFF,
            LicenseState.LOCKED,
            LicenseState.OUTRIGHT_OWNED,
        }
    ),
    LicenseState.RENT_TO_OWN_PAID_OFF: frozenset(),
    LicenseState.OUTRIGHT_OWNED: frozenset(),
    LicenseState.LOCKED: frozenset(
        {
            LicenseState.SUBSCRIPTION_ACTIVE,
            LicenseState.RENT_TO_OWN_ACTIVE,
            LicenseState.OUTRIGHT_OWNED,
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
    return state in PERMANENT_OWNED
