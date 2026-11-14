"""License activation flows — trial and monthly subscription.

The rent-to-own / outright paths are retired. ``redeem_purchase_token`` is kept
as a stub that refuses cleanly, so an old caller gets a clear message instead of
an AttributeError.
"""

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
    Entitlement,
    load_entitlement,
    save_entitlement,
)

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

    Tier may be ``subscription``, or ``paid``/``code`` (code-driven — the server
    returns the real level and state).

    The retired names ``owned``/``outright``/``rent_to_own`` are still ACCEPTED
    so an old command, script or Brain does not fail on an unknown tier, but
    they no longer select a different licence: there is one licence, a monthly
    subscription. Reading them as "let the server decide" is also what those
    callers meant, since the server is authoritative for level and state.
    """
    tier_norm = tier.strip().lower()
    code_driven = tier_norm in {
        "paid",
        "code",
        "auto",
        # retired tier names — accepted, no longer a distinct licence
        "owned",
        "outright",
        "rto",
        "rent_to_own",
    }
    if tier_norm in {"sub", "subscription"} or code_driven:
        tier_norm = LicenseTier.SUBSCRIPTION.value
        state = LicenseState.SUBSCRIPTION_ACTIVE
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
        # Retired names. The website can still echo one back for a licence
        # issued before the retirement, so map it rather than storing a tier
        # the local enum no longer has.
        server_tier = LicenseTier.SUBSCRIPTION.value
    elif server_tier in {"rto", "rent_to_own"}:
        server_tier = LicenseTier.SUBSCRIPTION.value
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
        # Deprecated: the website still emits this as 0 for older Brains.
        # Recorded, never acted on — entitlement is the credited period.
        ent.balance_target_gbp = float(data["balance_target_gbp"])
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


def redeem_purchase_token(
    token: str,
    *,
    config: Optional[Dict[str, Any]] = None,
) -> ActivateResult:
    """Retired: redeeming a proof-of-purchase token for an outright licence.

    There are no outright licences. A Centurion licence is a monthly
    subscription, and the implementation fee is a separate commercial matter
    handled by a partner — so a proof-of-purchase token has no licence to
    convert into.

    This previously raised AttributeError on every call: the function bound
    `LicenseTier.OUTRIGHT` and `LicenseState.OUTRIGHT_OWNED` unconditionally,
    and both were removed when the tier was retired. It also gated on
    `attested.kind == "outright"`, while the website's attestation payload
    carries no `kind` at all — so it could never have granted anything.

    It now refuses cleanly rather than crashing, and the refusal is the
    CONSERVATIVE reading: this is a licence gate, and a broken gate must fail
    closed, never open. Relaxing it to accept an attestation is a decision for
    the owner, not a bug fix — air-gapped installs may still need a redeem path
    and it would need to be designed against the website's actual payload.
    """
    append_audit("redeem_retired", token_present=bool(token))
    return ActivateResult(
        ok=False,
        error=(
            "Redeeming a proof-of-purchase token is no longer available: "
            "outright licences are retired and a Centurion licence is a monthly "
            "subscription. Run: centurion license activate subscription"
        ),
    )


def request_reissue(
    *,
    reason: str,
    proof_of_purchase: Optional[str] = None,
    old_fingerprint: Optional[str] = None,
    requested_edition: Optional[str] = None,
    config: Optional[Dict[str, Any]] = None,
) -> ActivateResult:
    """Request hardware re-issuance after machine failure (server/support flow).

    A re-bind is a repair, never an upgrade (business/EDITIONS.md §1). A request
    that would land on a different edition is refused here, before it is sent,
    so no support conversation can quietly become a licence change. The licence
    server applies the same rule independently.
    """
    from centurion.license.edition import rebind_refusal

    ent = load_entitlement()

    refusal = rebind_refusal(ent.edition(), requested_edition)
    if refusal:
        append_audit(
            "reissue_refused_edition_change",
            current_edition=ent.edition(),
            requested_edition=requested_edition,
            reason=reason,
        )
        return ActivateResult(ok=False, error=refusal)

    fp = compute_fingerprint()
    base = get_license_server_url(config)
    payload = {
        "license_id": ent.license_id,
        "token_id": ent.token_id,
        "old_fingerprint": old_fingerprint or ent.machine_fingerprint,
        "new_fingerprint": fp,
        "reason": reason,
        "proof_of_purchase": proof_of_purchase,
        # The edition being repaired. The server must issue the same one back:
        # a replacement box is provisioned to the customer's edition, and a
        # reissue is never the moment to change it.
        "edition": ent.edition(),
        "seats": ent.seat_limit(),
    }
    try:
        data = _post_json(f"{base.rstrip('/')}/license/reissue", payload)
    except (HTTPError, URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
        append_audit("reissue_failed", error=str(exc))
        return ActivateResult(ok=False, error=f"Reissue request failed: {exc}")

    # If the server answered with an edition, it must be the one we asked about.
    # A different one back would be the upgrade this product does not have.
    returned = data.get("edition") or data.get("tier")
    returned_refusal = rebind_refusal(ent.edition(), returned)
    if returned_refusal:
        append_audit(
            "reissue_refused_server_edition_change",
            current_edition=ent.edition(),
            returned_edition=returned,
            license_id=ent.license_id,
        )
        return ActivateResult(ok=False, error=returned_refusal)

    append_audit(
        "reissue_requested",
        license_id=ent.license_id,
        status=data.get("status"),
        edition=ent.edition(),
    )

    return ActivateResult(
        ok=bool(data.get("ok", True)),
        entitlement=ent,
        message=data.get("message")
        or "Reissue request submitted — support will issue a new token",
        error=None if data.get("ok", True) else data.get("error"),
    )
