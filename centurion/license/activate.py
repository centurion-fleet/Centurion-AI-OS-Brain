"""License activation flows — trial, subscription, RTO, outright redeem."""

from __future__ import annotations

import json
import logging
import secrets
import time
from dataclasses import dataclass
from typing import Any, Dict, Optional
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from centurion.license.audit import append_audit
from centurion.license.fingerprint import compute_fingerprint
from centurion.license.phone_home import get_license_server_url
from centurion.license.states import LicenseState, LicenseTier
from centurion.license.store import (
    DEFAULT_RTO_TARGET_GBP,
    Entitlement,
    load_entitlement,
    save_entitlement,
)
from centurion.license.tokens import verify_attestation

logger = logging.getLogger(__name__)

DEFAULT_TRIAL_DAYS = 14
# Cloudflare blocks Python-urllib's default UA (error 1010 → HTTP 403).
_LICENSE_HTTP_UA = "CenturionBrain/5.2.117 (+https://www.1human1ai.com)"


@dataclass
class ActivateResult:
    ok: bool
    entitlement: Optional[Entitlement] = None
    error: Optional[str] = None
    message: Optional[str] = None


def _post_json(url: str, payload: Dict[str, Any], timeout: float = 20.0) -> Dict[str, Any]:
    body = json.dumps(payload).encode("utf-8")
    req = Request(
        url,
        data=body,
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": _LICENSE_HTTP_UA,
        },
        method="POST",
    )
    try:
        with urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except HTTPError as exc:
        detail = ""
        try:
            raw = exc.read().decode("utf-8", errors="replace")
            parsed = json.loads(raw) if raw.strip().startswith("{") else {}
            if isinstance(parsed, dict) and parsed.get("error"):
                detail = str(parsed["error"])
            elif raw and "error code: 1010" in raw:
                detail = (
                    "Blocked by website firewall. Update Centurion AI OS "
                    "(license client User-Agent) and retry."
                )
            elif raw:
                detail = raw.strip()[:240]
        except Exception:
            detail = ""
        msg = f"HTTP Error {exc.code}: {detail or exc.reason}"
        raise URLError(msg) from exc


