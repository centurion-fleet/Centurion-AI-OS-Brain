"""Local stdio bridge from the native Linux remote service to Centurion.

The bridge deliberately has no network listener. ``centurion-remote`` owns the
encrypted LAN boundary and invokes this module with a JSON request on stdin.
Keeping the Python process behind stdio prevents the full dashboard/admin API
from being exposed to the local network.
"""

from __future__ import annotations

import argparse
import json
import logging
import re
import sys
from collections.abc import Callable
from types import SimpleNamespace
from typing import Any

from centurion_cli.provider_control import (
    LLM_AUTH_INVALID,
    LLM_AUTH_MISSING,
    LLM_CONFIG_INVALID,
    LLM_MODEL_INVALID,
    LLM_UNAVAILABLE,
    apply_remote_switch,
    apply_switch,
    classify_llm_error,
    get_routing_mode,
    get_status,
    list_options,
    list_remote_options,
    load_last_known_good,
    record_successful_turn,
    restore_last_known_good,
    save_remote_api_key,
    set_routing_mode,
    validate_switch,
)
from centurion_cli import support_control

logger = logging.getLogger(__name__)


def handle_request(
    request: dict[str, Any],
    *,
    run_agent: Callable[[str], str] | None = None,
) -> dict[str, Any]:
    """Run one native-remote request and return a JSON-safe response."""
    request_id = str(request.get("id") or "")
    action = str(request.get("action") or "chat").strip().lower()

    if action == "chat":
        return _handle_chat(request, request_id=request_id, run_agent=run_agent)
    if action == "provider_status":
        return _handle_provider_status(request_id)
    if action == "provider_options":
        return _handle_provider_options(request_id)
    if action == "provider_validate":
        return _handle_provider_validate(request, request_id)
    if action == "provider_apply":
        return _handle_provider_apply(request, request_id)
    if action == "provider_restore":
        return _handle_provider_restore(request_id)
    if action == "health_check":
        return _handle_health_check(request_id)
    if action == "bridge_ping":
        # Cheap handshake for Brain — no support probe, just version.
        from centurion_cli import __version__ as _bridge_version

        return {
            "id": request_id,
            "ok": True,
            "action": "bridge_ping",
            "version": _bridge_version,
        }
    if action == "settings_snapshot":
        return _handle_settings_snapshot(request, request_id)
    if action == "tool_env_get":
        return _handle_tool_env_get(request, request_id)
    if action == "tool_env_set":
        return _handle_tool_env_set(request, request_id)
    if action == "support_bundle":
        return _handle_support_bundle(request_id)
    if action == "support_auto_fix":
        return _handle_support_auto_fix(request_id)
    if action == "swarm_snapshot":
        return _handle_swarm_snapshot(request, request_id)
    if action == "swarm_connect":
        return _handle_swarm_connect(request, request_id)
    if action == "swarm_invite":
        return _handle_swarm_invite(request, request_id)
    if action == "swarm_resolve_signal":
        return _handle_swarm_resolve_signal(request, request_id)
    if action == "swarm_create_board":
        return _handle_swarm_create_board(request, request_id)
    if action == "beneficiary_snapshot":
        return _handle_beneficiary_snapshot(request_id)
    if action == "beneficiary_set_family_member":
        return _handle_beneficiary_set_family_member(request, request_id)
    if action == "beneficiary_submit_colleague":
        return _handle_beneficiary_submit_colleague(request, request_id)
    if action == "remote_model_catalog":
        return _handle_remote_model_catalog(request_id)
    if action == "remote_model_apply":
        return _handle_remote_model_apply(request, request_id)
    if action == "remote_model_save_key":
        return _handle_remote_model_save_key(request, request_id)
    if action == "remote_routing_mode":
        return _handle_remote_routing_mode(request, request_id)
    if action == "telegram_import_bundle":
        return _handle_telegram_import_bundle(request, request_id)
    if action == "telegram_import_preview":
        return _handle_telegram_import_preview(request_id)
    if action == "oversight_get":
        return _handle_oversight_get(request_id)
    if action == "oversight_put":
        return _handle_oversight_put(request, request_id)
    if action == "soul_get":
        return _handle_soul_get(request_id)
    if action == "soul_put":
        return _handle_soul_put(request, request_id)
    if action == "mission_get":
        return _handle_mission_get(request_id)
    if action == "mission_put":
        return _handle_mission_put(request, request_id)
    if action == "life_subjects_list":
        return _handle_life_subjects_list(request_id)
    if action == "life_subject_put":
        return _handle_life_subject_put(request, request_id)
    if action == "life_subject_delete":
        return _handle_life_subject_delete(request, request_id)
    if action == "life_subjects_reorder":
        return _handle_life_subjects_reorder(request, request_id)
    if action == "life_stack_get":
        return _handle_life_stack_get(request_id)
    if action == "deck_snapshot" or action == "life_deck_snapshot":
        return _handle_life_deck_snapshot(request, request_id)
    if action == "life_stack_set_primary":
        return _handle_life_stack_set_primary(request, request_id)
    if action == "life_stack_reorder":
        return _handle_life_stack_reorder(request, request_id)
    if action == "life_missions_list":
        return _handle_life_missions_list(request_id)
    if action == "life_mission_get":
        return _handle_life_mission_get(request, request_id)
    if action == "life_mission_put":
        return _handle_life_mission_put(request, request_id)
    if action == "life_target_put":
        return _handle_life_target_put(request, request_id)
    if action == "life_focus_set":
        return _handle_life_focus_set(request, request_id)
    if action == "life_sequence_validate":
        return _handle_life_sequence_validate(request, request_id)
    if action == "life_dreams_list":
        return _handle_life_dreams_list(request, request_id)
    if action == "life_dream_put":
        return _handle_life_dream_put(request, request_id)
    if action == "life_dream_delete":
        return _handle_life_dream_delete(request, request_id)
    if action == "life_dream_promote":
        return _handle_life_dream_promote(request, request_id)
    if action == "life_decisions_list":
        return _handle_life_decisions_list(request, request_id)
    if action == "life_decision_log":
        return _handle_life_decision_log(request, request_id)
    if action == "life_documents_list":
        return _handle_life_documents_list(request, request_id)
    if action == "life_documents_search":
        return _handle_life_documents_search(request, request_id)
    if action == "life_document_get":
        return _handle_life_document_get(request, request_id)
    if action == "life_document_put":
        return _handle_life_document_put(request, request_id)
    if action == "life_document_assign":
        return _handle_life_document_assign(request, request_id)
    if action == "life_documents_import_scan":
        return _handle_life_documents_import_scan(request, request_id)
    if action == "life_thoughts_list":
        return _handle_life_thoughts_list(request, request_id)
    if action == "life_thought_post":
        return _handle_life_thought_post(request, request_id)
    if action == "life_context_resolve":
        return _handle_life_context_resolve(request, request_id)
    if action == "life_context_inject":
        return _handle_life_context_inject(request, request_id)
    if action == "life_snapshot":
        return _handle_life_snapshot(request, request_id)
    if action == "plans_list":
        return _handle_plans_list(request, request_id)
    if action == "plan_get":
        return _handle_plan_get(request, request_id)
    if action == "plan_put":
        return _handle_plan_put(request, request_id)
    if action == "plan_decide":
        return _handle_plan_decide(request, request_id)
    if action == "plan_share":
        return _handle_plan_share(request, request_id)
    if action == "plan_comment":
        return _handle_plan_comment(request, request_id)
    if action == "plan_templates_list":
        return _handle_plan_templates_list(request_id)
    if action == "plan_template_instantiate":
        return _handle_plan_template_instantiate(request, request_id)
    if action == "plan_save_template":
        return _handle_plan_save_template(request, request_id)
    if action == "memory_horizon_snapshot":
        return _handle_memory_horizon_snapshot(request_id)
    if action == "gateway_status":
        return _handle_gateway_status(request_id)
    if action == "gateway_start":
        return _handle_gateway_lifecycle(request_id, "start")
    if action == "gateway_stop":
        return _handle_gateway_lifecycle(request_id, "stop")
    if action == "gateway_restart":
        return _handle_gateway_lifecycle(request_id, "restart")
    if action == "gateway_platform_set":
        return _handle_gateway_platform_set(request, request_id)
    if action == "session_list":
        return _handle_session_list(request, request_id)
    if action == "session_new":
        return _handle_session_new(request, request_id)
    if action == "session_end_continuity":
        return _handle_session_end_continuity(request, request_id)
    if action == "session_resume":
        return _handle_session_resume(request, request_id)
    if action == "session_history":
        return _handle_session_history(request, request_id)
    if action == "session_rename":
        return _handle_session_rename(request, request_id)
    if action == "session_delete":
        return _handle_session_delete(request, request_id)
    if action == "approval_respond":
        return _handle_approval_respond(request, request_id)
    if action == "license_status":
        return _handle_license_status(request_id)
    if action == "license_activate":
        return _handle_license_activate(request, request_id)
    if action == "license_redeem":
        return _handle_license_redeem(request, request_id)
    if action == "license_fingerprint":
        return _handle_license_fingerprint(request_id)
    if action == "fleet_status":
        return _handle_fleet_status(request_id)
    if action == "fleet_ping":
        return _handle_fleet_ping(request, request_id)
    if action == "fleet_peer_put":
        return _handle_fleet_peer_put(request, request_id)
    if action == "plugin_list":
        return _handle_plugin_list(request_id)
    if action == "tools_skills_snapshot":
        return _handle_tools_skills_snapshot(request_id)
    if action == "ops_glance":
        return _handle_ops_glance(request_id)
    if action == "client_plugin_cards":
        return _handle_client_plugin_cards(request_id)

    msg = (
        f"Unsupported bridge action: {action}. "
        "Update and restart Sovereign AI Brain so the bridge matches this Focus deck."
    )
    return {
        "id": request_id,
        "ok": False,
        "action": action,
        "code": "UNSUPPORTED_ACTION",
        "error": msg,
        "message": msg,
    }


def _handle_chat(
    request: dict[str, Any],
    *,
    request_id: str,
    run_agent: Callable[..., str] | None,
) -> dict[str, Any]:
    text = request.get("text")
    if not isinstance(text, str) or not text.strip():
        return {
            "id": request_id,
            "ok": False,
            "action": "chat",
            "code": "INVALID_REQUEST",
            "error": "Message text is required.",
            "message": "Message text is required.",
            "retryable": False,
        }

    # Product license gate — same rules as CLI/gateway (session boundary).
    try:
        from centurion.license.enforcement import (
            EnforcementMode,
            gate_agent_turn,
            locked_user_message,
        )

        decision = gate_agent_turn()
        if decision.mode in {EnforcementMode.LOCKED, EnforcementMode.RESTRICTED}:
            msg = locked_user_message(decision) or decision.message
            return {
                "id": request_id,
                "ok": False,
                "action": "chat",
                "code": "LICENSE_BLOCKED",
                "error": msg,
                "message": msg,
                "license_mode": decision.mode.value,
                "retryable": False,
            }
    except Exception:
        pass

    session_id = str(request.get("session_id") or "").strip() or None
    using_default_agent = run_agent is None
    if run_agent is None:
        run_agent = _run_agent_quiet
    if using_default_agent and not session_id:
        try:
            session_id = _ensure_remote_session()
        except Exception:
            session_id = None

    # Optional life-context inject (Brain Mission Discuss) — one round-trip
    # with chat instead of a separate bridge spawn before Send.
    chat_text = text.strip()
    life_inject = request.get("life_inject")
    if isinstance(life_inject, dict):
        try:
            from centurion_cli.life_missions import inject_context

            message = str(life_inject.get("message") or chat_text)
            current_view = life_inject.get("current_view")
            if not isinstance(current_view, dict):
                current_view = {
                    "mission_id": life_inject.get("mission_id"),
                    "target_id": life_inject.get("target_id"),
                    "subject_id": life_inject.get("subject_id"),
                }
            if life_inject.get("document_ids") is not None:
                current_view = dict(current_view)
                current_view["document_ids"] = life_inject.get("document_ids")
            result = inject_context(message, current_view=current_view)
            block = str(result.get("formatted_for_ai") or "").strip()
            if block:
                marker = "Mission context:\n"
                if marker not in chat_text:
                    # Prefer inserting before "User message:" when Brain framed the text.
                    needle = "User message:\n"
                    if needle in chat_text:
                        chat_text = chat_text.replace(
                            needle, f"{marker}{block}\n\n{needle}", 1
                        )
                    else:
                        chat_text = f"{marker}{block}\n\n{chat_text}"
        except Exception:
            pass

    # Optional per-turn skill injection (Brain Research mode, etc.).
    # Loaded into the *user* message so prompt caching stays intact.
    skills = request.get("skills")
    if isinstance(skills, list) and skills:
        try:
            from agent.skill_commands import build_skill_invocation_message

            blocks: list[str] = []
            for raw in skills:
                name = str(raw or "").strip().lstrip("/")
                if not name:
                    continue
                msg = build_skill_invocation_message(f"/{name}", user_instruction="")
                if msg:
                    blocks.append(msg)
            if blocks:
                chat_text = "\n\n".join(blocks) + "\n\n" + chat_text
        except Exception:
            pass

    routed_connector_id = None
    routed_display_name = ""
    try:
        if get_routing_mode() == "phoenix":
            from centurion_cli.phoenix_router import describe_route, resolve as phoenix_resolve

            routed_connector_id = phoenix_resolve(chat_text, categories={"text"})
            if routed_connector_id:
                switch = apply_remote_switch(routed_connector_id, probe=False)
                if switch.ok:
                    routed_display_name = describe_route(routed_connector_id)
    except Exception:
        routed_connector_id = None

    try:
        # Prefer session-aware signature; fall back for test doubles.
        try:
            response = run_agent(
                chat_text,
                session_id=session_id,
                request_id=request_id,
            )
        except TypeError:
            response = run_agent(chat_text)
        record_successful_turn()
        payload = {
            "id": request_id,
            "ok": True,
            "action": "chat",
            "text": response or "",
        }
        if session_id:
            payload["session_id"] = session_id
        if routed_connector_id:
            payload["routed_connector_id"] = routed_connector_id
            payload["routed_display_name"] = routed_display_name
        return payload
    except Exception as exc:
        return _error_response(
            request_id,
            action="chat",
            exc=exc,
            retryable=True,
            attempt_recovery=True,
            retry_text=chat_text,
            run_agent=run_agent,
        )


def _handle_provider_status(request_id: str) -> dict[str, Any]:
    try:
        status = get_status(probe=True)
        payload = status.to_dict()
        # Keep the flag but omit the snapshot — remote frames stay small on iPhone.
        payload.pop("last_good", None)
        return {
            "id": request_id,
            "ok": True,
            "action": "provider_status",
            "status": payload,
        }
    except Exception as exc:
        return _error_response(request_id, action="provider_status", exc=exc)


