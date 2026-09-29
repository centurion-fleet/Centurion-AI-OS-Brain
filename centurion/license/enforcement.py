"""License enforcement — grace → restricted → locked evaluation.

Checks run at session start / between turns only (never mid-tool-batch)
to preserve prompt-cache policy.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from enum import Enum
from typing import Any, Dict, Optional

from centurion.license.phone_home import check_interval_seconds
from centurion.license.states import (
    LicenseState,
    requires_phone_home,
)
from centurion.license.store import Entitlement, load_entitlement, save_entitlement

logger = logging.getLogger(__name__)


class EnforcementMode(str, Enum):
    ALLOW = "allow"
    WARN = "warn"
    RESTRICTED = "restricted"
    LOCKED = "locked"


@dataclass
class EnforcementDecision:
    mode: EnforcementMode
    state: LicenseState
    message: str = ""
    days_overdue: float = 0.0
    renew_url: str = "https://personalcenturion.com/manage-subscription"

    @property
    def allows_agent(self) -> bool:
        return self.mode in {EnforcementMode.ALLOW, EnforcementMode.WARN}

    @property
    def allows_tools(self) -> bool:
        return self.mode in {EnforcementMode.ALLOW, EnforcementMode.WARN}

    @property
    def activation_only(self) -> bool:
        return self.mode == EnforcementMode.LOCKED


def _license_config(config: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    if config is None:
        try:
            from centurion_cli.config import load_config

            config = load_config() or {}
        except Exception:
            config = {}
    section = config.get("license") if isinstance(config.get("license"), dict) else {}
    return section or {}


def enforcement_enabled(config: Optional[Dict[str, Any]] = None) -> bool:
    """True only when license.enabled AND license.enforcement are truthy."""
    from utils import is_truthy_value

    cfg = _license_config(config)
    if not is_truthy_value(cfg.get("enabled"), default=False):
        return False
    return is_truthy_value(cfg.get("enforcement"), default=False)


def _grace_days(config: Optional[Dict[str, Any]], key: str, default: int) -> int:
    cfg = _license_config(config)
    try:
        return int(cfg.get(key, default))
    except (TypeError, ValueError):
        return default


def _portal_url(config: Optional[Dict[str, Any]] = None) -> str:
    cfg = _license_config(config)
    if cfg.get("portal_url"):
        return str(cfg["portal_url"]).rstrip("/") + "/manage-subscription"
    try:
        from centurion_cli.config import load_config

        full = config if config is not None else (load_config() or {})
        billing = full.get("billing") if isinstance(full.get("billing"), dict) else {}
        portal = (billing or {}).get("portal_url") or "https://personalcenturion.com"
        return str(portal).rstrip("/") + "/manage-subscription"
    except Exception:
        return "https://personalcenturion.com/manage-subscription"


def evaluate(
    entitlement: Optional[Entitlement] = None,
    *,
    config: Optional[Dict[str, Any]] = None,
    now: Optional[float] = None,
) -> EnforcementDecision:
    """Evaluate current entitlement into an enforcement mode."""
    renew = _portal_url(config)

    if not enforcement_enabled(config):
        ent = entitlement if entitlement is not None else load_entitlement()
        return EnforcementDecision(
            mode=EnforcementMode.ALLOW,
            state=ent.license_state(),
            message="License enforcement disabled",
            renew_url=renew,
        )

    ent = entitlement if entitlement is not None else load_entitlement()
    state = ent.license_state()
    ts = now if now is not None else time.time()

    if state == LicenseState.LOCKED:
        reason = ent.revoke_reason or "License locked"
        return EnforcementDecision(
            mode=EnforcementMode.LOCKED,
            state=state,
            message=reason,
            renew_url=renew,
        )

    if state == LicenseState.UNACTIVATED:
        return EnforcementDecision(
            mode=EnforcementMode.LOCKED,
            state=state,
            message="Centurion is not activated. Run: centurion license activate",
            renew_url=renew,
        )

    if state == LicenseState.TRIAL and ent.trial_expires_at is not None:
        if ts >= float(ent.trial_expires_at):
            ent.state = LicenseState.LOCKED.value
            ent.revoke_reason = "Trial expired"
            save_entitlement(ent)
            return EnforcementDecision(
                mode=EnforcementMode.LOCKED,
                state=LicenseState.LOCKED,
                message="Trial expired. Activate a subscription or redeem a purchase token.",
                renew_url=renew,
            )

    if state == LicenseState.SUBSCRIPTION_EXPIRED:
        return _grace_decision(ent, config=config, now=ts, renew=renew, already_expired=True)

    if requires_phone_home(state):
        due_at = _due_timestamp(ent, config=config)
        if ts <= due_at:
            return EnforcementDecision(
                mode=EnforcementMode.ALLOW,
                state=state,
                message="License active",
                renew_url=renew,
            )
        # Past due — start or continue grace.
        if ent.grace_started_at is None:
            ent.grace_started_at = due_at
            if state == LicenseState.SUBSCRIPTION_ACTIVE:
                ent.state = LicenseState.SUBSCRIPTION_EXPIRED.value
                state = LicenseState.SUBSCRIPTION_EXPIRED
            save_entitlement(ent)
        return _grace_decision(ent, config=config, now=ts, renew=renew, already_expired=True)

    return EnforcementDecision(
        mode=EnforcementMode.ALLOW,
        state=state,
        message="License active",
        renew_url=renew,
    )


def _due_timestamp(ent: Entitlement, *, config: Optional[Dict[str, Any]]) -> float:
    if ent.next_check_by is not None:
        return float(ent.next_check_by)
    if ent.last_verified_at is not None:
        return float(ent.last_verified_at) + check_interval_seconds(config)
    # Never verified — treat as immediately due (grace starts now if enforcement on).
    return float(ent.updated_at or time.time())


def _grace_decision(
    ent: Entitlement,
    *,
    config: Optional[Dict[str, Any]],
    now: float,
    renew: str,
    already_expired: bool,
) -> EnforcementDecision:
    grace_start = float(ent.grace_started_at or _due_timestamp(ent, config=config))
    days_overdue = max(0.0, (now - grace_start) / 86400.0)
    warn_days = _grace_days(config, "grace_warn_days", 7)
    restrict_days = _grace_days(config, "grace_restrict_days", 14)
    lock_days = _grace_days(config, "grace_lock_days", 15)
    state = ent.license_state()

    if days_overdue >= lock_days:
        if state != LicenseState.LOCKED:
            ent.state = LicenseState.LOCKED.value
            ent.revoke_reason = "Grace period exhausted — license verification overdue"
            save_entitlement(ent)
        return EnforcementDecision(
            mode=EnforcementMode.LOCKED,
            state=LicenseState.LOCKED,
            message=(
                f"License locked after {lock_days} days without verification. "
                f"Renew at {renew} then run: centurion license activate"
            ),
            days_overdue=days_overdue,
            renew_url=renew,
        )

    if days_overdue >= restrict_days:
        return EnforcementDecision(
            mode=EnforcementMode.RESTRICTED,
            state=state,
            message=(
                f"License restricted (day {days_overdue:.0f}/{lock_days}). "
                f"Renew at {renew}"
            ),
            days_overdue=days_overdue,
            renew_url=renew,
        )

    # warn window (0..warn_days) and through restrict threshold
    _ = already_expired
    _ = warn_days
    return EnforcementDecision(
        mode=EnforcementMode.WARN,
        state=state,
        message=(
            f"License verification overdue ({days_overdue:.0f} days). "
            f"Renew at {renew} — lock in {max(0, lock_days - days_overdue):.0f} days."
        ),
        days_overdue=days_overdue,
        renew_url=renew,
    )


def gate_agent_turn(
    *,
    config: Optional[Dict[str, Any]] = None,
) -> EnforcementDecision:
    """Call at session start / between turns before starting an agent loop."""
    return evaluate(config=config)


def locked_user_message(decision: EnforcementDecision) -> str:
    if decision.mode == EnforcementMode.LOCKED:
        return (
            f"🔒 {decision.message}\n"
            f"  Manage billing: {decision.renew_url}\n"
            f"  Or run: centurion license status"
        )
    if decision.mode == EnforcementMode.RESTRICTED:
        return (
            f"⚠️  {decision.message}\n"
            f"  Agent tools are paused until the license is renewed."
        )
    if decision.mode == EnforcementMode.WARN:
        return f"⚠️  {decision.message}"
    return ""
