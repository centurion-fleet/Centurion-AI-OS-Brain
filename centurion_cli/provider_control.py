"""Host Provider Control Plane — canonical path for GUI/remote provider management.

Wraps :func:`centurion_cli.model_switch.switch_model`, runtime credential
resolution, lightweight health probes, and Last-Known-Good (LKG) snapshots.
All dashboard, GTK, iPhone, and remote-bridge provider mutations should go
through this module instead of writing ``config.yaml`` directly.
"""

from __future__ import annotations

import json
import logging
import os
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from centurion_constants import get_centurion_home

logger = logging.getLogger(__name__)

# Structured LLM error taxonomy (surfaced to iPhone/GTK — never raw traces).
LLM_AUTH_MISSING = "LLM_AUTH_MISSING"
LLM_AUTH_INVALID = "LLM_AUTH_INVALID"
LLM_MODEL_INVALID = "LLM_MODEL_INVALID"
LLM_RATE_LIMIT = "LLM_RATE_LIMIT"
LLM_UNAVAILABLE = "LLM_UNAVAILABLE"
LLM_CONFIG_INVALID = "LLM_CONFIG_INVALID"

_HEALTH_OK = "ok"
_HEALTH_DEGRADED = "degraded"
_HEALTH_BROKEN = "broken"


@dataclass
class ProviderStatus:
    provider: str = ""
    model: str = ""
    base_url: str = ""
    health: str = _HEALTH_BROKEN
    health_message: str = ""
    last_good_available: bool = False
    last_good: dict[str, Any] | None = None
    probe_latency_ms: int | None = None

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        if payload.get("last_good") is None:
            payload.pop("last_good", None)
        return payload


@dataclass
class ValidationResult:
    ok: bool
    provider: str = ""
    model: str = ""
    message: str = ""
    code: str = ""
    probe_latency_ms: int | None = None
    warning: str = ""

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class ApplyResult:
    ok: bool
    provider: str = ""
    model: str = ""
    message: str = ""
    code: str = ""
    warning: str = ""
    probe_latency_ms: int | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def lkg_path() -> Path:
    return get_centurion_home() / "state" / "last_good_model.json"


def load_last_known_good() -> dict[str, Any] | None:
    path = lkg_path()
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    provider = str(data.get("provider") or "").strip()
    model = str(data.get("model") or "").strip()
    if not provider or not model:
        return None
    return data


def save_last_known_good(
    *,
    provider: str,
    model: str,
    base_url: str = "",
    probe_latency_ms: int | None = None,
) -> None:
    provider = provider.strip()
    model = model.strip()
    if not provider or not model:
        return

    payload = {
        "provider": provider,
        "model": model,
        "base_url": (base_url or "").strip().rstrip("/"),
        "verified_at": int(time.time()),
    }
    if probe_latency_ms is not None:
        payload["probe_latency_ms"] = int(probe_latency_ms)

    path = lkg_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def _load_switch_context() -> tuple[str, str, str, Any, dict | None, list | None]:
    from centurion_cli.config import get_compatible_custom_providers, load_config
    from centurion_cli.runtime_provider import resolve_runtime_provider

    cfg = load_config()
    model_cfg = cfg.get("model", {})
    if isinstance(model_cfg, dict):
        current_provider = str(model_cfg.get("provider") or "")
        current_model = str(
            model_cfg.get("default", model_cfg.get("name", "")) or ""
        )
        current_base_url = str(model_cfg.get("base_url") or "")
    else:
        current_provider = ""
        current_model = str(model_cfg) if model_cfg else ""
        current_base_url = ""

    runtime = resolve_runtime_provider(requested=None)
    if not current_provider:
        current_provider = str(runtime.get("provider") or "")
    if not current_model:
        current_model = str(runtime.get("model") or "")
    if not current_base_url:
        current_base_url = str(runtime.get("base_url") or "")

    runtime_key = runtime.get("api_key", "")
    if callable(runtime_key) and not isinstance(runtime_key, str):
        current_api_key = runtime_key
    else:
        current_api_key = str(runtime_key or "")

    user_providers = cfg.get("providers") if isinstance(cfg.get("providers"), dict) else None
    custom_providers = get_compatible_custom_providers(cfg)
    return (
        current_provider,
        current_model,
        current_base_url,
        current_api_key,
        user_providers,
        custom_providers,
    )