def _handle_settings_snapshot(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    """One-shot Settings fill: thinking, backups, soul, oversight, horizon, etc."""
    try:
        from centurion_cli.life_missions import get_data_version

        skip_probe = request.get("skip_probe", True)
        if isinstance(skip_probe, str):
            skip_probe = skip_probe.strip().lower() in {"1", "true", "yes", "on"}
        else:
            skip_probe = bool(skip_probe)

        thinking = get_status(probe=not skip_probe).to_dict()
        thinking.pop("last_good", None)

        backups = support_control.list_backup_thinking_services()

        soul_resp = _handle_soul_get(request_id)
        soul = soul_resp.get("soul") if soul_resp.get("ok") else None

        oversight_resp = _handle_oversight_get(request_id)
        oversight = (
            oversight_resp.get("oversight") if oversight_resp.get("ok") else None
        )

        horizon_resp = _handle_memory_horizon_snapshot(request_id)
        horizon = horizon_resp.get("snapshot") if horizon_resp.get("ok") else None

        license_resp = _handle_license_status(request_id)
        license_payload: dict[str, Any] = {}
        if license_resp.get("ok") and isinstance(license_resp.get("license"), dict):
            license_payload = dict(license_resp["license"])
        # Desktop SettingsFill visibility: /status/enabled or top-level enabled.
        license_enabled = False
        try:
            from centurion.license.enforcement import enforcement_enabled

            license_enabled = bool(enforcement_enabled())
        except Exception:
            pass
        # Prefer config ``license.enabled`` for row visibility (not just enforcement).
        try:
            from centurion_cli.config import load_config
            from utils import is_truthy_value

            cfg = load_config() or {}
            lic = cfg.get("license") if isinstance(cfg.get("license"), dict) else {}
            if lic:
                license_enabled = is_truthy_value(lic.get("enabled"), default=False)
        except Exception:
            pass
        license_payload["enabled"] = license_enabled

        beneficiary_resp = _handle_beneficiary_snapshot(request_id)
        beneficiary: dict[str, Any] = {}
        if beneficiary_resp.get("ok") and isinstance(
            beneficiary_resp.get("snapshot"), dict
        ):
            beneficiary = dict(beneficiary_resp["snapshot"])
        # Visibility helpers expected by Desktop SettingsFill.
        if "enabled" not in beneficiary and "program_active" not in beneficiary:
            cycle = beneficiary.get("current_cycle") or {}
            family = str(
                cycle.get("family_beneficiary_first_name")
                or beneficiary.get("family_beneficiary_first_name")
                or ""
            ).strip()
            beneficiary["enabled"] = bool(family)
            beneficiary["program_active"] = bool(family)
            if family and "family_beneficiary_first_name" not in beneficiary:
                beneficiary["family_beneficiary_first_name"] = family

        firecrawl = _tool_env_status_payload("FIRECRAWL_API_KEY")

        return {
            "id": request_id,
            "ok": True,
            "action": "settings_snapshot",
            "thinking": thinking,
            "backups": backups,
            "soul": soul,
            "oversight": oversight,
            "horizon": horizon,
            "license": license_payload,
            "enabled": license_enabled,
            "status": {"enabled": license_enabled},
            "beneficiary": beneficiary,
            "firecrawl": firecrawl,
            "data_version": get_data_version(),
        }
    except Exception as exc:
        return _error_response(request_id, action="settings_snapshot", exc=exc)


# Research / tool keys the Brain Settings UI may read or write.
_TOOL_ENV_ALLOWLIST = frozenset({"FIRECRAWL_API_KEY"})
_FIRECRAWL_KEY_URL = "https://www.firecrawl.dev/"


def _tool_env_status_payload(key: str) -> dict[str, Any]:
    """Status for a tool env key — never returns the raw secret."""
    from centurion_cli.config import OPTIONAL_ENV_VARS, get_env_value

    meta = OPTIONAL_ENV_VARS.get(key) if isinstance(OPTIONAL_ENV_VARS, dict) else None
    meta = meta if isinstance(meta, dict) else {}
    raw = get_env_value(key) or ""
    configured = bool(str(raw).strip())
    url = str(meta.get("url") or "").strip() or (
        _FIRECRAWL_KEY_URL if key == "FIRECRAWL_API_KEY" else ""
    )
    description = str(meta.get("description") or "").strip()
    prompt = str(meta.get("prompt") or key).strip()
    return {
        "key": key,
        "configured": configured,
        "url": url,
        "description": description,
        "prompt": prompt,
    }


def _handle_tool_env_get(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    try:
        key = str(request.get("key") or "").strip()
        if key not in _TOOL_ENV_ALLOWLIST:
            return {
                "id": request_id,
                "ok": False,
                "action": "tool_env_get",
                "error": f"Unsupported tool env key: {key or '(empty)'}",
                "message": f"Unsupported tool env key: {key or '(empty)'}",
            }
        payload = _tool_env_status_payload(key)
        return {
            "id": request_id,
            "ok": True,
            "action": "tool_env_get",
            **payload,
        }
    except Exception as exc:
        return _error_response(request_id, action="tool_env_get", exc=exc)


def _handle_tool_env_set(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    try:
        from centurion_cli.config import save_env_value

        key = str(request.get("key") or "").strip()
        if key not in _TOOL_ENV_ALLOWLIST:
            return {
                "id": request_id,
                "ok": False,
                "action": "tool_env_set",
                "error": f"Unsupported tool env key: {key or '(empty)'}",
                "message": f"Unsupported tool env key: {key or '(empty)'}",
            }
        value = str(request.get("value") or request.get("api_key") or "")
        value = value.strip()
        if not value:
            return {
                "id": request_id,
                "ok": False,
                "action": "tool_env_set",
                "error": "API key is required",
                "message": "API key is required",
            }
        save_env_value(key, value)
        payload = _tool_env_status_payload(key)
        return {
            "id": request_id,
            "ok": True,
            "action": "tool_env_set",
            **payload,
        }
    except Exception as exc:
        return _error_response(request_id, action="tool_env_set", exc=exc)


def _handle_provider_options(request_id: str) -> dict[str, Any]:
    try:
        options = list_options()
        return {
            "id": request_id,
            "ok": True,
            "action": "provider_options",
            "options": options,
        }
    except Exception as exc:
        return _error_response(request_id, action="provider_options", exc=exc)


def _handle_provider_validate(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    provider = str(request.get("provider") or "").strip()
    model = str(request.get("model") or "").strip()
    try:
        result = validate_switch(provider, model, probe=True)
        payload = {
            "id": request_id,
            "ok": result.ok,
            "action": "provider_validate",
            "result": result.to_dict(),
        }
        if not result.ok:
            payload["code"] = result.code or LLM_UNAVAILABLE
            payload["error"] = result.message
            payload["message"] = result.message
            payload["retryable"] = result.code in {"LLM_RATE_LIMIT", "LLM_UNAVAILABLE"}
        return payload
    except Exception as exc:
        return _error_response(request_id, action="provider_validate", exc=exc)


def _handle_provider_apply(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    provider = str(request.get("provider") or "").strip()
    model = str(request.get("model") or "").strip()
    try:
        result = apply_switch(provider, model, probe=True)
        payload = {
            "id": request_id,
            "ok": result.ok,
            "action": "provider_apply",
            "result": result.to_dict(),
        }
        if not result.ok:
            payload["code"] = result.code or LLM_UNAVAILABLE
            payload["error"] = result.message
            payload["message"] = result.message
            payload["retryable"] = result.code in {"LLM_RATE_LIMIT", "LLM_UNAVAILABLE"}
        return payload
    except Exception as exc:
        return _error_response(request_id, action="provider_apply", exc=exc)


def _handle_provider_restore(request_id: str) -> dict[str, Any]:
    try:
        result = restore_last_known_good(probe=True)
        payload = {
            "id": request_id,
            "ok": result.ok,
            "action": "provider_restore",
            "result": result.to_dict(),
            "restored": result.ok,
        }
        if not result.ok:
            payload["code"] = result.code or LLM_UNAVAILABLE
            payload["error"] = result.message
            payload["message"] = result.message
            payload["retryable"] = False
        elif load_last_known_good():
            payload["message"] = "Restored your last working setup."
        return payload
    except Exception as exc:
        return _error_response(request_id, action="provider_restore", exc=exc)


def _handle_health_check(request_id: str) -> dict[str, Any]:
    try:
        snapshot = support_control.collect_health_snapshot(probe=True)
        return {
            "id": request_id,
            "ok": True,
            "action": "health_check",
            "snapshot": snapshot.to_dict(),
            "summary": snapshot.thinking_message,
            "thinking_health": snapshot.thinking_health,
        }
    except Exception as exc:
        return _error_response(request_id, action="health_check", exc=exc)


def _handle_support_bundle(request_id: str) -> dict[str, Any]:
    try:
        result = support_control.create_support_bundle(probe=True)
        payload = {
            "id": request_id,
            "ok": result.ok,
            "action": "support_bundle",
            "code": result.code,
            "expires_at": result.expires_at,
            "summary": result.summary,
            "thinking_health": result.thinking_health,
            "message": result.message,
        }
        if not result.ok:
            payload["error"] = result.message
        return payload
    except Exception as exc:
        return _error_response(request_id, action="support_bundle", exc=exc)


def _handle_support_auto_fix(request_id: str) -> dict[str, Any]:
    try:
        result = support_control.auto_fix_thinking(probe=True)
        return {
            "id": request_id,
            "ok": result.ok,
            "action": "support_auto_fix",
            "message": result.message,
            "thinking_health": result.thinking_health,
            "restored": result.restored,
        }
    except Exception as exc:
        return _error_response(request_id, action="support_auto_fix", exc=exc)


def _handle_swarm_snapshot(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.swarm_state import get_swarm_snapshot

        snapshot = get_swarm_snapshot(since=request.get("since"))
        try:
            from centurion_cli.life_missions import snapshot_extras

            extras = snapshot_extras(since=request.get("since"))
            if isinstance(snapshot, dict):
                snapshot = {**snapshot, "life": extras}
        except Exception:
            pass
        return {
            "id": request_id,
            "ok": True,
            "action": "swarm_snapshot",
            "snapshot": snapshot,
        }
    except Exception as exc:
        return _error_response(request_id, action="swarm_snapshot", exc=exc)


def _handle_swarm_connect(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    """Portal Mission Control connect is frozen — Life Missions are local."""
    del request
    msg = (
        "Portal Mission Control connect is frozen on this Brain. "
        "Life Missions use life.db (life_missions). "
        "Local collaboration boards: create a board without a portal token."
    )
    return {
        "id": request_id,
        "ok": False,
        "action": "swarm_connect",
        "code": "MC_FROZEN",
        "error": msg,
        "message": msg,
        "retryable": False,
    }


def _handle_swarm_invite(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    """Portal Mission Control invite is frozen."""
    del request
    msg = (
        "Portal Mission Control invites are frozen on this Brain. "
        "Use local collaboration boards; Life Missions stay offline in life.db."
    )
    return {
        "id": request_id,
        "ok": False,
        "action": "swarm_invite",
        "code": "MC_FROZEN",
        "error": msg,
        "message": msg,
        "retryable": False,
    }


def _handle_swarm_resolve_signal(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.swarm_state import resolve_signal

        signal_id = str(request.get("signal_id") or "").strip()
        choice_note = str(request.get("choice_note") or "").strip()
        result = resolve_signal(signal_id, choice_note=choice_note)
        if result.get("ok"):
            signal_obj = result.get("signal") if isinstance(result.get("signal"), dict) else {}
            mission_ref = result.get("mission_id") or signal_obj.get("mission_id")
            _record_life_decision(
                title=f"Collaboration choice · {signal_id[:8] or 'signal'}",
                chosen="resolved",
                human_said=choice_note,
                context=f"swarm_resolve_signal:{signal_id}",
                options=["resolve"],
                mission_id=str(mission_ref).strip() if mission_ref else None,
            )
        return {
            "id": request_id,
            "ok": bool(result.get("ok")),
            "action": "swarm_resolve_signal",
            "message": result.get("message") or result.get("error"),
            "result": result,
        }
    except Exception as exc:
        return _error_response(request_id, action="swarm_resolve_signal", exc=exc)


def _handle_swarm_create_board(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.swarm_state import create_collaboration_board

        name = str(request.get("name") or "").strip()
        objective = str(request.get("objective") or "").strip()
        mission_id = str(request.get("mission_id") or "").strip() or None
        result = create_collaboration_board(
            name=name,
            objective=objective,
            mission_id=mission_id,
        )
        return {
            "id": request_id,
            "ok": bool(result.get("ok")),
            "action": "swarm_create_board",
            "message": result.get("message") or result.get("error"),
            "result": result,
            "snapshot": result.get("snapshot"),
        }
    except Exception as exc:
        return _error_response(request_id, action="swarm_create_board", exc=exc)


def _handle_beneficiary_snapshot(request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.beneficiary_state import get_beneficiary_snapshot

        snapshot = get_beneficiary_snapshot()
        return {
            "id": request_id,
            "ok": True,
            "action": "beneficiary_snapshot",
            "snapshot": snapshot,
        }
    except Exception as exc:
        return _error_response(request_id, action="beneficiary_snapshot", exc=exc)


def _handle_beneficiary_set_family_member(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.beneficiary_state import set_family_beneficiary

        first_name = str(request.get("first_name") or request.get("family_beneficiary_first_name") or "")
        snapshot = set_family_beneficiary(first_name)
        return {
            "id": request_id,
            "ok": True,
            "action": "beneficiary_set_family_member",
            "snapshot": snapshot,
        }
    except Exception as exc:
        return _error_response(request_id, action="beneficiary_set_family_member", exc=exc)


def _handle_beneficiary_submit_colleague(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.beneficiary_state import submit_colleague_referral

        snapshot = submit_colleague_referral(
            name=str(request.get("name") or ""),
            email=str(request.get("email") or ""),
            phone=str(request.get("phone") or ""),
            non_family_attested=bool(request.get("non_family_attested")),
        )
        return {
            "id": request_id,
            "ok": True,
            "action": "beneficiary_submit_colleague",
            "snapshot": snapshot,
        }
    except Exception as exc:
        return _error_response(request_id, action="beneficiary_submit_colleague", exc=exc)


def _handle_remote_model_catalog(request_id: str) -> dict[str, Any]:
    try:
        catalog = list_remote_options(probe=False)
        return {
            "id": request_id,
            "ok": True,
            "action": "remote_model_catalog",
            "catalog": catalog,
        }
    except Exception as exc:
        return _error_response(request_id, action="remote_model_catalog", exc=exc)


def _handle_remote_model_apply(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    connector_id = str(request.get("connector_id") or "").strip()
    try:
        result = apply_remote_switch(connector_id, probe=True)
        payload = {
            "id": request_id,
            "ok": result.ok,
            "action": "remote_model_apply",
            "result": result.to_dict(),
            "routing_mode": get_routing_mode(),
        }
        if not result.ok:
            payload["code"] = result.code or LLM_UNAVAILABLE
            payload["error"] = result.message
            payload["message"] = result.message
            payload["retryable"] = result.code in {"LLM_RATE_LIMIT", "LLM_UNAVAILABLE"}
        return payload
    except Exception as exc:
        return _error_response(request_id, action="remote_model_apply", exc=exc)


def _handle_remote_model_save_key(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    connector_id = str(request.get("connector_id") or "").strip()
    key = str(request.get("key") or "")
    try:
        result = save_remote_api_key(connector_id, key)
        # Never echo the access code — only safe status fields.
        safe = {
            "ok": bool(result.get("ok")),
            "connector_id": result.get("connector_id"),
            "configured": result.get("configured"),
            "message": result.get("message"),
        }
        payload = {
            "id": request_id,
            "ok": safe["ok"],
            "action": "remote_model_save_key",
            "result": safe,
        }
        if not safe["ok"]:
            payload["message"] = safe.get("message") or "Could not save access code."
        return payload
    except Exception as exc:
        return _error_response(request_id, action="remote_model_save_key", exc=exc)


def _handle_remote_routing_mode(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        if "mode" in request:
            result = set_routing_mode(str(request.get("mode") or "manual"))
            return {
                "id": request_id,
                "ok": bool(result.get("ok")),
                "action": "remote_routing_mode",
                "routing_mode": result.get("routing_mode", get_routing_mode()),
                "message": result.get("message", ""),
            }
        return {
            "id": request_id,
            "ok": True,
            "action": "remote_routing_mode",
            "routing_mode": get_routing_mode(),
        }
    except Exception as exc:
        return _error_response(request_id, action="remote_routing_mode", exc=exc)


def _handle_telegram_import_bundle(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.telegram_import import build_import_bundle

        dry_run = bool(request.get("dry_run"))
        session_id = str(request.get("session_id") or "").strip() or None
        bundle = build_import_bundle(session_id=session_id, dry_run=dry_run)
        return {
            "id": request_id,
            "ok": bool(bundle.get("ok")),
            "action": "telegram_import_bundle",
            "bundle": bundle,
            "message": bundle.get("message", ""),
        }
    except Exception as exc:
        return _error_response(request_id, action="telegram_import_bundle", exc=exc)


def _handle_telegram_import_preview(request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.telegram_import import build_import_bundle

        bundle = build_import_bundle(dry_run=True)
        return {
            "id": request_id,
            "ok": bool(bundle.get("ok")),
            "action": "telegram_import_preview",
            "bundle": bundle,
            "message": bundle.get("message", ""),
        }
    except Exception as exc:
        return _error_response(request_id, action="telegram_import_preview", exc=exc)


def _record_life_decision(
    *,
    title: str,
    chosen: str,
    human_said: str = "",
    context: str = "",
    options: list[str] | None = None,
    mission_id: str | None = None,
) -> None:
    """Best-effort write into offline Decision Log — never fail the primary action."""
    try:
        from centurion_cli.life_missions import log_decision

        payload: dict[str, Any] = {
            "title": title,
            "chosen": chosen,
            "human_said": human_said,
            "context": context,
            "options": options or [],
        }
        if mission_id:
            # Only attach when it looks like a life mission UUID already in life.db
            payload["mission_id"] = mission_id
            try:
                from centurion_cli.life_missions import get_mission

                if get_mission(mission_id) is None:
                    payload.pop("mission_id", None)
            except Exception:
                payload.pop("mission_id", None)
        log_decision(payload)
    except Exception:
        logger.debug("life decision log skipped", exc_info=True)


def _error_response(
    request_id: str,
    *,
    action: str,
    exc: BaseException,
    retryable: bool = False,
    attempt_recovery: bool = False,
    retry_text: str = "",
    run_agent: Callable[[str], str] | None = None,
    classify_as_llm: bool | None = None,
) -> dict[str, Any]:
    """Build a bridge error payload.

    Chat/provider failures use thinking-service recovery copy via
    ``classify_llm_error``. Life / plans / swarm / ops actions must NOT — those
    are local Focus tooling; remapping them to “restore your last working setup”
    hides the real fault (and was what Scan this machine showed on Titus).
    """
    action_l = str(action or "").strip().lower()
    if classify_as_llm is None:
        head = action_l.split("_", 1)[0]
        classify_as_llm = head not in {
            "life",
            "plan",
            "plans",
            "swarm",
            "kanban",
            "fleet",
            "ops",
            "plugin",
            "client",
            "tools",
            "license",
            "mission",  # legacy mission_* actions
        }

    if classify_as_llm:
        code, message = classify_llm_error(exc)
    else:
        raw = str(exc).strip() or type(exc).__name__
        if isinstance(exc, ImportError) or isinstance(exc, ModuleNotFoundError):
            code = "MODULE_MISSING"
            message = (
                f"{raw}. Update Centurion AI OS and quit/reopen Sovereign AI Brain "
                "so the bridge reloads this action."
            )
        else:
            code = "ACTION_FAILED"
            message = raw

    if attempt_recovery and classify_as_llm and load_last_known_good() is not None:
        restored = _attempt_lkg_retry(
            request_id=request_id,
            retry_text=retry_text,
            original_code=code,
            run_agent=run_agent,
        )
        if restored is not None:
            return restored

    return {
        "id": request_id,
        "ok": False,
        "action": action,
        "code": code,
        "error": message,
        "message": message,
        "retryable": retryable
        or (classify_as_llm and code in {"LLM_RATE_LIMIT", "LLM_UNAVAILABLE"}),
    }


def _attempt_lkg_retry(
    *,
    request_id: str,
    retry_text: str,
    original_code: str,
    run_agent: Callable[[str], str] | None,
) -> dict[str, Any] | None:
    if original_code not in {
        LLM_AUTH_MISSING,
        LLM_AUTH_INVALID,
        LLM_MODEL_INVALID,
        LLM_CONFIG_INVALID,
    }:
        return None
    if not retry_text or run_agent is None:
        return None

    restore = restore_last_known_good(probe=True)
    if not restore.ok:
        return None

    try:
        response = run_agent(retry_text)
        record_successful_turn()
        return {
            "id": request_id,
            "ok": True,
            "action": "chat",
            "text": response or "",
            "recovered": True,
            "recovery_message": "Restored your last working setup.",
        }
    except Exception:
        return None


def _remote_events_enabled() -> bool:
    import os

    return os.environ.get("CENTURION_REMOTE_EVENTS", "").strip().lower() in {
        "1",
        "true",
        "yes",
    }


# Thread-local sink for daemon socket mode (overrides FD 1 / stdout).
_event_sink_tls: Any = None


def _event_sink_state():
    global _event_sink_tls
    import threading

    if _event_sink_tls is None:
        _event_sink_tls = threading.local()
    return _event_sink_tls


def _set_event_sink(write_fn: Callable[[bytes], None] | None) -> None:
    """Route NDJSON events to ``write_fn`` for this thread (Unix-socket serve)."""
    _event_sink_state().write = write_fn


def _emit_remote_event(event: dict[str, Any]) -> None:
    """Write one NDJSON event to the active sink or real stdout FD."""
    import os

    payload = (json.dumps(event, ensure_ascii=False) + "\n").encode("utf-8")
    write_fn = getattr(_event_sink_state(), "write", None)
    if write_fn is not None:
        write_fn(payload)
        return
    os.write(1, payload)


def _write_approval_event(event: dict[str, Any]) -> None:
    """Emit approval_request the same way as activity events (sink or FD 1)."""
    _emit_remote_event(event)


def _resolve_remote_tool_progress_mode(cfg: dict[str, Any] | None = None) -> str:
    """Resolve display.tool_progress for Brain/remote (default all)."""
    try:
        if cfg is None:
            from centurion_cli.config import load_config

            cfg = load_config()
        from gateway.display_config import resolve_display_setting

        mode = resolve_display_setting(cfg or {}, "remote", "tool_progress", "all")
    except Exception:
        mode = "all"
    if mode is False or mode is None:
        return "off"
    text = str(mode).strip().lower()
    if text in {"off", "new", "all", "verbose"}:
        return text
    return "all"


def _format_remote_tool_activity_line(
    tool_name: str,
    preview: str | None = None,
    args: dict | None = None,
    *,
    mode: str = "all",
) -> str:
    """Telegram-style tool progress line for Brain Chat activity feed."""
    try:
        from agent.display import get_tool_emoji, get_tool_preview_max_len

        emoji = get_tool_emoji(tool_name, default="⚙️")
        preview_len = get_tool_preview_max_len()
    except Exception:
        emoji = "⚙️"
        preview_len = 0

    name = (tool_name or "tool").strip() or "tool"
    if mode == "verbose" and args:
        try:
            args_str = json.dumps(args, ensure_ascii=False, default=str)
        except Exception:
            args_str = str(args)
        cap = preview_len if preview_len > 0 else 0
        if cap > 0 and len(args_str) > cap:
            args_str = args_str[: cap - 3] + "..."
        keys = list(args.keys()) if isinstance(args, dict) else []
        return f"{emoji} {name}({keys})\n{args_str}"

    text = (preview or "").strip()
    if text:
        cap = preview_len if preview_len > 0 else 40
        if len(text) > cap:
            text = text[: cap - 3] + "..."
        return f'{emoji} {name}: "{text}"'
    return f"{emoji} {name}..."


def _make_remote_activity_callbacks(
    *,
    mode: str,
) -> tuple[Any, Any]:
    """Build tool_progress_callback + status_callback that emit NDJSON activity.

    Returns ``(tool_progress_callback, status_callback)``. When *mode* is
    ``off``, both callables are no-ops (still safe to attach).
    """
    last_tool: list[str | None] = [None]

    def tool_progress_callback(
        event_type: str,
        tool_name: str | None = None,
        preview: str | None = None,
        args: dict | None = None,
        **_kwargs: Any,
    ) -> None:
        if mode == "off" or not _remote_events_enabled():
            return
        et = (event_type or "").strip()
        if et in {"reasoning.available", "_thinking"}:
            text = (preview or tool_name or "").strip()
            if not text:
                return
            _emit_remote_event(
                {
                    "centurion_event": "activity",
                    "kind": "thinking",
                    "text": text[:800],
                }
            )
            return
        if et == "tool.completed":
            if mode != "verbose":
                return
            # Verbose completion: short done line only.
            name = (tool_name or "").strip()
            if not name:
                return
            line = _format_remote_tool_activity_line(name, preview, args, mode="all")
            _emit_remote_event(
                {
                    "centurion_event": "activity",
                    "kind": "tool",
                    "event": et,
                    "tool": name,
                    "preview": (preview or "")[:200],
                    "line": f"✓ {line}",
                }
            )
            return
        if et != "tool.started":
            return
        name = (tool_name or "").strip()
        if not name:
            return
        if mode == "new" and name == last_tool[0]:
            return
        last_tool[0] = name
        line = _format_remote_tool_activity_line(name, preview, args, mode=mode)
        _emit_remote_event(
            {
                "centurion_event": "activity",
                "kind": "tool",
                "event": et,
                "tool": name,
                "preview": (preview or "")[:200],
                "line": line,
            }
        )

    def status_callback(event_type: str, message: str) -> None:
        if mode == "off" or not _remote_events_enabled():
            return
        text = (message or "").strip()
        if not text:
            return
        _emit_remote_event(
            {
                "centurion_event": "activity",
                "kind": "status",
                "event": (event_type or "lifecycle").strip() or "lifecycle",
                "message": text[:400],
                "line": text[:400],
            }
        )

    return tool_progress_callback, status_callback


def _run_agent_quiet(
    text: str,
    *,
    session_id: str | None = None,
    request_id: str | None = None,
) -> str:
    """Run one agent turn without polluting stdout (bridge response must be pure JSON).

    When remote events are enabled (NDJSON on stdout), approval prompts and
    mid-turn activity (tools / thinking / status) are emitted as
    ``{"centurion_event":...}`` lines and the final response is still a single
    JSON object on stdout. Stderr stays quiet.
    """
    import logging
    import os
    from contextlib import redirect_stderr, redirect_stdout

    from centurion_cli.oversight import should_enable_remote_yolo

    logging.disable(logging.CRITICAL)
    yolo = should_enable_remote_yolo()
    if yolo:
        os.environ.setdefault("CENTURION_YOLO_MODE", "1")
    else:
        os.environ.pop("CENTURION_YOLO_MODE", None)
        # Treat remote chat as an interactive gateway-like approval context so
        # dangerous tools block for phone Approve/Deny instead of auto-approving.
        os.environ["CENTURION_GATEWAY_SESSION"] = "1"
        os.environ["CENTURION_SESSION_PLATFORM"] = "remote"
    os.environ.setdefault("CENTURION_ACCEPT_HOOKS", "1")
    os.environ["CENTURION_DISABLE_OPENROUTER"] = "1"
    os.environ["CENTURION_PLATFORM"] = "remote"

    approval_key = f"remote:{request_id or session_id or 'turn'}"
    events_enabled = os.environ.get("CENTURION_REMOTE_EVENTS", "").strip() in {
        "1",
        "true",
        "yes",
    }

    notify_registered = False
    if not yolo and events_enabled:
        from tools.approval import (
            register_gateway_notify,
            set_current_session_key,
            unregister_gateway_notify,
        )

        set_current_session_key(approval_key)

        def _emit_approval(data: dict) -> None:
            event = {
                "centurion_event": "approval_request",
                "approval_id": approval_key,
                "session_key": approval_key,
                "command": data.get("command") or "",
                "description": data.get("description") or "",
                "pattern_key": data.get("pattern_key") or "",
                "choices": ["once", "session", "always", "deny"],
            }
            # Sink (socket) or real stdout FD — survives redirect_stdout(devnull).
            _write_approval_event(event)

        register_gateway_notify(approval_key, _emit_approval)
        notify_registered = True
        _start_approval_stdin_reader(approval_key)

    try:
        # Always silence agent library stdout; approval events write to FD 1
        # directly so they bypass redirect_stdout.
        with open(os.devnull, "w", encoding="utf-8") as devnull, redirect_stdout(
            devnull
        ), redirect_stderr(devnull):
            return _run_remote_agent_turn(text, session_id=session_id) or ""
    finally:
        if notify_registered:
            from tools.approval import unregister_gateway_notify

            unregister_gateway_notify(approval_key)


_approval_stdin_started = False
_approval_stdin_lock = None


def _start_approval_line_reader(
    default_session_key: str,
    readline_fn: Callable[[], str],
) -> None:
    """Read approval_respond JSON lines from ``readline_fn`` while the agent runs."""
    import threading

    def _loop() -> None:
        from tools.approval import resolve_gateway_approval

        while True:
            line = readline_fn()
            if not line:
                return
            line = line.strip()
            if not line:
                continue
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
            if str(payload.get("action") or "").strip().lower() != "approval_respond":
                continue
            session_key = str(payload.get("session_key") or default_session_key).strip()
            choice = str(payload.get("choice") or "deny").strip().lower()
            resolve_all = bool(payload.get("all") or payload.get("resolve_all"))
            if session_key and choice:
                resolve_gateway_approval(session_key, choice, resolve_all=resolve_all)

    threading.Thread(
        target=_loop,
        name="remote-approval-reader",
        daemon=True,
    ).start()


def _start_approval_stdin_reader(default_session_key: str) -> None:
    """Read follow-up approval_respond lines from stdin while the agent runs."""
    global _approval_stdin_started, _approval_stdin_lock
    import threading

    # Socket serve mode installs its own per-connection reader.
    if getattr(_event_sink_state(), "write", None) is not None:
        return

    if _approval_stdin_lock is None:
        _approval_stdin_lock = threading.Lock()
    with _approval_stdin_lock:
        if _approval_stdin_started:
            return
        _approval_stdin_started = True

    _start_approval_line_reader(default_session_key, sys.stdin.readline)


def _ensure_remote_session(*, title: str | None = None) -> str:
    import uuid

    from centurion_state import SessionDB

    session_id = f"remote_{uuid.uuid4().hex[:16]}"
    db = SessionDB()
    try:
        db.create_session(session_id, source="remote")
        if title:
            try:
                db.set_session_title(session_id, title)
            except Exception:
                pass
    finally:
        try:
            db.close()
        except Exception:
            pass
    return session_id


def _remote_display_name() -> str:
    try:
        from centurion_cli.profiles import apply_sticky_profile_home

        apply_sticky_profile_home()
    except Exception:
        pass
    try:
        from agent.prompt_builder import (
            _clean_display_name,
            _is_usable_personal_name,
            agent_name_path,
            resolve_centurion_display_name,
        )
        from centurion_cli.soul_sync import read_soul

        soul = read_soul()
        soul_name = _clean_display_name(str(soul.get("name") or ""))
        if _is_usable_personal_name(soul_name):
            name = soul_name
        else:
            name = resolve_centurion_display_name(str(soul.get("markdown") or ""))
        # Backfill sticky file so later turns stay locked to the Soul name.
        if name and name != "Centurion":
            path = agent_name_path()
            try:
                current = (
                    _clean_display_name(path.read_text(encoding="utf-8"))
                    if path.exists()
                    else ""
                )
                if current != name:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(name + "\n", encoding="utf-8")
                    try:
                        path.chmod(0o600)
                    except OSError:
                        pass
            except Exception:
                pass
        return name
    except Exception:
        return "Centurion"


def _remote_identity_ephemeral(display_name: str) -> str:
    name = (display_name or "").strip() or "Centurion"
    personality = ""
    try:
        from centurion_cli.soul_sync import read_soul

        soul = read_soul()
        personality = str(soul.get("personalitySummary") or "").strip()
        if not personality:
            # First chunk of freeform Soul body when structured Personality is empty.
            md = str(soul.get("markdown") or "")
            for line in md.splitlines():
                stripped = line.strip()
                if not stripped or stripped.startswith("#") or stripped.startswith("<!--"):
                    continue
                personality = stripped
                break
        if len(personality) > 400:
            personality = personality[:400].rstrip() + "…"
    except Exception:
        personality = ""

    lines = [
        f"IDENTITY (highest priority this turn): Your name is {name}.",
        f"{name} is a Centurion of Centurion Fleet on this owner's private brain.",
        f"When asked your name, answer only: {name}.",
        f"Describe yourself only as {name}, a Centurion of Centurion Fleet.",
        "Your Soul document (SOUL.md on this brain) is authoritative for how you "
        "speak and behave — follow it. If asked for your Soul, quote SOUL.md.",
        "Do not name other products, model families, or assistants.",
    ]
    if personality:
        lines.append(f"Soul personality (from SOUL.md): {personality}")
    return " ".join(lines)


def _scrub_foreign_identity_history(
    history: list[dict[str, Any]] | None,
    display_name: str,
) -> list[dict[str, Any]] | None:
    """Rewrite assistant turns that used foreign branding so they cannot stick."""
    if not history:
        return history
    name = (display_name or "").strip() or "Centurion"
    name_l = name.lower()
    cleaned: list[dict[str, Any]] = []
    for msg in history:
        if not isinstance(msg, dict):
            continue
        role = msg.get("role")
        content = msg.get("content")
        if role != "assistant" or not isinstance(content, str):
            cleaned.append(msg)
            continue
        lower = content.lower()
        foreign = any(
            token in lower
            for token in (
                "hermes",
                "nous research",
                "nousresearch",
                "i'm claude",
                "i am claude",
                "i'm chatgpt",
                "i am chatgpt",
                "i'm gpt",
                "as an ai language model",
            )
        )
        # Prior turns that used a different personal name (or only the product
        # default) confuse the model — pin them to the current Soul name.
        claims_other_name = False
        if name_l != "centurion":
            if re.search(r"\bmy name is\b", lower) and name_l not in lower:
                claims_other_name = True
            if re.search(r"\bi(?:'m| am)\b.{0,40}\bcenturion\b", lower) and name_l not in lower:
                claims_other_name = True
        if foreign or claims_other_name:
            cleaned.append(
                {
                    **msg,
                    "content": (
                        f"My name is {name}. I am a Centurion of Centurion Fleet."
                    ),
                }
            )
        else:
            cleaned.append(msg)
    return cleaned


def _sanitize_remote_reply(text: str, display_name: str) -> str:
    """Strip rival-brand echoes from Brain replies before the UI shows them."""
    name = (display_name or "").strip() or "Centurion"
    if not text:
        return text

    # Drop any sentence that still names rival brands (even as denials).
    parts = re.split(r"(?<=[.!?])\s+", text.strip())
    kept: list[str] = []
    for part in parts:
        lower = part.lower()
        if re.search(r"\bhermes\b", lower) or re.search(r"\bnous\b", lower):
            continue
        kept.append(part)
    out = " ".join(kept).strip()

    # If the owner chose a personal name, correct "My name is Centurion" slips.
    if name.lower() != "centurion":
        out = re.sub(r"(?i)\bmy name is Centurion\b", f"My name is {name}", out)
        out = re.sub(
            r"(?i)\bname(?:d)?(?:\s+confirmed)?\s*:?\s*Centurion\b",
            f"Name confirmed: {name}",
            out,
        )
        out = re.sub(
            r"(?i)\bI am Centurion\b(?!\s+(?:AI|Fleet|of))",
            f"I am {name}",
            out,
        )
        # Common product-default reply: "Centurion. A Centurion of the Centurion fleet"
        # Also: "Centurion and yes I know it — centurion of centurion fleet"
        if re.search(
            r"(?i)\bcenturion\s+of\s+(?:the\s+)?centurion\s+fleet\b",
            out,
        ) and not re.search(rf"(?i)\b{re.escape(name)}\b", out):
            out = f"My name is {name}. I am a Centurion of Centurion Fleet."
        elif re.match(
            r"(?is)^\s*Centurion\b[.!]?\s*(?:A\s+)?Centurion\s+of\s+(?:the\s+)?Centurion\s+fleet\b",
            out,
        ):
            out = f"My name is {name}. I am a Centurion of Centurion Fleet."
        elif re.match(r"(?is)^\s*Centurion\s*[.!]?\s*$", out):
            out = f"My name is {name}."
        elif re.match(r"(?is)^\s*Centurion\b", out) and name.lower() not in out.lower():
            out = re.sub(r"(?i)^\s*Centurion\b", name, out, count=1)

    lower_out = out.lower()
    if (
        not out
        or re.search(r"\bhermes\b", lower_out)
        or re.search(r"\bnous\b", lower_out)
    ):
        out = f"My name is {name}. I am a Centurion of Centurion Fleet."
    return out.strip()


def _run_remote_agent_turn(text: str, *, session_id: str | None = None) -> str:
    """Session-aware remote chat turn using AIAgent.run_conversation."""
    import os

    from centurion_cli.config import load_config
    from centurion_cli.runtime_provider import resolve_runtime_provider
    from centurion_cli.tools_config import _get_platform_tools
    from centurion_cli.fallback_config import get_fallback_chain
    from run_agent import AIAgent

    cfg = load_config()
    model_cfg = cfg.get("model") or {}
    if isinstance(model_cfg, str):
        cfg_model = model_cfg
    else:
        cfg_model = model_cfg.get("default") or model_cfg.get("model") or ""
    env_model = os.getenv("CENTURION_INFERENCE_MODEL", "").strip()
    effective_model = env_model or cfg_model

    effective_provider = None
    runtime = resolve_runtime_provider(
        requested=effective_provider,
        target_model=effective_model or None,
    )
    toolsets_list = sorted(_get_platform_tools(cfg, "telegram"))
    _fb = get_fallback_chain(cfg)

    history = None
    session_db = None
    try:
        from centurion_state import SessionDB

        session_db = SessionDB()
        if session_id:
            tip = session_db.resolve_resume_session_id(session_id)
            history = session_db.get_messages_as_conversation(tip, include_ancestors=True)
            session_id = tip
        else:
            session_id = _ensure_remote_session()
    except Exception:
        session_db = None
        history = None

    display_name = _remote_display_name()
    history = _scrub_foreign_identity_history(history, display_name)
    identity_ephemeral = _remote_identity_ephemeral(display_name)
    api_user_message = (
        f"[Identity for this reply: your name is {display_name}. "
        f"{display_name} is a Centurion of Centurion Fleet. "
        f"Answer in those terms only.]\n\n"
        f"{text}"
    )

    # Brain Chat shares CENTURION_HOME with Telegram/gateway — load hot-cache
    # memory + providers so existing customers keep continuity. Vault prefetch
    # stays config-gated inside agent init.
    agent = AIAgent(
        api_key=runtime.get("api_key"),
        base_url=runtime.get("base_url"),
        provider=runtime.get("provider"),
        api_mode=runtime.get("api_mode"),
        model=effective_model,
        enabled_toolsets=toolsets_list,
        quiet_mode=True,
        platform="remote",
        session_id=session_id,
        session_db=session_db,
        credential_pool=runtime.get("credential_pool"),
        fallback_model=_fb or None,
        skip_memory=False,
        load_soul_identity=True,
        ephemeral_system_prompt=identity_ephemeral,
    )
    agent.suppress_status_output = True
    agent.stream_delta_callback = None
    agent.tool_gen_callback = None

    progress_mode = _resolve_remote_tool_progress_mode(cfg)
    if _remote_events_enabled() and progress_mode != "off":
        tool_cb, status_cb = _make_remote_activity_callbacks(mode=progress_mode)
        agent.tool_progress_callback = tool_cb
        agent.status_callback = status_cb

    result = agent.run_conversation(
        user_message=api_user_message,
        conversation_history=history or None,
        task_id=session_id,
        persist_user_message=text,
    )
    if isinstance(result, dict):
        raw = str(result.get("final_response") or result.get("response") or "")
    else:
        raw = str(result or "")
    return _sanitize_remote_reply(raw, display_name)

def _handle_gateway_status(request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.gateway import get_gateway_runtime_snapshot
        from gateway.status import read_runtime_status

        snapshot = get_gateway_runtime_snapshot()
        runtime = read_runtime_status() or {}
        platforms_runtime = runtime.get("platforms") or {}
        platforms: list[dict[str, Any]] = []
        try:
            from gateway.config import load_gateway_config

            gateway_config = load_gateway_config()
            for platform, pconfig in (gateway_config.platforms or {}).items():
                name = getattr(platform, "value", str(platform))
                runtime_info = platforms_runtime.get(name) or {}
                platforms.append(
                    {
                        "name": name,
                        "enabled": bool(getattr(pconfig, "enabled", False)),
                        "connected": bool(
                            runtime_info.get("connected")
                            or runtime_info.get("status") == "connected"
                        ),
                        "status": runtime_info.get("status")
                        or ("enabled" if getattr(pconfig, "enabled", False) else "disabled"),
                        "label": name.replace("_", " ").title(),
                    }
                )
        except Exception:
            for name, runtime_info in platforms_runtime.items():
                if not isinstance(runtime_info, dict):
                    runtime_info = {}
                platforms.append(
                    {
                        "name": name,
                        "enabled": True,
                        "connected": bool(runtime_info.get("connected")),
                        "status": runtime_info.get("status") or "unknown",
                        "label": name.replace("_", " ").title(),
                    }
                )

        return {
            "id": request_id,
            "ok": True,
            "action": "gateway_status",
            "status": {
                "running": bool(snapshot.running),
                "service_running": bool(snapshot.service_running),
                "service_installed": bool(snapshot.service_installed),
                "manager": snapshot.manager,
                "pids": list(snapshot.gateway_pids),
                "gateway_state": runtime.get("gateway_state"),
                "platforms": platforms,
            },
        }
    except Exception as exc:
        return _error_response(request_id, action="gateway_status", exc=exc)


def _handle_gateway_lifecycle(request_id: str, operation: str) -> dict[str, Any]:
    try:
        import os
        from contextlib import redirect_stderr, redirect_stdout

        from centurion_cli import gateway as gateway_cli

        with open(os.devnull, "w", encoding="utf-8") as devnull, redirect_stdout(
            devnull
        ), redirect_stderr(devnull):
            if operation == "start":
                if gateway_cli.supports_systemd_services():
                    gateway_cli.systemd_start(system=False)
                else:
                    raise RuntimeError(
                        "Gateway start is only supported via systemd on this host."
                    )
            elif operation == "stop":
                if gateway_cli.supports_systemd_services():
                    gateway_cli.systemd_stop(system=False)
                else:
                    gateway_cli.stop_profile_gateway()
            elif operation == "restart":
                if gateway_cli.supports_systemd_services():
                    try:
                        gateway_cli.systemd_stop(system=False)
                    except Exception:
                        pass
                    gateway_cli.systemd_start(system=False)
                else:
                    raise RuntimeError("Gateway restart requires systemd on this host.")
            else:
                raise ValueError(f"unsupported gateway operation: {operation}")

        status = _handle_gateway_status(request_id)
        status["action"] = f"gateway_{operation}"
        status["message"] = f"Gateway {operation} requested."
        return status
    except Exception as exc:
        return _error_response(request_id, action=f"gateway_{operation}", exc=exc)


def _handle_gateway_platform_set(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.config import load_config, save_config

        platform = str(request.get("platform") or "").strip().lower()
        if not platform:
            return {
                "id": request_id,
                "ok": False,
                "action": "gateway_platform_set",
                "code": "INVALID_REQUEST",
                "error": "platform is required.",
                "message": "platform is required.",
                "retryable": False,
            }
        enabled = bool(request.get("enabled"))
        restart = bool(request.get("restart", True))
        config = load_config()
        block = config.get(platform)
        if not isinstance(block, dict):
            block = {}
        block["enabled"] = enabled
        config[platform] = block
        save_config(config)

        restarted = False
        if restart:
            life = _handle_gateway_lifecycle(request_id, "restart")
            restarted = bool(life.get("ok"))
        status = _handle_gateway_status(request_id)
        status["action"] = "gateway_platform_set"
        status["restarted"] = restarted
        status["message"] = f"{platform} {'enabled' if enabled else 'disabled'}."
        return status
    except Exception as exc:
        return _error_response(request_id, action="gateway_platform_set", exc=exc)


def _handle_session_list(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_state import SessionDB

        limit = int(request.get("limit") or 20)
        source = str(request.get("source") or "remote").strip() or None
        db = SessionDB()
        try:
            rows = db.list_sessions_rich(
                source=source,
                limit=max(1, min(limit, 100)),
                order_by_last_active=True,
            )
        finally:
            try:
                db.close()
            except Exception:
                pass
        sessions = [
            {
                "id": row.get("id"),
                "title": row.get("title") or "",
                "preview": row.get("preview") or "",
                "last_active": row.get("last_active"),
                "message_count": row.get("message_count") or 0,
                "source": row.get("source") or source,
            }
            for row in rows
        ]
        return {
            "id": request_id,
            "ok": True,
            "action": "session_list",
            "sessions": sessions,
        }
    except Exception as exc:
        return _error_response(request_id, action="session_list", exc=exc)


def _commit_remote_session_continuity(session_id: str | None) -> dict[str, Any]:
    """Fire Memory Horizon session-end digest for a Brain/remote chat session.

    Safe to call from session_new / soul_put / explicit session_end_continuity.
    Never raises.
    """
    result: dict[str, Any] = {"committed": False, "session_id": session_id}
    sid = str(session_id or "").strip()
    if not sid:
        return result
    try:
        from agent.memory_continuity import run_session_end_digest
        from centurion_state import SessionDB

        db = SessionDB()
        try:
            tip = db.resolve_resume_session_id(sid)
            messages = db.get_messages_as_conversation(tip, include_ancestors=True)
        finally:
            try:
                db.close()
            except Exception:
                pass

        agent = SimpleNamespace(
            _skip_memory=False,
            _continuity_digest_done=False,
            agent_context="primary",
            session_id=tip,
            _horizon_continuity_cfg=None,
        )
        run_session_end_digest(agent, messages or [])
        result["committed"] = bool(getattr(agent, "_continuity_digest_done", False))
        result["session_id"] = tip
    except Exception:
        logger.debug(
            "remote_bridge: session continuity commit failed for %s",
            sid,
            exc_info=True,
        )
    return result


def _handle_session_end_continuity(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    try:
        session_id = str(request.get("session_id") or "").strip()
        info = _commit_remote_session_continuity(session_id or None)
        return {
            "id": request_id,
            "ok": True,
            "action": "session_end_continuity",
            **info,
        }
    except Exception as exc:
        return _error_response(request_id, action="session_end_continuity", exc=exc)


def _handle_session_new(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        previous = str(request.get("previous_session_id") or "").strip()
        continuity = _commit_remote_session_continuity(previous or None)
        title = str(request.get("title") or "").strip() or None
        session_id = _ensure_remote_session(title=title)
        return {
            "id": request_id,
            "ok": True,
            "action": "session_new",
            "session_id": session_id,
            "continuity": continuity,
        }
    except Exception as exc:
        return _error_response(request_id, action="session_new", exc=exc)


def _handle_session_resume(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_state import SessionDB

        session_id = str(request.get("session_id") or "").strip()
        if not session_id:
            return {
                "id": request_id,
                "ok": False,
                "action": "session_resume",
                "code": "INVALID_REQUEST",
                "error": "session_id is required.",
                "message": "session_id is required.",
                "retryable": False,
            }
        db = SessionDB()
        try:
            tip = db.resolve_resume_session_id(session_id)
            messages = db.get_messages_as_conversation(tip, include_ancestors=True)
        finally:
            try:
                db.close()
            except Exception:
                pass
        return {
            "id": request_id,
            "ok": True,
            "action": "session_resume",
            "session_id": tip,
            "messages": messages,
        }
    except Exception as exc:
        return _error_response(request_id, action="session_resume", exc=exc)


def _handle_session_history(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_state import SessionDB

        session_id = str(request.get("session_id") or "").strip()
        if not session_id:
            return {
                "id": request_id,
                "ok": False,
                "action": "session_history",
                "code": "INVALID_REQUEST",
                "error": "session_id is required.",
                "message": "session_id is required.",
                "retryable": False,
            }
        limit = int(request.get("limit") or 200)
        db = SessionDB()
        try:
            tip = db.resolve_resume_session_id(session_id)
            messages = db.get_messages_as_conversation(tip, include_ancestors=True)
        finally:
            try:
                db.close()
            except Exception:
                pass
        if limit > 0 and len(messages) > limit:
            messages = messages[-limit:]
        return {
            "id": request_id,
            "ok": True,
            "action": "session_history",
            "session_id": tip,
            "messages": messages,
        }
    except Exception as exc:
        return _error_response(request_id, action="session_history", exc=exc)


def _handle_session_rename(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_state import SessionDB

        session_id = str(request.get("session_id") or "").strip()
        title = str(request.get("title") or "").strip()
        if not session_id:
            return {
                "id": request_id,
                "ok": False,
                "action": "session_rename",
                "code": "INVALID_REQUEST",
                "error": "session_id is required.",
                "message": "session_id is required.",
                "retryable": False,
            }
        if not title:
            return {
                "id": request_id,
                "ok": False,
                "action": "session_rename",
                "code": "INVALID_REQUEST",
                "error": "title is required.",
                "message": "Enter a conversation name.",
                "retryable": False,
            }
        db = SessionDB()
        try:
            tip = db.resolve_resume_session_id(session_id)
            try:
                updated = db.set_session_title(tip, title)
            except ValueError as exc:
                return {
                    "id": request_id,
                    "ok": False,
                    "action": "session_rename",
                    "code": "INVALID_REQUEST",
                    "error": str(exc),
                    "message": str(exc),
                    "retryable": False,
                }
            if not updated:
                return {
                    "id": request_id,
                    "ok": False,
                    "action": "session_rename",
                    "code": "NOT_FOUND",
                    "error": "Conversation not found.",
                    "message": "Conversation not found.",
                    "retryable": False,
                }
            saved = db.get_session_title(tip) or title
        finally:
            try:
                db.close()
            except Exception:
                pass
        return {
            "id": request_id,
            "ok": True,
            "action": "session_rename",
            "session_id": tip,
            "title": saved,
        }
    except Exception as exc:
        return _error_response(request_id, action="session_rename", exc=exc)


def _handle_session_delete(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_constants import get_centurion_home
        from centurion_state import SessionDB

        session_id = str(request.get("session_id") or "").strip()
        if not session_id:
            return {
                "id": request_id,
                "ok": False,
                "action": "session_delete",
                "code": "INVALID_REQUEST",
                "error": "session_id is required.",
                "message": "session_id is required.",
                "retryable": False,
            }
        db = SessionDB()
        try:
            tip = db.resolve_resume_session_id(session_id)
            sessions_dir = get_centurion_home() / "sessions"
            deleted = db.delete_session(tip, sessions_dir=sessions_dir)
        finally:
            try:
                db.close()
            except Exception:
                pass
        if not deleted:
            return {
                "id": request_id,
                "ok": False,
                "action": "session_delete",
                "code": "NOT_FOUND",
                "error": "Conversation not found.",
                "message": "Conversation not found.",
                "retryable": False,
                "deleted": False,
            }
        return {
            "id": request_id,
            "ok": True,
            "action": "session_delete",
            "session_id": tip,
            "deleted": True,
        }
    except Exception as exc:
        return _error_response(request_id, action="session_delete", exc=exc)


def _handle_approval_respond(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from tools.approval import resolve_gateway_approval

        session_key = str(
            request.get("session_key") or request.get("approval_id") or ""
        ).strip()
        choice = str(request.get("choice") or "").strip().lower()
        if not session_key or not choice:
            return {
                "id": request_id,
                "ok": False,
                "action": "approval_respond",
                "code": "INVALID_REQUEST",
                "error": "session_key and choice are required.",
                "message": "session_key and choice are required.",
                "retryable": False,
            }
        resolve_all = bool(request.get("all") or request.get("resolve_all"))
        resolved = resolve_gateway_approval(session_key, choice, resolve_all=resolve_all)
        return {
            "id": request_id,
            "ok": True,
            "action": "approval_respond",
            "resolved": resolved,
        }
    except Exception as exc:
        return _error_response(request_id, action="approval_respond", exc=exc)


def _handle_oversight_get(request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.oversight import get_oversight_snapshot

        snapshot = get_oversight_snapshot()
        return {
            "id": request_id,
            "ok": True,
            "action": "oversight_get",
            "oversight": snapshot,
        }
    except Exception as exc:
        return _error_response(request_id, action="oversight_get", exc=exc)


def _handle_oversight_put(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.oversight import put_oversight_prefs

        updates = request.get("oversight")
        if not isinstance(updates, dict):
            # Allow flat fields on the request for convenience.
            updates = {
                key: request[key]
                for key in (
                    "autonomy_level",
                    "report_cadence",
                    "ask_before_initiative",
                    "confirm_dangerous_commands",
                    "confirm_external_actions",
                )
                if key in request
            }
        if not updates:
            return {
                "id": request_id,
                "ok": False,
                "action": "oversight_put",
                "code": "INVALID_REQUEST",
                "error": "Oversight updates are required.",
                "message": "Oversight updates are required.",
                "retryable": False,
            }
        apply_level_preset = bool(request.get("apply_level_preset", True))
        snapshot = put_oversight_prefs(
            updates, apply_level_preset=apply_level_preset
        )
        return {
            "id": request_id,
            "ok": True,
            "action": "oversight_put",
            "oversight": snapshot,
            "message": "Saved. Changes apply on the next conversation.",
        }
    except Exception as exc:
        return _error_response(request_id, action="oversight_put", exc=exc)


def _handle_license_status(request_id: str) -> dict[str, Any]:
    try:
        from centurion.license.balance import summarize_balance
        from centurion.license.enforcement import (
            EnforcementMode,
            evaluate,
            locked_user_message,
        )
        from centurion.license.fingerprint import fingerprint_short
        from centurion.license.store import load_entitlement

        ent = load_entitlement()
        decision = evaluate(ent)
        paid, target, remaining = summarize_balance(ent)
        agent_allowed = decision.mode in {
            EnforcementMode.ALLOW,
            EnforcementMode.WARN,
        }
        return {
            "id": request_id,
            "ok": True,
            "action": "license_status",
            "license": {
                "state": ent.state,
                "tier": ent.tier,
                "license_id": ent.license_id,
                "fingerprint": fingerprint_short(ent.machine_fingerprint),
                "mode": decision.mode.value,
                "agent_allowed": agent_allowed,
                "message": locked_user_message(decision) or decision.message,
                "balance_paid_gbp": paid,
                "balance_target_gbp": target,
                "balance_remaining_gbp": remaining,
                "customer_name": ent.customer_name,
                "shipment_id": ent.shipment_id,
            },
        }
    except Exception as exc:
        return _error_response(request_id, action="license_status", exc=exc)


def _handle_license_activate(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion.license.activate import activate_from_server, activate_trial
        from centurion.license.enforcement import EnforcementMode, evaluate

        # Block activate only when permanently owned (no-op); otherwise allow.
        decision = evaluate()
        _ = decision  # status is always available; activate is an unlock path

        tier = str(request.get("tier") or "trial").strip().lower()
        if tier == "trial":
            result = activate_trial(
                days=int(request.get("days") or 14),
                offline=bool(request.get("offline", False)),
            )
        else:
            result = activate_from_server(
                tier=tier,
                activation_code=request.get("activation_code") or request.get("code"),
                api_key=request.get("api_key"),
            )
        if not result.ok:
            return {
                "id": request_id,
                "ok": False,
                "action": "license_activate",
                "error": result.error or "activation_failed",
                "message": result.error or "Activation failed",
                "retryable": True,
            }
        return {
            "id": request_id,
            "ok": True,
            "action": "license_activate",
            "message": result.message,
            "state": result.entitlement.state if result.entitlement else None,
        }
    except Exception as exc:
        return _error_response(request_id, action="license_activate", exc=exc)


def _handle_license_redeem(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion.license.activate import redeem_outright_token

        token = str(request.get("token") or request.get("code") or "").strip()
        if not token:
            return {
                "id": request_id,
                "ok": False,
                "action": "license_redeem",
                "error": "token_required",
                "message": "A proof-of-purchase token is required.",
                "retryable": False,
            }
        result = redeem_outright_token(
            token,
            offline_attestation=request.get("attestation"),
        )
        if not result.ok:
            return {
                "id": request_id,
                "ok": False,
                "action": "license_redeem",
                "error": result.error or "redeem_failed",
                "message": result.error or "Redeem failed",
                "retryable": True,
            }
        return {
            "id": request_id,
            "ok": True,
            "action": "license_redeem",
            "message": result.message,
            "state": result.entitlement.state if result.entitlement else None,
        }
    except Exception as exc:
        return _error_response(request_id, action="license_redeem", exc=exc)


def _handle_license_fingerprint(request_id: str) -> dict[str, Any]:
    try:
        from centurion.license.fingerprint import collect_identity_parts, compute_fingerprint

        parts = collect_identity_parts()
        return {
            "id": request_id,
            "ok": True,
            "action": "license_fingerprint",
            "fingerprint": compute_fingerprint(parts=parts),
            "parts": {k: (v[:12] + "…" if len(v) > 20 else v) for k, v in parts.items()},
        }
    except Exception as exc:
        return _error_response(request_id, action="license_fingerprint", exc=exc)


def _handle_soul_get(request_id: str) -> dict[str, Any]:
    try:
        from agent.prompt_builder import resolve_centurion_display_name
        from centurion_cli.config import ensure_centurion_home
        from centurion_cli.soul_sync import read_soul
        from centurion_constants import get_centurion_home, get_default_centurion_root

        ensure_centurion_home()
        soul = read_soul()
        name = str(soul.get("name") or "").strip()
        resolved = resolve_centurion_display_name(str(soul.get("markdown") or ""))
        # Prefer cleaned personal name for Chat/UI locks (emoji stripped).
        soul["resolvedName"] = resolved
        soul["displayName"] = resolved if resolved else name
        home = get_centurion_home()
        root = get_default_centurion_root()
        profile_name = "default"
        try:
            if home.resolve().parent.name == "profiles":
                profile_name = home.name
            elif home.resolve() == root.resolve():
                profile_name = "default"
        except Exception:
            profile_name = "default"
        soul["profileName"] = profile_name
        soul["centurionHome"] = str(home)
        return {
            "id": request_id,
            "ok": True,
            "action": "soul_get",
            "soul": soul,
        }
    except Exception as exc:
        from centurion_cli.soul_sync import soul_md_path

        return {
            "id": request_id,
            "ok": False,
            "action": "soul_get",
            "message": f"Could not read Soul at {soul_md_path()}: {exc}",
            "error": str(exc),
        }


def _handle_soul_put(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from agent.prompt_builder import (
            _clean_display_name,
            _is_usable_personal_name,
            resolve_centurion_display_name,
        )
        from centurion_cli.soul_sync import read_soul, write_soul

        fields = request.get("soul")
        if not isinstance(fields, dict):
            fields = request.get("fields")
        markdown = request.get("markdown")
        if not isinstance(fields, dict) and not isinstance(markdown, str):
            return {
                "id": request_id,
                "ok": False,
                "action": "soul_put",
                "code": "INVALID_REQUEST",
                "error": "Soul fields or markdown are required.",
                "message": "Soul fields or markdown are required.",
                "retryable": False,
            }

        # Require a personal name so Chat never falls back to the product word.
        # Check explicit Name, then markdown body, then whatever is already on disk
        # (so a personality-only patch from iOS doesn't get rejected).
        explicit_name = ""
        if isinstance(fields, dict):
            explicit_name = _clean_display_name(str(fields.get("name") or ""))
        md_text = markdown if isinstance(markdown, str) else ""
        inferred = (
            resolve_centurion_display_name(md_text)
            if md_text.strip()
            else ""
        )
        if not _is_usable_personal_name(inferred):
            try:
                disk = read_soul()
                inferred = resolve_centurion_display_name(
                    str(disk.get("markdown") or "")
                )
            except Exception:
                pass
        if not _is_usable_personal_name(explicit_name) and not _is_usable_personal_name(
            inferred
        ):
            return {
                "id": request_id,
                "ok": False,
                "action": "soul_put",
                "code": "INVALID_REQUEST",
                "error": "Set a personal Name (e.g. Titus) before saving Soul.",
                "message": (
                    "Set a personal Name in the Name field (for example Titus) "
                    "before saving. Without it, Chat can only answer as Centurion."
                ),
                "retryable": False,
            }
        if isinstance(fields, dict) and not _is_usable_personal_name(explicit_name):
            # Keep structured ## Name aligned when Name box was empty but
            # markdown/disk already had a usable personal name.
            fields = dict(fields)
            fields["name"] = inferred

        soul = write_soul(
            fields if isinstance(fields, dict) else None,
            markdown=markdown if isinstance(markdown, str) else None,
        )
        resolved = resolve_centurion_display_name(str(soul.get("markdown") or ""))
        soul["resolvedName"] = resolved
        soul["displayName"] = str(soul.get("name") or "").strip() or resolved
        # Soul change rebuilds identity on next turn — commit continuity for the
        # chat session the Brain is about to abandon (previous_session_id or
        # desktop_chat_session file).
        previous = str(request.get("previous_session_id") or "").strip()
        if not previous:
            try:
                from centurion_constants import get_centurion_home

                marker = get_centurion_home() / "desktop_chat_session"
                if marker.is_file():
                    previous = marker.read_text(encoding="utf-8").strip()
            except Exception:
                previous = ""
        continuity = _commit_remote_session_continuity(previous or None)
        return {
            "id": request_id,
            "ok": True,
            "action": "soul_put",
            "soul": soul,
            "continuity": continuity,
            "message": (
                f"Saved. Next Chat reply should use the name {resolved}."
                if _is_usable_personal_name(resolved)
                else "Saved. Soul identity applies on the next message."
            ),
        }
    except Exception as exc:
        return _error_response(request_id, action="soul_put", exc=exc)


def _handle_mission_get(request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import legacy_mission_get

        mission = legacy_mission_get()
        return {
            "id": request_id,
            "ok": True,
            "action": "mission_get",
            "mission": mission,
        }
    except Exception as exc:
        return _error_response(request_id, action="mission_get", exc=exc)


def _handle_mission_put(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import legacy_mission_put
        from centurion_cli.mission_sync import markdown_to_structured, write_mission

        fields = request.get("mission")
        if not isinstance(fields, dict):
            fields = request.get("fields")
        markdown = request.get("markdown")
        if not isinstance(fields, dict) and not isinstance(markdown, str):
            return {
                "id": request_id,
                "ok": False,
                "action": "mission_put",
                "code": "INVALID_REQUEST",
                "error": "Mission fields or markdown are required.",
                "message": "Mission fields or markdown are required.",
                "retryable": False,
            }
        if isinstance(markdown, str) and not isinstance(fields, dict):
            fields = markdown_to_structured(markdown)
            write_mission(fields, markdown=markdown)
        mission = legacy_mission_put(fields if isinstance(fields, dict) else {})
        return {
            "id": request_id,
            "ok": True,
            "action": "mission_put",
            "mission": mission,
            "message": "Saved. Life Mission changes apply on the next conversation.",
        }
    except Exception as exc:
        return _error_response(request_id, action="mission_put", exc=exc)


def _handle_life_subjects_list(request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import list_subjects

        return {
            "id": request_id,
            "ok": True,
            "action": "life_subjects_list",
            "subjects": list_subjects(),
        }
    except Exception as exc:
        return _error_response(request_id, action="life_subjects_list", exc=exc)


def _handle_life_subject_put(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import put_subject

        fields = request.get("subject") if isinstance(request.get("subject"), dict) else request
        subject = put_subject(fields if isinstance(fields, dict) else {})
        return {
            "id": request_id,
            "ok": True,
            "action": "life_subject_put",
            "subject": subject,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_subject_put", exc=exc)


def _handle_life_subject_delete(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import delete_subject

        subject_id = str(request.get("subject_id") or request.get("id") or "").strip()
        if not subject_id:
            return {
                "id": request_id,
                "ok": False,
                "action": "life_subject_delete",
                "code": "INVALID_REQUEST",
                "error": "subject_id required",
                "message": "subject_id required",
                "retryable": False,
            }
        delete_subject(subject_id)
        return {
            "id": request_id,
            "ok": True,
            "action": "life_subject_delete",
            "deleted": True,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_subject_delete", exc=exc)


def _handle_life_subjects_reorder(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import list_subjects, reorder_subjects

        ordered = request.get("ordered_ids") or request.get("ids") or []
        if not isinstance(ordered, list):
            ordered = []
        reorder_subjects([str(x) for x in ordered])
        return {
            "id": request_id,
            "ok": True,
            "action": "life_subjects_reorder",
            "subjects": list_subjects(),
        }
    except Exception as exc:
        return _error_response(request_id, action="life_subjects_reorder", exc=exc)


def _handle_life_stack_get(request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import get_stack

        return {
            "id": request_id,
            "ok": True,
            "action": "life_stack_get",
            "stack": get_stack(),
        }
    except Exception as exc:
        return _error_response(request_id, action="life_stack_get", exc=exc)


def _handle_life_deck_snapshot(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import deck_snapshot

        thought_limit = int(request.get("thought_limit") or 32)
        document_limit = int(request.get("document_limit") or 5)
        snap = deck_snapshot(
            thought_limit=thought_limit,
            document_limit=document_limit,
        )
        return {
            "id": request_id,
            "ok": True,
            "action": "life_deck_snapshot",
            **snap,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_deck_snapshot", exc=exc)


def _handle_life_stack_set_primary(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import set_primary

        mid = request.get("mission_id")
        stack = set_primary(str(mid) if mid else None)
        return {
            "id": request_id,
            "ok": True,
            "action": "life_stack_set_primary",
            "stack": stack,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_stack_set_primary", exc=exc)


def _handle_life_stack_reorder(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import reorder_supporting

        ordered = request.get("ordered_ids") or request.get("ids") or []
        if not isinstance(ordered, list):
            ordered = []
        stack = reorder_supporting([str(x) for x in ordered])
        return {
            "id": request_id,
            "ok": True,
            "action": "life_stack_reorder",
            "stack": stack,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_stack_reorder", exc=exc)


def _handle_life_missions_list(request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import list_missions

        return {
            "id": request_id,
            "ok": True,
            "action": "life_missions_list",
            "missions": list_missions(),
        }
    except Exception as exc:
        return _error_response(request_id, action="life_missions_list", exc=exc)


def _handle_life_mission_get(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import get_mission

        mid = str(request.get("mission_id") or request.get("id") or "").strip()
        if not mid:
            return {
                "id": request_id,
                "ok": False,
                "action": "life_mission_get",
                "code": "INVALID_REQUEST",
                "error": "mission_id required",
                "message": "mission_id required",
                "retryable": False,
            }
        mission = get_mission(mid)
        if mission is None:
            return {
                "id": request_id,
                "ok": False,
                "action": "life_mission_get",
                "code": "NOT_FOUND",
                "error": "Mission not found",
                "message": "Mission not found",
                "retryable": False,
            }
        return {
            "id": request_id,
            "ok": True,
            "action": "life_mission_get",
            "mission": mission,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_mission_get", exc=exc)


def _handle_life_mission_put(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import put_mission

        fields = request.get("mission") if isinstance(request.get("mission"), dict) else request
        mission = put_mission(fields if isinstance(fields, dict) else {})
        return {
            "id": request_id,
            "ok": True,
            "action": "life_mission_put",
            "mission": mission,
            "message": "Saved. Life Mission changes apply on the next conversation.",
        }
    except Exception as exc:
        return _error_response(request_id, action="life_mission_put", exc=exc)


def _handle_life_target_put(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import put_target

        fields = request.get("target") if isinstance(request.get("target"), dict) else request
        target = put_target(fields if isinstance(fields, dict) else {})
        return {
            "id": request_id,
            "ok": True,
            "action": "life_target_put",
            "target": target,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_target_put", exc=exc)


def _handle_life_focus_set(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import set_focus_target

        mid = str(request.get("mission_id") or "").strip()
        tid = request.get("target_id")
        if not mid:
            return {
                "id": request_id,
                "ok": False,
                "action": "life_focus_set",
                "code": "INVALID_REQUEST",
                "error": "mission_id required",
                "message": "mission_id required",
                "retryable": False,
            }
        state = set_focus_target(mid, str(tid) if tid else None)
        return {
            "id": request_id,
            "ok": True,
            "action": "life_focus_set",
            "state": state,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_focus_set", exc=exc)


def _handle_life_sequence_validate(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import validate_sequence

        mid = str(request.get("mission_id") or "").strip()
        if not mid:
            return {
                "id": request_id,
                "ok": False,
                "action": "life_sequence_validate",
                "code": "INVALID_REQUEST",
                "error": "mission_id required",
                "message": "mission_id required",
                "retryable": False,
            }
        result = validate_sequence(mid)
        return {
            "id": request_id,
            "ok": True,
            "action": "life_sequence_validate",
            **result,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_sequence_validate", exc=exc)


def _handle_life_dreams_list(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import list_dreams

        include = bool(request.get("include_promoted"))
        return {
            "id": request_id,
            "ok": True,
            "action": "life_dreams_list",
            "dreams": list_dreams(include_promoted=include),
        }
    except Exception as exc:
        return _error_response(request_id, action="life_dreams_list", exc=exc)


def _handle_life_dream_put(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import put_dream

        fields = request.get("dream") if isinstance(request.get("dream"), dict) else request
        dream = put_dream(fields if isinstance(fields, dict) else {})
        return {
            "id": request_id,
            "ok": True,
            "action": "life_dream_put",
            "dream": dream,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_dream_put", exc=exc)


def _handle_life_dream_delete(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import delete_dream

        did = str(request.get("dream_id") or request.get("id") or "").strip()
        if not did:
            return {
                "id": request_id,
                "ok": False,
                "action": "life_dream_delete",
                "code": "INVALID_REQUEST",
                "error": "dream_id required",
                "message": "dream_id required",
                "retryable": False,
            }
        delete_dream(did)
        return {
            "id": request_id,
            "ok": True,
            "action": "life_dream_delete",
            "deleted": True,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_dream_delete", exc=exc)


def _handle_life_dream_promote(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import promote_dream

        did = str(request.get("dream_id") or request.get("id") or "").strip()
        if not did:
            return {
                "id": request_id,
                "ok": False,
                "action": "life_dream_promote",
                "code": "INVALID_REQUEST",
                "error": "dream_id required",
                "message": "dream_id required",
                "retryable": False,
            }
        result = promote_dream(did, subject_id=request.get("subject_id"))
        return {
            "id": request_id,
            "ok": True,
            "action": "life_dream_promote",
            **result,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_dream_promote", exc=exc)


def _handle_life_decisions_list(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import list_decisions

        mid = request.get("mission_id")
        limit = int(request.get("limit") or 50)
        return {
            "id": request_id,
            "ok": True,
            "action": "life_decisions_list",
            "decisions": list_decisions(
                mission_id=str(mid) if mid else None,
                limit=limit,
            ),
        }
    except Exception as exc:
        return _error_response(request_id, action="life_decisions_list", exc=exc)


def _handle_life_decision_log(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import log_decision

        fields = (
            request.get("decision") if isinstance(request.get("decision"), dict) else request
        )
        decision = log_decision(fields if isinstance(fields, dict) else {})
        return {
            "id": request_id,
            "ok": True,
            "action": "life_decision_log",
            "decision": decision,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_decision_log", exc=exc)


def _handle_life_documents_list(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import list_documents

        mid = request.get("mission_id")
        limit = int(request.get("limit") or 50)
        return {
            "id": request_id,
            "ok": True,
            "action": "life_documents_list",
            "documents": list_documents(
                mission_id=str(mid) if mid else None,
                limit=limit,
            ),
        }
    except Exception as exc:
        return _error_response(request_id, action="life_documents_list", exc=exc)


def _handle_life_documents_search(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import search_documents

        query = str(request.get("query") or request.get("q") or "")
        mid = request.get("mission_id")
        source = request.get("source")
        limit = int(request.get("limit") or 50)
        return {
            "id": request_id,
            "ok": True,
            "action": "life_documents_search",
            "documents": search_documents(
                query,
                source=str(source) if source else None,
                mission_id=str(mid) if mid else None,
                limit=limit,
            ),
            "query": query,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_documents_search", exc=exc)


def _handle_life_document_get(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import get_document

        did = str(
            request.get("document_id")
            or request.get("id")
            or ""
        ).strip()
        if not did:
            raise ValueError("document_id required")
        doc = get_document(did)
        if doc is None:
            raise ValueError("Document not found")
        return {
            "id": request_id,
            "ok": True,
            "action": "life_document_get",
            "document": doc,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_document_get", exc=exc)


def _handle_life_document_put(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import put_document

        fields = (
            request.get("document")
            if isinstance(request.get("document"), dict)
            else request
        )
        document = put_document(fields if isinstance(fields, dict) else {})
        return {
            "id": request_id,
            "ok": True,
            "action": "life_document_put",
            "document": document,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_document_put", exc=exc)


def _handle_life_document_assign(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import assign_document

        did = str(
            request.get("document_id") or request.get("id") or ""
        ).strip()
        mid = str(request.get("mission_id") or "").strip()
        announce = bool(request.get("announce", False))
        document = assign_document(did, mid, announce=announce)
        return {
            "id": request_id,
            "ok": True,
            "action": "life_document_assign",
            "document": document,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_document_assign", exc=exc)


def _handle_life_documents_import_scan(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import import_scanned_documents

        roots_raw = request.get("roots") or request.get("paths") or request.get("path")
        roots: list[str] | None
        if roots_raw is None:
            roots = None
        elif isinstance(roots_raw, str):
            roots = [roots_raw]
        elif isinstance(roots_raw, list):
            roots = [str(r) for r in roots_raw if str(r).strip()]
        else:
            roots = None
        mid = request.get("mission_id")
        include_plans = request.get("include_plans", True)
        include_outcomes = request.get("include_outcomes", True)
        max_files = int(request.get("max_files") or 2000)
        force_mission = bool(request.get("force_mission"))
        result = import_scanned_documents(
            roots=roots,
            mission_id=str(mid) if mid else None,
            force_mission=force_mission,
            include_plans=bool(include_plans),
            include_outcomes=bool(include_outcomes),
            max_files=max_files,
        )
        return {
            "id": request_id,
            "ok": True,
            "action": "life_documents_import_scan",
            **result,
        }
    except Exception as exc:
        return _error_response(
            request_id, action="life_documents_import_scan", exc=exc
        )


def _handle_life_thoughts_list(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import get_data_version, list_thoughts

        since = request.get("since")
        limit = int(request.get("limit") or 50)
        return {
            "id": request_id,
            "ok": True,
            "action": "life_thoughts_list",
            "thoughts": list_thoughts(
                since=str(since) if since else None,
                limit=limit,
            ),
            "data_version": get_data_version(),
        }
    except Exception as exc:
        return _error_response(request_id, action="life_thoughts_list", exc=exc)


def _handle_life_thought_post(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import post_thought

        fields = request.get("thought") if isinstance(request.get("thought"), dict) else request
        thought = post_thought(fields if isinstance(fields, dict) else {})
        return {
            "id": request_id,
            "ok": True,
            "action": "life_thought_post",
            "thought": thought,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_thought_post", exc=exc)


def _handle_life_context_resolve(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import resolve_context

        query = str(request.get("query") or request.get("message") or "")
        return {
            "id": request_id,
            "ok": True,
            "action": "life_context_resolve",
            "matches": resolve_context(query),
        }
    except Exception as exc:
        return _error_response(request_id, action="life_context_resolve", exc=exc)


def _handle_life_context_inject(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import inject_context

        message = str(request.get("message") or request.get("query") or "")
        current_view = request.get("current_view")
        if not isinstance(current_view, dict):
            current_view = {
                "mission_id": request.get("mission_id"),
                "target_id": request.get("target_id"),
                "subject_id": request.get("subject_id"),
            }
        result = inject_context(message, current_view=current_view)
        return {
            "id": request_id,
            "ok": True,
            "action": "life_context_inject",
            **result,
        }
    except Exception as exc:
        return _error_response(request_id, action="life_context_inject", exc=exc)


def _handle_life_snapshot(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.life_missions import snapshot_extras

        since = request.get("since")
        return {
            "id": request_id,
            "ok": True,
            "action": "life_snapshot",
            "snapshot": snapshot_extras(since=str(since) if since else None),
        }
    except Exception as exc:
        return _error_response(request_id, action="life_snapshot", exc=exc)


def _handle_memory_horizon_snapshot(request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.memory_horizon import build_memory_horizon_snapshot

        snapshot = build_memory_horizon_snapshot()
        return {
            "id": request_id,
            "ok": True,
            "action": "memory_horizon_snapshot",
            "snapshot": snapshot,
        }
    except Exception as exc:
        return _error_response(
            request_id, action="memory_horizon_snapshot", exc=exc
        )


def _handle_plans_list(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.plans import list_plans

        status = request.get("status")
        plans = list_plans(str(status) if status is not None else "all")
        return {
            "id": request_id,
            "ok": True,
            "action": "plans_list",
            "plans": plans,
        }
    except Exception as exc:
        return _error_response(request_id, action="plans_list", exc=exc)


def _handle_plan_get(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.plans import get_plan

        plan_id = str(request.get("plan_id") or "").strip()
        if not plan_id:
            return {
                "id": request_id,
                "ok": False,
                "action": "plan_get",
                "code": "INVALID_REQUEST",
                "error": "plan_id is required",
                "message": "plan_id is required",
            }
        plan = get_plan(plan_id)
        if plan is None:
            return {
                "id": request_id,
                "ok": False,
                "action": "plan_get",
                "code": "NOT_FOUND",
                "error": "Plan not found",
                "message": "Plan not found",
            }
        from centurion_cli.plans import _plan_to_ios

        return {
            "id": request_id,
            "ok": True,
            "action": "plan_get",
            "plan": _plan_to_ios(plan),
        }
    except Exception as exc:
        return _error_response(request_id, action="plan_get", exc=exc)


def _handle_plan_put(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.plans import put_plan

        payload = request.get("plan")
        if not isinstance(payload, dict):
            return {
                "id": request_id,
                "ok": False,
                "action": "plan_put",
                "code": "INVALID_REQUEST",
                "error": "plan object is required",
                "message": "plan object is required",
            }
        plan = put_plan(payload)
        return {
            "id": request_id,
            "ok": True,
            "action": "plan_put",
            "plan": plan,
            "message": "Plan saved.",
        }
    except Exception as exc:
        return _error_response(request_id, action="plan_put", exc=exc)


def _handle_plan_decide(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.plans import decide_plan

        plan_id = str(request.get("plan_id") or "").strip()
        choice = str(request.get("choice") or "").strip()
        if not plan_id or not choice:
            return {
                "id": request_id,
                "ok": False,
                "action": "plan_decide",
                "code": "INVALID_REQUEST",
                "error": "plan_id and choice are required",
                "message": "plan_id and choice are required",
            }
        note = request.get("note")
        plan = decide_plan(
            plan_id,
            choice,
            note=note,
            reviewer_customer_id=(
                str(request["reviewer_customer_id"]).strip()
                if request.get("reviewer_customer_id")
                else None
            ),
        )
        plan_title = ""
        related_mission = None
        if isinstance(plan, dict):
            plan_title = str(plan.get("title") or plan.get("goal") or plan_id)
            related_mission = plan.get("related_mission") or plan.get("mission_id")
        choice_labels = {
            "approve": "Approved — proceed",
            "reject": "Rejected",
            "request_changes": "Requested changes",
            "hold": "Held for later",
        }
        _record_life_decision(
            title=f"Plan · {plan_title or plan_id}",
            chosen=choice_labels.get(choice.lower(), choice),
            human_said=str(note or "").strip(),
            context=f"plan_decide:{plan_id}",
            options=["approve", "reject", "request_changes", "hold"],
            mission_id=str(related_mission).strip() if related_mission else None,
        )
        messages = {
            "approve": "Proceed recorded. Your Sovereign can continue with this plan.",
            "reject": "Plan rejected.",
            "request_changes": "Changes requested. Plan is ready to adjust.",
            "hold": "Plan held for later.",
        }
        return {
            "id": request_id,
            "ok": True,
            "action": "plan_decide",
            "plan": plan,
            "message": messages.get(choice.lower(), "Decision recorded."),
        }
    except KeyError:
        return {
            "id": request_id,
            "ok": False,
            "action": "plan_decide",
            "code": "NOT_FOUND",
            "error": "Plan not found",
            "message": "Plan not found",
        }
    except ValueError as exc:
        return {
            "id": request_id,
            "ok": False,
            "action": "plan_decide",
            "code": "INVALID_REQUEST",
            "error": str(exc),
            "message": str(exc),
        }
    except Exception as exc:
        return _error_response(request_id, action="plan_decide", exc=exc)


def _handle_plan_share(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.plans import share_plan

        plan_id = str(request.get("plan_id") or "").strip()
        reviewer = str(request.get("reviewer_customer_id") or "").strip()
        if not plan_id or not reviewer:
            return {
                "id": request_id,
                "ok": False,
                "action": "plan_share",
                "code": "INVALID_REQUEST",
                "error": "plan_id and reviewer_customer_id are required",
                "message": "plan_id and reviewer_customer_id are required",
            }
        plan = share_plan(
            plan_id,
            reviewer_customer_id=reviewer,
            role=str(request.get("role") or "observer"),
            board_id=(
                str(request["board_id"]).strip() if request.get("board_id") else None
            ),
        )
        return {
            "id": request_id,
            "ok": True,
            "action": "plan_share",
            "plan": plan,
            "message": "Plan shared for review.",
        }
    except KeyError:
        return {
            "id": request_id,
            "ok": False,
            "action": "plan_share",
            "code": "NOT_FOUND",
            "error": "Plan not found",
            "message": "Plan not found",
        }
    except ValueError as exc:
        return {
            "id": request_id,
            "ok": False,
            "action": "plan_share",
            "code": "INVALID_REQUEST",
            "error": str(exc),
            "message": str(exc),
        }
    except Exception as exc:
        return _error_response(request_id, action="plan_share", exc=exc)


def _handle_plan_comment(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.plans import comment_plan

        plan_id = str(request.get("plan_id") or "").strip()
        body = str(request.get("body") or "").strip()
        if not plan_id or not body:
            return {
                "id": request_id,
                "ok": False,
                "action": "plan_comment",
                "code": "INVALID_REQUEST",
                "error": "plan_id and body are required",
                "message": "plan_id and body are required",
            }
        plan = comment_plan(
            plan_id,
            body,
            author=str(request.get("author") or "owner"),
        )
        return {
            "id": request_id,
            "ok": True,
            "action": "plan_comment",
            "plan": plan,
            "message": "Comment added.",
        }
    except KeyError:
        return {
            "id": request_id,
            "ok": False,
            "action": "plan_comment",
            "code": "NOT_FOUND",
            "error": "Plan not found",
            "message": "Plan not found",
        }
    except ValueError as exc:
        return {
            "id": request_id,
            "ok": False,
            "action": "plan_comment",
            "code": "INVALID_REQUEST",
            "error": str(exc),
            "message": str(exc),
        }
    except Exception as exc:
        return _error_response(request_id, action="plan_comment", exc=exc)


def _handle_plan_templates_list(request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.plans import list_templates

        return {
            "id": request_id,
            "ok": True,
            "action": "plan_templates_list",
            "templates": list_templates(),
        }
    except Exception as exc:
        return _error_response(request_id, action="plan_templates_list", exc=exc)


def _handle_plan_template_instantiate(
    request: dict[str, Any], request_id: str
) -> dict[str, Any]:
    try:
        from centurion_cli.plans import instantiate_template

        template_id = str(request.get("template_id") or "").strip()
        if not template_id:
            return {
                "id": request_id,
                "ok": False,
                "action": "plan_template_instantiate",
                "code": "INVALID_REQUEST",
                "error": "template_id is required",
                "message": "template_id is required",
            }
        overrides = request.get("overrides")
        plan = instantiate_template(
            template_id,
            overrides if isinstance(overrides, dict) else None,
        )
        return {
            "id": request_id,
            "ok": True,
            "action": "plan_template_instantiate",
            "plan": plan,
            "message": "Plan created from template.",
        }
    except KeyError:
        return {
            "id": request_id,
            "ok": False,
            "action": "plan_template_instantiate",
            "code": "NOT_FOUND",
            "error": "Template not found",
            "message": "Template not found",
        }
    except Exception as exc:
        return _error_response(request_id, action="plan_template_instantiate", exc=exc)


def _handle_plan_save_template(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.plans import save_plan_as_template

        plan_id = str(request.get("plan_id") or "").strip()
        if not plan_id:
            return {
                "id": request_id,
                "ok": False,
                "action": "plan_save_template",
                "code": "INVALID_REQUEST",
                "error": "plan_id is required",
                "message": "plan_id is required",
            }
        title = request.get("title")
        tmpl = save_plan_as_template(
            plan_id,
            title=str(title).strip() if title else None,
        )
        return {
            "id": request_id,
            "ok": True,
            "action": "plan_save_template",
            "template": tmpl,
            "message": "Saved as template.",
        }
    except KeyError:
        return {
            "id": request_id,
            "ok": False,
            "action": "plan_save_template",
            "code": "NOT_FOUND",
            "error": "Plan not found",
            "message": "Plan not found",
        }
    except Exception as exc:
        return _error_response(request_id, action="plan_save_template", exc=exc)


def _ensure_fleet_toolset_enabled() -> None:
    """Enable the fleet toolset when at least one peer has an address."""
    try:
        from centurion_cli.config import load_config, save_config

        cfg = load_config()
        changed = False
        tools = cfg.setdefault("tools", {})
        for platform in ("remote", "cli", "telegram"):
            plat = tools.setdefault(platform, {})
            disabled = plat.get("disabled")
            if isinstance(disabled, list) and "fleet" in disabled:
                plat["disabled"] = [x for x in disabled if x != "fleet"]
                changed = True
            enabled = plat.get("enabled")
            if isinstance(enabled, list) and "fleet" not in enabled:
                plat["enabled"] = list(enabled) + ["fleet"]
                changed = True
        platform_toolsets = cfg.setdefault("platform_toolsets", {})
        for platform in ("remote", "cli", "telegram"):
            current = platform_toolsets.get(platform)
            if isinstance(current, list) and "fleet" not in current:
                platform_toolsets[platform] = list(current) + ["fleet"]
                changed = True
        if changed:
            save_config(cfg)
    except Exception:
        logger.debug("remote_bridge: could not enable fleet toolset", exc_info=True)


def _handle_fleet_status(request_id: str) -> dict[str, Any]:
    try:
        from tools.fleet_tools import fleet_status_tool

        raw = fleet_status_tool({})
        payload = json.loads(raw) if isinstance(raw, str) else raw
        if not isinstance(payload, dict):
            raise ValueError("Unexpected fleet status payload")
        ok = bool(payload.get("success", True)) and not payload.get("error")
        return {
            "id": request_id,
            "ok": ok,
            "action": "fleet_status",
            "self_id": payload.get("self_id"),
            "health": payload.get("health"),
            "peers": payload.get("peers") or [],
            "peer_count": payload.get("peer_count") or 0,
            "message": payload.get("error") or payload.get("message"),
        }
    except Exception as exc:
        return _error_response(request_id, action="fleet_status", exc=exc)


def _handle_fleet_ping(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from tools.fleet_tools import fleet_ping_tool

        peer_id = str(request.get("peer_id") or request.get("name") or "").strip()
        raw = fleet_ping_tool({"peer_id": peer_id})
        payload = json.loads(raw) if isinstance(raw, str) else raw
        if not isinstance(payload, dict):
            raise ValueError("Unexpected fleet ping payload")
        ok = bool(payload.get("success", False))
        return {
            "id": request_id,
            "ok": ok,
            "action": "fleet_ping",
            "peer": payload,
            "message": payload.get("error") or payload.get("note") or payload.get("status"),
        }
    except Exception as exc:
        return _error_response(request_id, action="fleet_ping", exc=exc)


def _handle_fleet_peer_put(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion.fleet.peers import FleetPeer, FleetPeers

        peer_id = str(request.get("peer_id") or request.get("id") or "").strip()
        name = str(request.get("name") or peer_id).strip()
        address = str(request.get("address") or "").strip()
        auth_token = str(request.get("auth_token") or request.get("token") or "").strip()
        if not peer_id:
            return {
                "id": request_id,
                "ok": False,
                "action": "fleet_peer_put",
                "code": "INVALID_REQUEST",
                "error": "peer_id is required",
                "message": "peer_id is required",
            }
        peers = FleetPeers()
        existing = peers.get(peer_id)
        peer = FleetPeer(
            centurion_id=peer_id,
            name=name or (existing.name if existing else peer_id),
            address=address if address else (existing.address if existing else ""),
            auth_token=auth_token
            if auth_token
            else (existing.auth_token if existing else ""),
            telegram_handle=existing.telegram_handle if existing else "",
            status=existing.status if existing else "unknown",
            last_seen=existing.last_seen if existing else 0.0,
        )
        peers.register(peer)
        if peer.address:
            _ensure_fleet_toolset_enabled()
        return {
            "id": request_id,
            "ok": True,
            "action": "fleet_peer_put",
            "peer": {
                "id": peer.centurion_id,
                "name": peer.name,
                "address": peer.address,
                "status": peer.status,
                "has_token": bool(peer.auth_token),
            },
            "message": f"Saved peer {peer.name}.",
        }
    except Exception as exc:
        return _error_response(request_id, action="fleet_peer_put", exc=exc)


def _handle_plugin_list(request_id: str) -> dict[str, Any]:
    """Client plugin seam v0 — list discovered agent plugins for Brain Settings."""
    try:
        from centurion_cli.plugins import discover_plugins, get_plugin_manager

        discover_plugins()
        plugins = get_plugin_manager().list_plugins()
        return {
            "id": request_id,
            "ok": True,
            "action": "plugin_list",
            "plugins": plugins,
            "count": len(plugins),
            "message": (
                "Agent plugins extend tools and hooks. They do not automatically "
                "add Brain UI — see developer-guide/client-plugins.md."
            ),
        }
    except Exception as exc:
        return _error_response(request_id, action="plugin_list", exc=exc)


def _handle_tools_skills_snapshot(request_id: str) -> dict[str, Any]:
    """Read-only toolsets + skill names for Brain Settings."""
    try:
        from centurion_cli.config import load_config
        from centurion_cli.tools_config import _get_platform_tools

        cfg = load_config()
        toolsets = sorted(_get_platform_tools(cfg, "remote") or _get_platform_tools(cfg, "cli") or [])
        skills: list[str] = []
        try:
            from pathlib import Path

            from centurion_constants import get_centurion_home

            skills_root = get_centurion_home() / "skills"
            if skills_root.is_dir():
                for path in sorted(skills_root.rglob("SKILL.md")):
                    name = path.parent.name
                    if name and name not in skills:
                        skills.append(name)
        except Exception:
            logger.debug("tools_skills_snapshot: skill scan failed", exc_info=True)
        return {
            "id": request_id,
            "ok": True,
            "action": "tools_skills_snapshot",
            "toolsets": toolsets,
            "skills": skills,
            "message": "Manage via centurion tools / skills (next session unless --now).",
        }
    except Exception as exc:
        return _error_response(request_id, action="tools_skills_snapshot", exc=exc)


def _handle_ops_glance(request_id: str) -> dict[str, Any]:
    """Home pulse glance: next cron jobs + blocked/ready kanban tasks."""
    cron_jobs: list[dict[str, Any]] = []
    kanban_tasks: list[dict[str, Any]] = []
    try:
        from cron.jobs import list_jobs

        for job in list_jobs()[:8]:
            if not isinstance(job, dict):
                continue
            if job.get("paused") or job.get("enabled") is False:
                continue
            cron_jobs.append(
                {
                    "id": job.get("id") or job.get("job_id") or "",
                    "name": job.get("name") or job.get("title") or job.get("id") or "job",
                    "schedule": job.get("schedule") or job.get("next_run") or "",
                    "next_run": job.get("next_run") or job.get("next_run_at") or "",
                }
            )
    except Exception:
        logger.debug("ops_glance: cron unavailable", exc_info=True)
    try:
        import centurion_cli.kanban_db as kb

        with kb.connect() as conn:
            rows = kb.list_tasks(conn, limit=24)
            for row in rows or []:
                status = str(getattr(row, "status", "") or "").lower()
                if status not in {"blocked", "ready", "in_progress", "todo", "open"}:
                    continue
                kanban_tasks.append(
                    {
                        "id": str(getattr(row, "id", "") or ""),
                        "title": str(getattr(row, "title", "") or getattr(row, "name", "") or "task"),
                        "status": status,
                    }
                )
                if len(kanban_tasks) >= 8:
                    break
    except Exception:
        logger.debug("ops_glance: kanban unavailable", exc_info=True)
    return {
        "id": request_id,
        "ok": True,
        "action": "ops_glance",
        "cron": cron_jobs,
        "kanban": kanban_tasks,
    }


def _handle_client_plugin_cards(request_id: str) -> dict[str, Any]:
    """Client plugin seam v1 — declarative Home/Settings cards from manifests."""
    cards: list[dict[str, Any]] = []
    try:
        from pathlib import Path

        from centurion_constants import get_centurion_home

        roots = [
            get_centurion_home() / "plugins",
            Path(__file__).resolve().parents[1] / "plugins",
        ]
        seen: set[str] = set()
        for root in roots:
            if not root.is_dir():
                continue
            for manifest in root.rglob("manifest.json"):
                # Prefer dashboard/ or client/ brain manifests
                parent_name = manifest.parent.name.lower()
                if parent_name not in {"dashboard", "client", "brain"}:
                    # Also accept plugin.yaml sibling with client section via JSON only here
                    if "dashboard" not in str(manifest) and "client" not in str(manifest):
                        continue
                try:
                    data = json.loads(manifest.read_text(encoding="utf-8"))
                except Exception:
                    continue
                if not isinstance(data, dict):
                    continue
                client = data.get("client") or data.get("brain") or data
                if not isinstance(client, dict):
                    continue
                title = str(client.get("title") or data.get("name") or manifest.parent.parent.name).strip()
                if not title or title in seen:
                    continue
                seen.add(title)
                cards.append(
                    {
                        "id": str(client.get("id") or title).strip(),
                        "title": title,
                        "subtitle": str(client.get("subtitle") or client.get("description") or "").strip(),
                        "surface": str(client.get("surface") or "home").strip().lower(),
                        "ask_prompt": str(client.get("ask_prompt") or f"Tell me about {title}.").strip(),
                    }
                )
                if len(cards) >= 12:
                    break
            if len(cards) >= 12:
                break
    except Exception:
        logger.debug("client_plugin_cards failed", exc_info=True)
    return {
        "id": request_id,
        "ok": True,
        "action": "client_plugin_cards",
        "cards": cards,
        "count": len(cards),
    }


def _read_request() -> dict[str, Any]:
    import os

    # Evented chat keeps stdin open for approval_respond follow-ups, so the
    # initial request must be one JSON line (not a full-stream read).
    if os.environ.get("CENTURION_REMOTE_EVENTS", "").strip().lower() in {
        "1",
        "true",
        "yes",
    }:
        raw = sys.stdin.readline()
    else:
        raw = sys.stdin.read()
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise ValueError("request must be a JSON object")
    return value


def default_bridge_socket_path() -> str:
    """Unix socket path for the persistent Brain bridge daemon."""
    import os

    override = (os.environ.get("CENTURION_BRIDGE_SOCKET") or "").strip()
    if override:
        return override
    try:
        from centurion_constants import get_centurion_home

        home = get_centurion_home()
    except Exception:
        from pathlib import Path

        home = Path(os.environ.get("CENTURION_HOME") or (Path.home() / ".centurion"))
    return str(home / "run" / "bridge.sock")


def _warm_bridge_imports() -> None:
    """Best-effort eager imports so the first chat is not the coldest path.

    Runs off the accept loop so Focus/life reads are not blocked on run_agent.
    """
    try:
        from centurion_cli.config import load_config

        load_config()
    except Exception:
        pass
    try:
        import centurion_cli.life_missions  # noqa: F401
    except Exception:
        pass
    try:
        import centurion_state  # noqa: F401
    except Exception:
        pass
    try:
        import run_agent  # noqa: F401
    except Exception:
        pass
    try:
        from run_agent import AIAgent  # noqa: F401
    except Exception:
        pass
    try:
        from centurion_cli.life_missions import ensure_schema_once

        ensure_schema_once()
    except Exception:
        pass


_CHAT_SERVE_LOCK: Any = None


def _chat_serve_lock():
    global _CHAT_SERVE_LOCK
    import threading

    if _CHAT_SERVE_LOCK is None:
        _CHAT_SERVE_LOCK = threading.Lock()
    return _CHAT_SERVE_LOCK


def _events_requested(request: dict[str, Any]) -> bool:
    if request.get("events") in (True, 1, "1", "true", "yes"):
        return True
    return _remote_events_enabled()


def _close_socket_conn(conn: Any, rfile: Any = None) -> None:
    if rfile is not None:
        try:
            rfile.close()
        except Exception:
            pass
    try:
        conn.close()
    except Exception:
        pass


def _serve_parsed_socket_request(
    conn: Any,
    rfile: Any,
    request: dict[str, Any],
) -> None:
    """Handle an already-parsed bridge request on the current worker thread."""
    import os
    import threading

    write_lock = threading.Lock()

    def _write_bytes(data: bytes) -> None:
        with write_lock:
            try:
                conn.sendall(data)
            except OSError:
                pass

    action = str(request.get("action") or "chat").strip().lower()
    events = action == "chat" and _events_requested(request)

    if events:
        os.environ["CENTURION_REMOTE_EVENTS"] = "1"
        _set_event_sink(_write_bytes)
        approval_key = (
            f"remote:{request.get('id') or request.get('session_id') or 'turn'}"
        )

        def _readline() -> str:
            try:
                line = rfile.readline()
            except OSError:
                return ""
            if not line:
                return ""
            return line.decode("utf-8", errors="replace")

        _start_approval_line_reader(approval_key, _readline)
        try:
            with _chat_serve_lock():
                # Early activity so the Brain UI is never blank during residual warm-up.
                _emit_remote_event(
                    {
                        "centurion_event": "activity",
                        "kind": "status",
                        "event": "lifecycle",
                        "message": "Starting…",
                        "line": "Starting…",
                    }
                )
                try:
                    response = handle_request(request)
                except Exception as exc:
                    code, message = classify_llm_error(exc)
                    response = {
                        "id": str(request.get("id") or ""),
                        "ok": False,
                        "code": code,
                        "error": message,
                        "message": message,
                        "retryable": False,
                    }
        finally:
            _set_event_sink(None)
    else:
        try:
            if action == "chat":
                with _chat_serve_lock():
                    response = handle_request(request)
            else:
                response = handle_request(request)
        except Exception as exc:
            code, message = classify_llm_error(exc)
            response = {
                "id": str(request.get("id") or ""),
                "ok": False,
                "code": code,
                "error": message,
                "message": message,
                "retryable": False,
            }

    _write_bytes((json.dumps(response, ensure_ascii=False) + "\n").encode("utf-8"))
    _close_socket_conn(conn, rfile)


def _handle_socket_connection(
    conn: Any,
    addr: Any = None,
    chat_pool: Any = None,
) -> None:
    """Read one request; chat may re-route onto ``chat_pool`` to free control workers."""
    import threading

    del addr  # unused; accept() returns it for AF_UNIX compatibility
    conn.settimeout(None)
    rfile = conn.makefile("rb")
    write_lock = threading.Lock()

    def _write_bytes(data: bytes) -> None:
        with write_lock:
            try:
                conn.sendall(data)
            except OSError:
                pass

    try:
        raw = rfile.readline()
        if not raw:
            _close_socket_conn(conn, rfile)
            return
        request = json.loads(raw.decode("utf-8"))
        if not isinstance(request, dict):
            raise ValueError("request must be a JSON object")
    except Exception as exc:
        code, message = classify_llm_error(exc)
        _write_bytes(
            (
                json.dumps(
                    {
                        "id": "",
                        "ok": False,
                        "code": code,
                        "error": message,
                        "message": message,
                        "retryable": False,
                    },
                    ensure_ascii=False,
                )
                + "\n"
            ).encode("utf-8")
        )
        _close_socket_conn(conn, rfile)
        return

    action = str(request.get("action") or "chat").strip().lower()
    if action == "chat" and chat_pool is not None:
        # Transfer connection ownership so this control worker frees immediately.
        chat_pool.submit(_serve_parsed_socket_request, conn, rfile, request)
        return

    _serve_parsed_socket_request(conn, rfile, request)


def serve_bridge(
    socket_path: str | None = None,
    *,
    workers: int = 4,
    chat_workers: int = 1,
) -> int:
    """Run the persistent Unix-socket bridge daemon (Brain latency path)."""
    import os
    import signal
    import socket
    import threading
    from concurrent.futures import ThreadPoolExecutor
    from pathlib import Path

    try:
        from centurion_cli.profiles import apply_sticky_profile_home

        apply_sticky_profile_home()
    except Exception:
        pass

    path = socket_path or default_bridge_socket_path()
    sock_file = Path(path)
    sock_file.parent.mkdir(parents=True, exist_ok=True)
    if sock_file.exists():
        try:
            sock_file.unlink()
        except OSError:
            pass

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(path)
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
    server.listen(32)
    server.settimeout(1.0)

    stop = threading.Event()

    def _shutdown(*_args: Any) -> None:
        stop.set()

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    # Accept immediately — do not block the listen loop on run_agent imports.
    # Chat warms in the background; life_/soul_/session_ stay cold-fast.
    logger.info(
        "Centurion bridge daemon listening on %s (workers=%s chat_workers=%s)",
        path,
        max(1, workers),
        max(1, chat_workers),
    )
    threading.Thread(
        target=_warm_bridge_imports,
        name="bridge-warm-imports",
        daemon=True,
    ).start()

    with (
        ThreadPoolExecutor(max_workers=max(1, workers)) as control_pool,
        ThreadPoolExecutor(max_workers=max(1, chat_workers)) as chat_pool,
    ):
        try:
            while not stop.is_set():
                try:
                    conn, addr = server.accept()
                except socket.timeout:
                    continue
                except OSError:
                    if stop.is_set():
                        break
                    continue
                # Control pool reads the request, then re-routes chat onto chat_pool.
                control_pool.submit(
                    _handle_socket_connection, conn, addr, chat_pool
                )
        finally:
            try:
                server.close()
            except OSError:
                pass
            try:
                if sock_file.exists():
                    sock_file.unlink()
            except OSError:
                pass
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Local bridge used by the native Centurion remote service."
    )
    parser.add_argument(
        "--serve",
        action="store_true",
        help="Run as a persistent Unix-socket daemon (Brain).",
    )
    parser.add_argument(
        "--socket",
        default=None,
        help="Unix socket path for --serve (default: $CENTURION_HOME/run/bridge.sock).",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=4,
        help="Control thread-pool size for --serve (default: 4).",
    )
    parser.add_argument(
        "--chat-workers",
        type=int,
        default=1,
        help="Chat thread-pool size for --serve (default: 1).",
    )
    args = parser.parse_args(argv)

    if args.serve:
        return serve_bridge(
            args.socket,
            workers=args.workers,
            chat_workers=args.chat_workers,
        )

    try:
        from centurion_cli.profiles import apply_sticky_profile_home

        apply_sticky_profile_home()
    except Exception:
        pass

    try:
        request = _read_request()
        response = handle_request(request)
    except Exception as exc:
        code, message = classify_llm_error(exc)
        response = {
            "id": "",
            "ok": False,
            "code": code,
            "error": message,
            "message": message,
            "retryable": False,
        }

    sys.stdout.write(json.dumps(response, ensure_ascii=False))
    sys.stdout.write("\n")
    return 0 if response.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
