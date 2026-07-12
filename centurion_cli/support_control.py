"""Structured support plane for iPhone Get Help and GTK Support Tools.

Collects redacted health snapshots, stores time-limited support bundles keyed
by short human-readable codes, and runs safe thinking-service recovery (LKG
restore + re-probe). No secrets leave the host in phone-visible payloads.
"""

from __future__ import annotations

import json
import logging
import os
import platform
import random
import sys
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from centurion_constants import display_centurion_home, get_centurion_home

from centurion_cli.provider_control import (
    get_status,
    restore_last_known_good,
)

logger = logging.getLogger(__name__)

# Crockford base32 — no 0/O, 1/I/L ambiguity.
_CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
_BUNDLE_TTL_HOURS = 24
_MAX_BUNDLES = 50
_MAX_ERROR_LINES = 30

_THINKING_WORKING = "working_normally"
_THINKING_NEEDS_ATTENTION = "needs_attention"
_THINKING_UNKNOWN = "unknown"


@dataclass
class HealthSnapshot:
    version: str = ""
    release_date: str = ""
    profile_display: str = ""
    os_info: str = ""
    python_version: str = ""
    gateway_running: bool = False
    thinking_health: str = _THINKING_UNKNOWN
    thinking_message: str = ""
    last_good_available: bool = False
    issue_count: int = 0
    issues: list[str] = field(default_factory=list)
    checked_at: str = ""

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class SupportBundleResult:
    ok: bool
    code: str = ""
    expires_at: str = ""
    summary: str = ""
    thinking_health: str = _THINKING_UNKNOWN
    message: str = ""

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class AutoFixResult:
    ok: bool
    message: str = ""
    thinking_health: str = _THINKING_UNKNOWN
    restored: bool = False

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def _bundles_dir() -> Path:
    path = get_centurion_home() / "state" / "support_bundles"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _generate_code() -> str:
    """Return a fresh ``XXX-XXX`` support code."""
    while True:
        chars = [_CODE_ALPHABET[random.randrange(len(_CODE_ALPHABET))] for _ in range(6)]
        code = f"{chars[0]}{chars[1]}{chars[2]}-{chars[3]}{chars[4]}{chars[5]}"
        if not (_bundles_dir() / f"{code}.json").exists():
            return code


def _normalize_code(code: str) -> str:
    raw = code.strip().upper().replace(" ", "")
    if len(raw) == 6 and "-" not in raw:
        return f"{raw[:3]}-{raw[3:]}"
    return raw


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def _thinking_health_from_status(health: str) -> str:
    if health == "ok":
        return _THINKING_WORKING
    if health in {"degraded", "broken"}:
        return _THINKING_NEEDS_ATTENTION
    return _THINKING_UNKNOWN


def _plain_summary(*, thinking_health: str, last_good_available: bool) -> str:
    if thinking_health == _THINKING_WORKING:
        base = "Your Centurion's thinking service is working normally."
    elif thinking_health == _THINKING_NEEDS_ATTENTION:
        base = "Your Centurion's thinking service needs attention."
    else:
        base = "Your Centurion's thinking service could not be verified."
    if last_good_available and thinking_health != _THINKING_WORKING:
        return f"{base} Last working setup is available."
    return base


def _gateway_running() -> bool:
    try:
        from centurion_cli.gateway import get_gateway_runtime_snapshot

        return bool(get_gateway_runtime_snapshot().running)
    except Exception:
        return False


def _load_config_safe() -> dict[str, Any]:
    try:
        from centurion_cli.config import load_config

        cfg = load_config()
        return cfg if isinstance(cfg, dict) else {}
    except Exception as exc:
        logger.debug("config load failed: %s", exc)
        return {}


def _current_provider_has_key(config: dict[str, Any]) -> bool:
    """Return whether the active provider appears to have credentials (no values)."""
    try:
        from centurion_cli.env_loader import load_centurion_dotenv
        from centurion_cli.config import get_env_path, get_project_root

        env_path = get_env_path()
        load_centurion_dotenv(
            centurion_home=env_path.parent,
            project_env=get_project_root() / ".env",
        )
        from centurion_cli.runtime_provider import resolve_runtime_credentials

        model_cfg = config.get("model") or {}
        provider = str(model_cfg.get("provider") or "").strip()
        model = str(model_cfg.get("default") or "").strip()
        if not provider:
            return False
        creds = resolve_runtime_credentials(provider=provider, model=model)
        return bool(creds and creds.api_key)
    except Exception:
        return False