def list_options(*, max_models: int = 50) -> dict[str, Any]:
    from centurion_cli.inventory import build_models_payload, load_picker_context

    ctx = load_picker_context()
    return build_models_payload(ctx, max_models=max_models, picker_hints=True)


def _resolve_switch(provider: str, model: str):
    from centurion_cli.model_switch import switch_model

    (
        current_provider,
        current_model,
        current_base_url,
        current_api_key,
        user_providers,
        custom_providers,
    ) = _load_switch_context()

    return switch_model(
        raw_input=model.strip(),
        current_provider=current_provider,
        current_model=current_model,
        current_base_url=current_base_url,
        current_api_key=current_api_key,
        is_global=True,
        explicit_provider=provider.strip(),
        user_providers=user_providers,
        custom_providers=custom_providers,
    )


def _persist_switch_result(result) -> None:
    from centurion_cli.config import load_config, save_config

    cfg = load_config()
    model_cfg = cfg.get("model")
    if not isinstance(model_cfg, dict):
        model_cfg = {}
        cfg["model"] = model_cfg

    model_cfg["default"] = result.new_model
    model_cfg["provider"] = result.target_provider
    if result.base_url:
        model_cfg["base_url"] = result.base_url
    else:
        model_cfg.pop("base_url", None)
    model_cfg.pop("context_length", None)
    save_config(cfg)


def probe_provider(
    *,
    provider: str,
    model: str,
    api_key: str = "",
    base_url: str = "",
    api_mode: str = "",
    timeout: float = 12.0,
) -> tuple[bool, str, int | None]:
    """Run a minimal 1-token completion probe. Returns (ok, message, latency_ms)."""
    if not api_key and not _provider_allows_keyless(provider, base_url):
        return False, "API key not configured for this thinking service.", None

    started = time.monotonic()
    try:
        import httpx

        from agent.auxiliary_client import resolve_provider_client

        client_info, resolved_model = resolve_provider_client(
            provider,
            model=model,
            explicit_base_url=base_url or None,
            explicit_api_key=api_key or None,
            raw_codex=True,
        )
        if client_info is None:
            return False, "Could not resolve credentials for this thinking service.", None

        effective_model = resolved_model or model
        effective_base = str(client_info.base_url).rstrip("/")
        key = client_info.api_key
        if callable(key) and not isinstance(key, str):
            key = key()
        headers = {"Content-Type": "application/json"}
        if key:
            headers["Authorization"] = f"Bearer {key}"

        if api_mode == "anthropic_messages" or _looks_anthropic(base_url, provider):
            url = f"{effective_base}/messages"
            body = {
                "model": effective_model,
                "max_tokens": 1,
                "messages": [{"role": "user", "content": "ping"}],
            }
            header_name = "x-api-key"
            if key:
                headers[header_name] = str(key)
                headers.pop("Authorization", None)
            resp = httpx.post(url, headers=headers, json=body, timeout=timeout)
        else:
            url = f"{effective_base}/chat/completions"
            body = {
                "model": effective_model,
                "max_tokens": 1,
                "messages": [{"role": "user", "content": "ping"}],
            }
            resp = httpx.post(url, headers=headers, json=body, timeout=timeout)

        latency_ms = int((time.monotonic() - started) * 1000)
        if resp.status_code == 200:
            return True, "", latency_ms
        if resp.status_code in {401, 403}:
            return False, "API key was rejected by the thinking service.", latency_ms
        if resp.status_code == 404:
            return False, "This model was not found for the selected thinking service.", latency_ms
        if resp.status_code == 429:
            return False, "The thinking service is rate-limited right now.", latency_ms
        if resp.status_code >= 500:
            return False, "The thinking service is temporarily unavailable.", latency_ms
        return False, f"Probe failed (HTTP {resp.status_code}).", latency_ms
    except Exception as exc:
        latency_ms = int((time.monotonic() - started) * 1000)
        logger.debug("provider probe failed: %s", exc)
        return False, "Could not reach the thinking service.", latency_ms


