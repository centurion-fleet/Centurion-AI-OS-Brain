"""License phone-home client — periodic check-in with personalcenturion.com."""

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
from centurion.license.states import (
    LicenseState,
    parse_state,
    requires_phone_home,
)
from centurion.license.store import Entitlement, load_entitlement, save_entitlement

logger = logging.getLogger(__name__)

DEFAULT_CHECK_INTERVAL_DAYS = 30
RETRY_BACKOFF_SECONDS = (3600, 6 * 3600, 24 * 3600, 7 * 24 * 3600)


@dataclass
class CheckinResult:
    ok: bool
    state: Optional[str] = None
    tier: Optional[str] = None
    balance_paid_gbp: Optional[float] = None
    balance_target_gbp: Optional[float] = None
    next_check_by: Optional[float] = None
    grace_until: Optional[float] = None
    signed_attestation: Optional[str] = None
    revoke_reason: Optional[str] = None
    error: Optional[str] = None
    network_error: bool = False
    raw: Optional[Dict[str, Any]] = None


def _license_config(config: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    if config is None:
        try:
            from centurion_cli.config import load_config

            config = load_config() or {}
        except Exception:
            config = {}
    section = config.get("license") if isinstance(config.get("license"), dict) else {}
    return section or {}


def get_license_server_url(config: Optional[Dict[str, Any]] = None) -> str:
    license_cfg = _license_config(config)
    url = (license_cfg.get("server_url") or "").strip().rstrip("/")
    if url:
        return url
    # Fall back to billing.fleet_api_url
    try:
        from centurion_cli.cloud_client import get_fleet_api_base

        return get_fleet_api_base(config)
    except Exception:
        return "https://personalcenturion.com/api/v1"


def check_interval_seconds(config: Optional[Dict[str, Any]] = None) -> float:
    license_cfg = _license_config(config)
    days = license_cfg.get("check_interval_days", DEFAULT_CHECK_INTERVAL_DAYS)
    try:
        return float(days) * 24 * 3600
    except (TypeError, ValueError):
        return DEFAULT_CHECK_INTERVAL_DAYS * 24 * 3600


def is_phone_home_due(
    entitlement: Optional[Entitlement] = None,
    *,
    config: Optional[Dict[str, Any]] = None,
    now: Optional[float] = None,
) -> bool:
    ent = entitlement if entitlement is not None else load_entitlement()
    state = ent.license_state()
    if not requires_phone_home(state):
        return False
    ts = now if now is not None else time.time()
    if ent.next_check_by is not None:
        return ts >= float(ent.next_check_by)
    if ent.last_verified_at is None:
        return True
    return (ts - float(ent.last_verified_at)) >= check_interval_seconds(config)


def _post_json(url: str, payload: Dict[str, Any], timeout: float = 15.0) -> Dict[str, Any]:
    body = json.dumps(payload).encode("utf-8")
    req = Request(
        url,
        data=body,
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            # Cloudflare bans Python-urllib default UA (error 1010 → HTTP 403).
            "User-Agent": "CenturionBrain/5.2.117 (+https://www.1human1ai.com)",
        },
        method="POST",
    )
    with urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def phone_home(
    *,
    entitlement: Optional[Entitlement] = None,
    config: Optional[Dict[str, Any]] = None,
    force: bool = False,
) -> CheckinResult:
    """POST /license/checkin and apply the response to local entitlement."""
    ent = entitlement if entitlement is not None else load_entitlement()
    state = ent.license_state()

    if not force and not is_phone_home_due(ent, config=config):
        return CheckinResult(ok=True, state=state.value, error="not_due")

    try:
        from centurion_cli.cloud_client import get_install_id
        from centurion_cli import __version__ as centurion_version
    except Exception:
        get_install_id = lambda: "unknown"  # noqa: E731
        centurion_version = "unknown"

    import platform as _platform

    fp = ent.machine_fingerprint or compute_fingerprint()
    payload = {
        "license_id": ent.license_id,
        "install_id": get_install_id(),
        "machine_fingerprint": fp,
        "tier": ent.tier,
        "os_version": f"{_platform.system()} {_platform.release()}",
        "centurion_version": centurion_version,
        "last_state": ent.state,
        "nonce": secrets.token_hex(16),
    }

    base = get_license_server_url(config)
    url = f"{base.rstrip('/')}/license/checkin"
    try:
        data = _post_json(url, payload)
    except HTTPError as exc:
        try:
            detail = json.loads(exc.read().decode("utf-8"))
            err = detail.get("error") or str(exc)
        except Exception:
            err = str(exc)
        append_audit("phone_home_http_error", error=err, license_id=ent.license_id)
        return CheckinResult(ok=False, error=err, network_error=False)
    except (URLError, TimeoutError, json.JSONDecodeError, OSError) as exc:
        append_audit("phone_home_network_error", error=str(exc), license_id=ent.license_id)
        _record_retry(ent)
        return CheckinResult(ok=False, error=f"network: {exc}", network_error=True)

    result = CheckinResult(
        ok=bool(data.get("ok", True)),
        state=data.get("state"),
        tier=data.get("tier") or data.get("level"),
        balance_paid_gbp=_as_float(data.get("balance_paid_gbp")),
        balance_target_gbp=_as_float(data.get("balance_target_gbp")),
        next_check_by=_prefer_next_check_unix(data),
        grace_until=_as_float(data.get("grace_until"))
        if not isinstance(data.get("grace_until"), str)
        else _parse_iso_ts(data.get("grace_until")),
        signed_attestation=data.get("signed_attestation"),
        revoke_reason=data.get("revoke_reason"),
        raw=data if isinstance(data, dict) else None,
    )

    apply_checkin_result(ent, result, config=config)
    append_audit(
        "phone_home_ok" if result.ok else "phone_home_rejected",
        license_id=ent.license_id,
        state=result.state or ent.state,
        revoke_reason=result.revoke_reason,
    )
    return result