def _collect_lightweight_issues(config: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    if not config:
        issues.append("Configuration could not be loaded.")
    model_cfg = (config or {}).get("model") or {}
    if not str(model_cfg.get("provider") or "").strip():
        issues.append("No thinking service provider is configured.")
    if not str(model_cfg.get("default") or "").strip():
        issues.append("No default thinking model is configured.")
    elif config and not _current_provider_has_key(config):
        issues.append("The active thinking service is missing its API key on this computer.")
    return issues


def _read_recent_errors() -> list[str]:
    log_path = get_centurion_home() / "logs" / "errors.log"
    if not log_path.is_file():
        return []
    try:
        lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
        tail = lines[-_MAX_ERROR_LINES:]
        from agent.redact import redact_sensitive_text

        return [redact_sensitive_text(line) for line in tail if line.strip()]
    except Exception as exc:
        logger.debug("errors.log read failed: %s", exc)
        return []


def _dump_summary_fields(config: dict[str, Any]) -> dict[str, Any]:
    """Redacted dump-style fields for support staff (no secret values)."""
    model_cfg = (config or {}).get("model") or {}
    terminal_cfg = (config or {}).get("terminal") or {}
    try:
        from centurion_cli.profiles import get_active_profile_name

        profile = get_active_profile_name() or "(default)"
    except Exception:
        profile = "(default)"
    try:
        from centurion_cli import __version__, __release_date__
    except ImportError:
        __version__ = "(unknown)"
        __release_date__ = ""

    return {
        "version": __version__,
        "release_date": __release_date__,
        "profile": profile,
        "centurion_home": display_centurion_home(),
        "model": str(model_cfg.get("default") or ""),
        "provider": str(model_cfg.get("provider") or ""),
        "terminal_backend": str(terminal_cfg.get("backend") or "local"),
        "gateway_running": _gateway_running(),
        "os": f"{platform.system()} {platform.release()} {platform.machine()}",
        "python": sys.version.split()[0],
    }


def collect_health_snapshot(*, probe: bool = True) -> HealthSnapshot:
    """Collect a phone-safe structured health snapshot."""
    config = _load_config_safe()
    issues = _collect_lightweight_issues(config)

    try:
        status = get_status(probe=probe)
        thinking_health = _thinking_health_from_status(status.health)
        thinking_message = status.health_message or _plain_summary(
            thinking_health=thinking_health,
            last_good_available=status.last_good_available,
        )
        last_good_available = status.last_good_available
        if status.health != "ok":
            if status.health_message and status.health_message not in issues:
                issues.append(status.health_message)
    except Exception as exc:
        logger.debug("thinking status probe failed: %s", exc)
        thinking_health = _THINKING_UNKNOWN
        thinking_message = "Could not verify your Centurion's thinking service."
        last_good_available = False
        issues.append("Thinking service status could not be read.")

    try:
        from centurion_cli import __version__, __release_date__
    except ImportError:
        __version__ = "(unknown)"
        __release_date__ = ""

    return HealthSnapshot(
        version=__version__,
        release_date=__release_date__,
        profile_display=display_centurion_home(),
        os_info=f"{platform.system()} {platform.release()} {platform.machine()}",
        python_version=sys.version.split()[0],
        gateway_running=_gateway_running(),
        thinking_health=thinking_health,
        thinking_message=thinking_message,
        last_good_available=last_good_available,
        issue_count=len(issues),
        issues=issues,
        checked_at=_iso(_utc_now()),
    )


def _prune_expired_bundles() -> None:
    now = _utc_now()
    bundle_dir = _bundles_dir()
    entries: list[tuple[datetime, Path]] = []
    for path in bundle_dir.glob("*.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            expires_raw = data.get("expires_at") or ""
            expires = datetime.strptime(expires_raw, "%Y-%m-%dT%H:%M:%SZ").replace(
                tzinfo=timezone.utc
            )
        except Exception:
            path.unlink(missing_ok=True)
            continue
        if expires <= now:
            path.unlink(missing_ok=True)
            continue
        entries.append((expires, path))

    if len(entries) <= _MAX_BUNDLES:
        return
    entries.sort(key=lambda item: item[0])
    for _expires, path in entries[: len(entries) - _MAX_BUNDLES]:
        path.unlink(missing_ok=True)


def create_support_bundle(*, probe: bool = True) -> SupportBundleResult:
    """Create a time-limited support bundle and return its short code."""
    _prune_expired_bundles()
    snapshot = collect_health_snapshot(probe=probe)
    config = _load_config_safe()
    code = _generate_code()
    created = _utc_now()
    expires = created + timedelta(hours=_BUNDLE_TTL_HOURS)
    summary = _plain_summary(
        thinking_health=snapshot.thinking_health,
        last_good_available=snapshot.last_good_available,
    )

    payload = {
        "code": code,
        "created_at": _iso(created),
        "expires_at": _iso(expires),
        "summary_plain": summary,
        "snapshot": snapshot.to_dict(),
        "dump_summary": _dump_summary_fields(config),
        "recent_errors": _read_recent_errors(),
    }
    path = _bundles_dir() / f"{code}.json"
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    return SupportBundleResult(
        ok=True,
        code=code,
        expires_at=_iso(expires),
        summary=summary,
        thinking_health=snapshot.thinking_health,
        message="Support code created. Share it with your advisor.",
    )


def lookup_support_bundle(code: str) -> dict[str, Any] | None:
    """Load a support bundle by code for GTK/support staff."""
    normalized = _normalize_code(code)
    if not normalized or len(normalized.replace("-", "")) != 6:
        return None
    path = _bundles_dir() / f"{normalized}.json"
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    expires_raw = data.get("expires_at") or ""
    try:
        expires = datetime.strptime(expires_raw, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=timezone.utc
        )
        if expires <= _utc_now():
            path.unlink(missing_ok=True)
            return None
    except Exception:
        return None
    if not isinstance(data, dict):
        return None
    data["code"] = normalized
    return data


def auto_fix_thinking(*, probe: bool = True) -> AutoFixResult:
    """Restore last working setup and re-probe — safe automatic recovery."""
    restore = restore_last_known_good(probe=probe)
    if not restore.ok:
        snapshot = collect_health_snapshot(probe=probe)
        message = restore.message or "Could not restore your last working setup."
        if snapshot.last_good_available:
            message = (
                "Automatic recovery did not succeed. "
                "Try again or share a support code with your advisor."
            )
        return AutoFixResult(
            ok=False,
            message=message,
            thinking_health=snapshot.thinking_health,
            restored=False,
        )

    snapshot = collect_health_snapshot(probe=probe)
    if snapshot.thinking_health == _THINKING_WORKING:
        message = "Restored your last working setup. Your Centurion is thinking normally again."
        ok = True
    else:
        message = (
            restore.message
            or "Restored your last working setup, but the thinking service still needs attention."
        )
        ok = snapshot.thinking_health != _THINKING_NEEDS_ATTENTION

    return AutoFixResult(
        ok=ok,
        message=message,
        thinking_health=snapshot.thinking_health,
        restored=True,
    )


def list_backup_thinking_services() -> list[dict[str, str]]:
    """Read-only backup thinking services from ``fallback_providers`` config."""
    config = _load_config_safe()
    try:
        from centurion_cli.fallback_config import get_fallback_chain
    except ImportError:
        return []

    entries: list[dict[str, str]] = []
    for entry in get_fallback_chain(config):
        if not isinstance(entry, dict):
            continue
        provider = str(entry.get("provider") or "").strip()
        model = str(entry.get("model") or "").strip()
        if not provider and not model:
            continue
        label = f"{model} via {provider}" if provider and model else model or provider
        entries.append({"label": label, "provider": provider, "model": model})
    return entries


def format_bundle_for_display(bundle: dict[str, Any]) -> str:
    """Plain-language support-staff summary — no secrets."""
    lines: list[str] = []
    summary = bundle.get("summary_plain")
    if isinstance(summary, str) and summary.strip():
        lines.append(summary.strip())

    snapshot = bundle.get("snapshot")
    if isinstance(snapshot, dict):
        thinking = snapshot.get("thinking_message")
        if isinstance(thinking, str) and thinking.strip() and thinking not in lines:
            lines.append(thinking.strip())
        issues = snapshot.get("issues")
        if isinstance(issues, list) and issues:
            lines.append("")
            lines.append("Issues found:")
            for issue in issues[:8]:
                if isinstance(issue, str) and issue.strip():
                    lines.append(f"• {issue.strip()}")

    dump_summary = bundle.get("dump_summary")
    if isinstance(dump_summary, dict):
        version = dump_summary.get("version")
        if version:
            lines.append("")
            lines.append(f"Centurion version: {version}")

    recent_errors = bundle.get("recent_errors")
    if isinstance(recent_errors, list) and recent_errors:
        lines.append("")
        lines.append(f"Recent errors ({len(recent_errors)} lines, redacted):")
        for line in recent_errors[-5:]:
            if isinstance(line, str) and line.strip():
                lines.append(line.strip()[:200])

    return "\n".join(lines).strip() or "Support bundle found."