def _provider_allows_keyless(provider: str, base_url: str) -> bool:
    lowered = (provider or "").lower()
    if lowered in {"ollama", "lmstudio", "llamacpp", "local"}:
        return True
    if base_url and any(
        token in base_url.lower()
        for token in ("localhost", "127.0.0.1", "0.0.0.0")
    ):
        return True
    return False


def _looks_anthropic(base_url: str, provider: str) -> bool:
    blob = f"{provider} {base_url}".lower()
    return "anthropic" in blob and "openrouter" not in blob


def validate_switch(provider: str, model: str, *, probe: bool = True) -> ValidationResult:
    from centurion_cli.remote_model_catalog import is_openrouter_blocked

    provider = (provider or "").strip()
    model = (model or "").strip()
    if not provider or not model:
        return ValidationResult(
            ok=False,
            message="Provider and model are required.",
            code=LLM_CONFIG_INVALID,
        )

    if is_openrouter_blocked(provider):
        return ValidationResult(
            ok=False,
            provider=provider,
            model=model,
            message=(
                "OpenRouter and subscription remaps are not available for Centurion "
                "Remote / Sovereign BYOK. Use a direct thinking-service family."
            ),
            code=LLM_CONFIG_INVALID,
        )

    result = _resolve_switch(provider, model)
    if not result.success:
        code, message = classify_llm_error(RuntimeError(result.error_message or "switch failed"))
        return ValidationResult(
            ok=False,
            provider=provider,
            model=model,
            message=message,
            code=code,
        )

    if not probe:
        return ValidationResult(
            ok=True,
            provider=result.target_provider,
            model=result.new_model,
            message="Configuration looks valid.",
            warning=result.warning_message or "",
        )

    ok, probe_message, latency_ms = probe_provider(
        provider=result.target_provider,
        model=result.new_model,
        api_key=result.api_key,
        base_url=result.base_url,
        api_mode=result.api_mode,
    )
    if not ok:
        code, message = classify_llm_error(RuntimeError(probe_message))
        return ValidationResult(
            ok=False,
            provider=result.target_provider,
            model=result.new_model,
            message=message,
            code=code,
            probe_latency_ms=latency_ms,
            warning=result.warning_message or "",
        )

    return ValidationResult(
        ok=True,
        provider=result.target_provider,
        model=result.new_model,
        message="Thinking service validated successfully.",
        probe_latency_ms=latency_ms,
        warning=result.warning_message or "",
    )


def commit_switch_result(result, *, probe: bool = True) -> ApplyResult:
    """Persist a successful :class:`ModelSwitchResult` without re-resolving."""
    if not result.success:
        code, message = classify_llm_error(RuntimeError(result.error_message or "switch failed"))
        return ApplyResult(
            ok=False,
            provider=result.target_provider,
            model=result.new_model,
            message=message,
            code=code,
        )

    if probe:
        ok, probe_message, latency_ms = probe_provider(
            provider=result.target_provider,
            model=result.new_model,
            api_key=result.api_key,
            base_url=result.base_url,
            api_mode=result.api_mode,
        )
        if not ok:
            code, message = classify_llm_error(RuntimeError(probe_message))
            return ApplyResult(
                ok=False,
                provider=result.target_provider,
                model=result.new_model,
                message=message,
                code=code,
                probe_latency_ms=latency_ms,
            )
    else:
        latency_ms = None

    _persist_switch_result(result)
    os.environ["CENTURION_MODEL"] = result.new_model
    os.environ["CENTURION_INFERENCE_MODEL"] = result.new_model
    if result.target_provider:
        os.environ["CENTURION_INFERENCE_PROVIDER"] = result.target_provider
    save_last_known_good(
        provider=result.target_provider,
        model=result.new_model,
        base_url=result.base_url,
        probe_latency_ms=latency_ms,
    )
    return ApplyResult(
        ok=True,
        provider=result.target_provider,
        model=result.new_model,
        message="Thinking service updated.",
        warning=result.warning_message or "",
        probe_latency_ms=latency_ms,
    )