def apply_checkin_result(
    entitlement: Entitlement,
    result: CheckinResult,
    *,
    config: Optional[Dict[str, Any]] = None,
) -> Entitlement:
    """Mutate + persist entitlement from a check-in response."""
    now = time.time()

    if result.revoke_reason or (
        result.state and parse_state(result.state) == LicenseState.LOCKED
    ):
        entitlement.state = LicenseState.LOCKED.value
        entitlement.revoke_reason = result.revoke_reason or "revoked"
        entitlement.grace_started_at = None
        if result.signed_attestation:
            entitlement.signed_attestation = result.signed_attestation
        save_entitlement(entitlement)
        return entitlement

    if result.tier:
        entitlement.tier = str(result.tier)
    if result.state:
        try:
            new_state = parse_state(result.state)
            entitlement.state = new_state.value
        except ValueError:
            pass

    if result.ok:
        entitlement.last_verified_at = now
        entitlement.grace_started_at = None
        entitlement.revoke_reason = None
        if result.next_check_by is not None:
            entitlement.next_check_by = float(result.next_check_by)
        else:
            entitlement.next_check_by = now + check_interval_seconds(config)
        if result.signed_attestation:
            entitlement.signed_attestation = result.signed_attestation

    save_entitlement(entitlement)
    return entitlement


def _record_retry(entitlement: Entitlement) -> None:
    """Bump next attempt using backoff without changing verified timestamp."""
    attempts_path_key = "_phone_home_failures"
    # Store failure count in audit only; schedule soft retry via next_check_by
    # sooner than full interval but not immediately.
    now = time.time()
    # First failure: retry in 1h if due date already passed, else leave next_check_by.
    if entitlement.next_check_by is None or entitlement.next_check_by <= now:
        entitlement.next_check_by = now + RETRY_BACKOFF_SECONDS[0]
        save_entitlement(entitlement)
    append_audit("phone_home_retry_scheduled", next_check_by=entitlement.next_check_by)
    _ = attempts_path_key  # reserved for future persistent counter


def _as_float(value: Any) -> Optional[float]:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _parse_iso_ts(value: Any) -> Optional[float]:
    if value is None:
        return None
    try:
        from datetime import datetime

        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def _prefer_next_check_unix(data: Dict[str, Any]) -> Optional[float]:
    """Prefer website ``next_check_by_unix``; fall back to numeric or ISO ``next_check_by``."""
    unix = _as_float(data.get("next_check_by_unix"))
    if unix is not None:
        return unix
    raw = data.get("next_check_by")
    as_num = _as_float(raw)
    if as_num is not None and as_num > 1_000_000_000:
        return as_num
    return _parse_iso_ts(raw)


def maybe_phone_home_on_startup(config: Optional[Dict[str, Any]] = None) -> Optional[CheckinResult]:
    """Non-blocking-ish startup check: only runs when license.enabled and due."""
    license_cfg = _license_config(config)
    from utils import is_truthy_value

    if not is_truthy_value(license_cfg.get("enabled"), default=False):
        return None
    ent = load_entitlement()
    if not is_phone_home_due(ent, config=config):
        return None
    try:
        return phone_home(entitlement=ent, config=config)
    except Exception as exc:
        logger.debug("License phone-home on startup failed: %s", exc)
        append_audit("phone_home_startup_error", error=str(exc))
        return CheckinResult(ok=False, error=str(exc), network_error=True)