def activate_trial(
    *,
    days: int = DEFAULT_TRIAL_DAYS,
    config: Optional[Dict[str, Any]] = None,
    offline: bool = False,
) -> ActivateResult:
    """Start a local trial (optionally registered with the license server)."""
    ent = load_entitlement()
    if ent.license_state() not in {
        LicenseState.UNACTIVATED,
        LicenseState.LOCKED,
    }:
        return ActivateResult(
            ok=False,
            entitlement=ent,
            error=f"Cannot start trial from state {ent.state}",
        )

    now = time.time()
    fp = compute_fingerprint()
    ent.machine_fingerprint = fp
    ent.tier = LicenseTier.TRIAL.value
    ent.state = LicenseState.TRIAL.value
    ent.trial_expires_at = now + days * 86400
    ent.last_verified_at = now
    ent.grace_started_at = None
    ent.revoke_reason = None
    if not ent.license_id:
        ent.license_id = f"trial-{secrets.token_hex(8)}"

    if not offline:
        try:
            base = get_license_server_url(config)
            data = _post_json(
                f"{base.rstrip('/')}/license/activate",
                {
                    "tier": LicenseTier.TRIAL.value,
                    "machine_fingerprint": fp,
                    "trial_days": days,
                    "license_id": ent.license_id,
                },
            )
            if data.get("license_id"):
                ent.license_id = str(data["license_id"])
            if data.get("signed_attestation"):
                ent.signed_attestation = str(data["signed_attestation"])
            if data.get("trial_expires_at") is not None:
                ent.trial_expires_at = float(data["trial_expires_at"])
        except (HTTPError, URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
            logger.info("Trial server activate unavailable; continuing offline: %s", exc)

    save_entitlement(ent)
    append_audit("activate_trial", license_id=ent.license_id, days=days)
    return ActivateResult(ok=True, entitlement=ent, message=f"Trial active for {days} days")


def activate_from_server(
    *,
    tier: str,
    activation_code: Optional[str] = None,
    api_key: Optional[str] = None,
    config: Optional[Dict[str, Any]] = None,
) -> ActivateResult:
    """Activate via the license server (website `/api/v1/license/activate`).

    Tier may be ``subscription``, ``rent_to_own``, ``owned``/``outright``, or
    ``paid``/``code`` (code-driven — server returns the real level/state).
    """
    tier_norm = tier.strip().lower()
    code_driven = tier_norm in {"paid", "code", "auto"}
    if tier_norm in {"owned", "outright"}:
        tier_norm = LicenseTier.OUTRIGHT.value
        state = LicenseState.OUTRIGHT_OWNED
    elif tier_norm in {"sub", "subscription"} or code_driven:
        tier_norm = LicenseTier.SUBSCRIPTION.value
        state = LicenseState.SUBSCRIPTION_ACTIVE
    elif tier_norm in {"rto", "rent_to_own"}:
        tier_norm = LicenseTier.RENT_TO_OWN.value
        state = LicenseState.RENT_TO_OWN_ACTIVE
    else:
        return ActivateResult(ok=False, error=f"Unsupported tier: {tier}")

    if not activation_code and not api_key and not code_driven:
        # Still allow trial-like paths elsewhere; paid activation needs a code.
        pass
    if not (activation_code or api_key):
        return ActivateResult(ok=False, error="activation_code required")

    fp = compute_fingerprint()
    try:
        from centurion_cli.cloud_client import get_install_id
    except Exception:
        get_install_id = lambda: "unknown"  # noqa: E731

    base = get_license_server_url(config)
    # Website contract fields + legacy aliases.
    payload: Dict[str, Any] = {
        "code": activation_code,
        "activation_code": activation_code,
        "hardware_id": fp,
        "machine_fingerprint": fp,
        "install_id": get_install_id(),
        "api_key": api_key,
        "tier": tier_norm,
    }
    try:
        data = _post_json(f"{base.rstrip('/')}/license/activate", payload)
    except (HTTPError, URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
        append_audit("activate_failed", tier=tier_norm, error=str(exc))
        return ActivateResult(ok=False, error=f"Activation failed: {exc}")

    if not data.get("ok", True):
        return ActivateResult(ok=False, error=data.get("error") or "Activation rejected")

    from centurion.license.states import parse_state

    ent = load_entitlement()
    ent.machine_fingerprint = fp
    server_tier = str(data.get("tier") or data.get("level") or tier_norm).lower()
    if server_tier in {"owned", "outright"}:
        server_tier = LicenseTier.OUTRIGHT.value
    ent.tier = server_tier
    try:
        ent.state = parse_state(str(data.get("state") or state.value)).value
    except ValueError:
        ent.state = state.value
    ent.license_id = str(data.get("license_id") or ent.license_id or "")
    ent.last_verified_at = time.time()
    ent.grace_started_at = None
    ent.revoke_reason = None
    if data.get("balance_paid_gbp") is not None:
        ent.balance_paid_gbp = float(data["balance_paid_gbp"])
    if data.get("balance_target_gbp") is not None:
        ent.balance_target_gbp = float(data["balance_target_gbp"])
    elif server_tier == LicenseTier.RENT_TO_OWN.value:
        ent.balance_target_gbp = DEFAULT_RTO_TARGET_GBP
    if data.get("signed_attestation"):
        ent.signed_attestation = str(data["signed_attestation"])
    # Prefer unix seconds from website contract; ISO next_check_by is not a float.
    if data.get("next_check_by_unix") is not None:
        try:
            ent.next_check_by = float(data["next_check_by_unix"])
        except (TypeError, ValueError):
            pass
    elif data.get("next_check_by") is not None:
        raw = data["next_check_by"]
        try:
            ent.next_check_by = float(raw)
        except (TypeError, ValueError):
            try:
                from datetime import datetime

                ent.next_check_by = datetime.fromisoformat(str(raw).replace("Z", "+00:00")).timestamp()
            except Exception:
                pass
    if data.get("customer_name"):
        ent.customer_name = str(data["customer_name"])

    save_entitlement(ent)
    append_audit("activate_ok", tier=ent.tier, license_id=ent.license_id)
    return ActivateResult(ok=True, entitlement=ent, message=f"Activated as {ent.tier}")


def redeem_outright_token(
    token: str,
    *,
    config: Optional[Dict[str, Any]] = None,
    offline_attestation: Optional[str] = None,
) -> ActivateResult:
    """Redeem a proof-of-purchase token and bind to this machine."""
    fp = compute_fingerprint()
    try:
        from centurion_cli.cloud_client import get_install_id
    except Exception:
        get_install_id = lambda: "unknown"  # noqa: E731

    # Prefer server redeem; allow offline attestation for air-gapped DIF Y images.
    data: Dict[str, Any] = {}
    if offline_attestation:
        data = {
            "ok": True,
            "state": LicenseState.OUTRIGHT_OWNED.value,
            "tier": LicenseTier.OUTRIGHT.value,
            "signed_attestation": offline_attestation,
            "token_id": token,
        }
    else:
        base = get_license_server_url(config)
        try:
            data = _post_json(
                f"{base.rstrip('/')}/license/redeem",
                {
                    "token": token,
                    "machine_fingerprint": fp,
                    "install_id": get_install_id(),
                },
            )
        except (HTTPError, URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
            append_audit("redeem_failed", error=str(exc))
            return ActivateResult(ok=False, error=f"Redeem failed: {exc}")

    if not data.get("ok", True):
        return ActivateResult(ok=False, error=data.get("error") or "Redeem rejected")

    attestation = data.get("signed_attestation")
    if attestation:
        try:
            attested = verify_attestation(
                str(attestation),
                expected_fingerprint=fp,
                config=config,
            )
            if attested.state and attested.state != LicenseState.OUTRIGHT_OWNED.value:
                if attested.kind != "outright":
                    return ActivateResult(ok=False, error="Attestation is not an outright grant")
        except ValueError as exc:
            return ActivateResult(ok=False, error=str(exc))

    ent = load_entitlement()
    ent.machine_fingerprint = fp
    ent.tier = LicenseTier.OUTRIGHT.value
    ent.state = LicenseState.OUTRIGHT_OWNED.value
    ent.license_id = str(data.get("license_id") or ent.license_id or f"outright-{secrets.token_hex(6)}")
    ent.token_id = str(data.get("token_id") or token)
    ent.signed_attestation = str(attestation) if attestation else ent.signed_attestation
    ent.last_verified_at = time.time()
    ent.grace_started_at = None
    ent.revoke_reason = None
    ent.next_check_by = None
    if data.get("customer_name"):
        ent.customer_name = str(data["customer_name"])
    save_entitlement(ent)
    append_audit("redeem_outright", license_id=ent.license_id, token_id=ent.token_id)
    return ActivateResult(ok=True, entitlement=ent, message="Outright license bound to this machine")


def request_reissue(
    *,
    reason: str,
    proof_of_purchase: Optional[str] = None,
    old_fingerprint: Optional[str] = None,
    config: Optional[Dict[str, Any]] = None,
) -> ActivateResult:
    """Request hardware re-issuance after machine failure (server/support flow)."""
    ent = load_entitlement()
    fp = compute_fingerprint()
    base = get_license_server_url(config)
    payload = {
        "license_id": ent.license_id,
        "token_id": ent.token_id,
        "old_fingerprint": old_fingerprint or ent.machine_fingerprint,
        "new_fingerprint": fp,
        "reason": reason,
        "proof_of_purchase": proof_of_purchase,
    }
    try:
        data = _post_json(f"{base.rstrip('/')}/license/reissue", payload)
    except (HTTPError, URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
        append_audit("reissue_failed", error=str(exc))
        return ActivateResult(ok=False, error=f"Reissue request failed: {exc}")

    append_audit(
        "reissue_requested",
        license_id=ent.license_id,
        status=data.get("status"),
    )

    return ActivateResult(
        ok=bool(data.get("ok", True)),
        entitlement=ent,
        message=data.get("message")
        or "Reissue request submitted — support will issue a new token",
        error=None if data.get("ok", True) else data.get("error"),
    )