def apply_switch(provider: str, model: str, *, probe: bool = True) -> ApplyResult:
    from centurion_cli.remote_model_catalog import is_openrouter_blocked

    if is_openrouter_blocked(provider):
        return ApplyResult(
            ok=False,
            provider=provider,
            model=model,
            message=(
                "OpenRouter and subscription remaps are not available for Centurion "
                "Remote / Sovereign BYOK. Use a direct thinking-service family "
                "(OpenAI API, Anthropic, Gemini, …)."
            ),
            code=LLM_CONFIG_INVALID,
        )

    result = _resolve_switch(provider, model)
    if not result.success:
        code, message = classify_llm_error(RuntimeError(result.error_message or "switch failed"))
        return ApplyResult(
            ok=False,
            provider=provider,
            model=model,
            message=message,
            code=code,
        )

    return commit_switch_result(result, probe=probe)


def restore_last_known_good(*, probe: bool = True) -> ApplyResult:
    snapshot = load_last_known_good()
    if not snapshot:
        return ApplyResult(
            ok=False,
            message="No last working setup is saved yet.",
            code=LLM_CONFIG_INVALID,
        )
    provider = str(snapshot.get("provider") or "")
    model = str(snapshot.get("model") or "")
    return apply_switch(provider, model, probe=probe)


def get_status(*, probe: bool = True) -> ProviderStatus:
    (
        current_provider,
        current_model,
        current_base_url,
        _current_api_key,
        _user_providers,
        _custom_providers,
    ) = _load_switch_context()

    lkg = load_last_known_good()
    status = ProviderStatus(
        provider=current_provider,
        model=current_model,
        base_url=current_base_url,
        last_good_available=lkg is not None,
        last_good=lkg,
    )

    if not current_provider or not current_model:
        status.health = _HEALTH_BROKEN
        status.health_message = "No thinking service is configured yet."
        return status

    if not probe:
        status.health = _HEALTH_OK
        status.health_message = "Configured (not probed)."
        return status

    ok, message, latency_ms = probe_provider(
        provider=current_provider,
        model=current_model,
        base_url=current_base_url,
    )
    status.probe_latency_ms = latency_ms
    if ok:
        status.health = _HEALTH_OK
        status.health_message = "Thinking service is reachable."
        save_last_known_good(
            provider=current_provider,
            model=current_model,
            base_url=current_base_url,
            probe_latency_ms=latency_ms,
        )
        return status

    status.health = _HEALTH_BROKEN
    status.health_message = message or "Thinking service is unreachable."
    return status


def classify_llm_error(error: BaseException) -> tuple[str, str]:
    """Map an exception to (code, user-facing message)."""
    message = str(error) or error.__class__.__name__
    lowered = message.lower()

    if any(
        token in lowered
        for token in (
            "no api key",
            "api key not",
            "not configured",
            "no llm provider configured",
            "environment variable",
            "missing api key",
            "credential",
        )
    ):
        return LLM_AUTH_MISSING, (
            "Your Centurion needs an API key for its thinking service. "
            "Add one on your Centurion, then try again."
        )

    if any(
        token in lowered
        for token in (
            "invalid api key",
            "unauthorized",
            "authentication",
            "401",
            "403",
            "rejected",
        )
    ):
        return LLM_AUTH_INVALID, (
            "The API key for this thinking service was rejected. "
            "Update the key on your Centurion or switch to another service."
        )

    if any(
        token in lowered
        for token in (
            "model not found",
            "invalid model",
            "unknown model",
            "404",
            "non-agentic",
        )
    ):
        return LLM_MODEL_INVALID, (
            "This model is not available for your thinking service. "
            "Pick a different model and try again."
        )

    if any(token in lowered for token in ("rate limit", "429", "too many requests")):
        return LLM_RATE_LIMIT, (
            "The thinking service is busy right now. Wait a moment or switch services."
        )

    if any(
        token in lowered
        for token in (
            "timeout",
            "timed out",
            "unavailable",
            "502",
            "503",
            "504",
            "connection",
            "could not reach",
        )
    ):
        return LLM_UNAVAILABLE, (
            "Your Centurion could not reach its thinking service. "
            "Try again or restore your last working setup."
        )

    if any(
        token in lowered
        for token in ("config", "yaml", "unknown provider", "invalid provider")
    ):
        return LLM_CONFIG_INVALID, (
            "Your Centurion's thinking-service settings need attention. "
            "Open recovery to fix them."
        )

    try:
        from agent.error_classifier import FailoverReason, classify_api_error

        classified = classify_api_error(error)
        reason = classified.reason
        if reason in {FailoverReason.auth, FailoverReason.auth_permanent}:
            return LLM_AUTH_INVALID, (
                "The API key for this thinking service was rejected. "
                "Update the key on your Centurion or switch to another service."
            )
        if reason == FailoverReason.model_not_found:
            return LLM_MODEL_INVALID, (
                "This model is not available for your thinking service. "
                "Pick a different model and try again."
            )
        if reason == FailoverReason.rate_limit:
            return LLM_RATE_LIMIT, (
                "The thinking service is busy right now. Wait a moment or switch services."
            )
        if reason in {
            FailoverReason.timeout,
            FailoverReason.server_error,
            FailoverReason.overloaded,
        }:
            return LLM_UNAVAILABLE, (
                "Your Centurion could not reach its thinking service. "
                "Try again or restore your last working setup."
            )
    except Exception:
        pass

    return LLM_UNAVAILABLE, (
        "Your Centurion could not complete that request. "
        "Try again or restore your last working setup."
    )


def record_successful_turn(
    *,
    provider: str | None = None,
    model: str | None = None,
    base_url: str = "",
) -> None:
    """Persist LKG after a successful chat turn (best-effort).

    Must never raise — a turn that already produced a response should not be
    turned into an error just because this bookkeeping step failed (e.g. no
    provider auto-detects cleanly in a fresh/minimal environment).
    """
    try:
        if provider and model:
            save_last_known_good(provider=provider, model=model, base_url=base_url)
            return
        status = get_status(probe=False)
        if status.provider and status.model:
            save_last_known_good(
                provider=status.provider,
                model=status.model,
                base_url=status.base_url,
            )
    except Exception as exc:
        logger.debug("record_successful_turn failed (best-effort, ignored): %s", exc)


# ---------------------------------------------------------------------------
# Remote catalog (iPhone) — direct APIs only, no OpenRouter
# ---------------------------------------------------------------------------


def _current_connector_id() -> str | None:
    from centurion_cli.remote_model_catalog import iter_catalog

    try:
        (
            current_provider,
            current_model,
            _current_base_url,
            _current_api_key,
            _user_providers,
            _custom_providers,
        ) = _load_switch_context()
    except Exception as exc:
        # No provider configured/auto-detected yet — the catalog should still
        # list every connector, just with none marked as "active".
        logger.debug("_current_connector_id: could not resolve active provider: %s", exc)
        return None
    provider = (current_provider or "").strip().lower()
    model = (current_model or "").strip().lower()
    for entry in iter_catalog():
        if entry.category != "text":
            continue
        if entry.provider.lower() == provider and entry.model.lower() == model:
            return entry.id
    return None


def list_remote_options(*, probe: bool = False) -> dict[str, Any]:
    from centurion_cli.remote_model_catalog import (
        build_remote_option_row,
        is_openrouter_blocked,
        iter_catalog,
    )

    active_id = _current_connector_id()
    text_models: list[dict[str, Any]] = []
    creative_models: list[dict[str, Any]] = []

    for entry in iter_catalog():
        if is_openrouter_blocked(entry.provider):
            continue
        healthy: bool | None = None
        if probe and entry.category == "text" and _key_configured(entry.key_env):
            ok, _message, _latency = probe_provider(
                provider=entry.provider,
                model=entry.model,
                base_url=entry.base_url,
            )
            healthy = ok
        row = build_remote_option_row(
            entry,
            active=(entry.id == active_id),
            healthy=healthy,
        )
        if entry.category == "creative":
            creative_models.append(row)
        else:
            text_models.append(row)

    return {
        "text_models": text_models,
        "creative_models": creative_models,
        "active_connector_id": active_id,
        "routing_mode": get_routing_mode(),
    }


def _key_configured(key_env: str) -> bool:
    if bool((os.environ.get(key_env) or "").strip()):
        return True
    try:
        from centurion_cli.config import load_env

        return bool((load_env().get(key_env) or "").strip())
    except Exception:
        return False


def apply_remote_switch(connector_id: str, *, probe: bool = True) -> ApplyResult:
    from centurion_cli.remote_model_catalog import get_connector, is_openrouter_blocked

    connector = get_connector(connector_id)
    if connector is None:
        return ApplyResult(
            ok=False,
            message="Unknown thinking service.",
            code=LLM_CONFIG_INVALID,
        )
    if is_openrouter_blocked(connector.provider):
        return ApplyResult(
            ok=False,
            message="OpenRouter is not available from Centurion Remote.",
            code=LLM_CONFIG_INVALID,
        )
    if connector.category == "creative":
        return _apply_creative_connector(connector)
    return apply_switch(connector.provider, connector.model, probe=probe)


def _apply_creative_connector(connector) -> ApplyResult:
    from centurion_cli.config import load_config, save_config

    cfg = load_config()
    kind = connector.creative_kind
    if kind == "image_gen":
        section = cfg.setdefault("image_gen", {})
        if not isinstance(section, dict):
            section = {}
            cfg["image_gen"] = section
        section["provider"] = connector.provider
        section["model"] = connector.model
        provider_section = section.setdefault(connector.provider, {})
        if isinstance(provider_section, dict):
            provider_section["model"] = connector.model
    elif kind == "video_gen":
        section = cfg.setdefault("video_gen", {})
        if not isinstance(section, dict):
            section = {}
            cfg["video_gen"] = section
        section["provider"] = connector.provider
        section["model"] = connector.model
        provider_section = section.setdefault(connector.provider, {})
        if isinstance(provider_section, dict):
            provider_section["model"] = connector.model
    elif kind == "tts":
        section = cfg.setdefault("tts", {})
        if not isinstance(section, dict):
            section = {}
            cfg["tts"] = section
        section["provider"] = connector.provider
        provider_section = section.setdefault(connector.provider, {})
        if isinstance(provider_section, dict):
            provider_section["model_id"] = connector.model
    else:
        return ApplyResult(
            ok=False,
            message="This creative connector is not supported yet.",
            code=LLM_CONFIG_INVALID,
        )

    save_config(cfg)
    return ApplyResult(
        ok=True,
        provider=connector.provider,
        model=connector.model,
        message=f"Creative default set to {connector.display_name}.",
    )


def save_remote_api_key(connector_id: str, key: str) -> dict[str, Any]:
    from centurion_cli.config import is_managed, save_env_value
    from centurion_cli.remote_model_catalog import get_connector

    connector = get_connector(connector_id)
    if connector is None:
        return {"ok": False, "message": "Unknown thinking service."}
    value = (key or "").strip()
    if not value:
        return {"ok": False, "message": "Access code is required."}
    if is_managed():
        return {
            "ok": False,
            "message": (
                "This Centurion install is managed by a package manager. "
                "Set access codes through your package config, not from Remote."
            ),
        }
    save_env_value(connector.key_env, value)
    os.environ[connector.key_env] = value
    return {
        "ok": True,
        "connector_id": connector.id,
        "configured": True,
        "message": f"Saved access code for {connector.display_name} on your Centurion.",
    }


def get_routing_mode() -> str:
    from centurion_cli.config import load_config

    cfg = load_config()
    remote_cfg = cfg.get("remote") if isinstance(cfg.get("remote"), dict) else {}
    mode = str(remote_cfg.get("routing_mode") or "manual").strip().lower()
    return mode if mode in {"manual", "phoenix"} else "manual"


def set_routing_mode(mode: str) -> dict[str, Any]:
    from centurion_cli.config import load_config, save_config

    normalized = (mode or "manual").strip().lower()
    if normalized not in {"manual", "phoenix"}:
        return {"ok": False, "message": "Routing mode must be manual or phoenix."}
    cfg = load_config()
    remote_cfg = cfg.setdefault("remote", {})
    if not isinstance(remote_cfg, dict):
        remote_cfg = {}
        cfg["remote"] = remote_cfg
    remote_cfg["routing_mode"] = normalized
    save_config(cfg)
    return {"ok": True, "routing_mode": normalized}
