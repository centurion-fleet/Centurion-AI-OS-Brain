"""Local stdio bridge from the native Linux remote service to Centurion.

The bridge deliberately has no network listener. ``centurion-remote`` owns the
encrypted LAN boundary and invokes this module with a JSON request on stdin.
Keeping the Python process behind stdio prevents the full dashboard/admin API
from being exposed to the local network.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Callable
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
    if action == "session_resume":
        return _handle_session_resume(request, request_id)
    if action == "session_history":
        return _handle_session_history(request, request_id)
    if action == "approval_respond":
        return _handle_approval_respond(request, request_id)

    code, message = classify_llm_error(ValueError(f"unsupported action: {action}"))
    return {
        "id": request_id,
        "ok": False,
        "action": action,
        "code": "UNSUPPORTED_ACTION",
        "error": message,
        "message": message,
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

    session_id = str(request.get("session_id") or "").strip() or None
    using_default_agent = run_agent is None
    if run_agent is None:
        run_agent = _run_agent_quiet
    if using_default_agent and not session_id:
        try:
            session_id = _ensure_remote_session()
        except Exception:
            session_id = None

    routed_connector_id = None
    routed_display_name = ""
    try:
        if get_routing_mode() == "phoenix":
            from centurion_cli.phoenix_router import describe_route, resolve as phoenix_resolve

            routed_connector_id = phoenix_resolve(text.strip(), categories={"text"})
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
                text.strip(),
                session_id=session_id,
                request_id=request_id,
            )
        except TypeError:
            response = run_agent(text.strip())
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
            retry_text=text.strip(),
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
        return {
            "id": request_id,
            "ok": True,
            "action": "swarm_snapshot",
            "snapshot": snapshot,
        }
    except Exception as exc:
        return _error_response(request_id, action="swarm_snapshot", exc=exc)


def _handle_swarm_connect(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    """Join a friend collaboration — same fields as ``centurion swarm connect``."""
    try:
        from gateway.swarm_mc import save_mc_config
        from centurion_cli.config import load_config, save_config

        token = str(request.get("token") or "").strip()
        install_id = str(request.get("install_id") or "").strip()
        project_id = str(request.get("project_id") or "").strip()

        if not token.startswith("ctk_proj_"):
            return {
                "id": request_id,
                "ok": False,
                "action": "swarm_connect",
                "code": "INVALID_REQUEST",
                "error": "Provide a Mission Control project token (ctk_proj_...).",
                "message": "Provide a Mission Control project token (ctk_proj_...).",
                "retryable": False,
            }
        if not install_id or not project_id:
            return {
                "id": request_id,
                "ok": False,
                "action": "swarm_connect",
                "code": "INVALID_REQUEST",
                "error": "Project id and install id are required.",
                "message": "Project id and install id are required.",
                "retryable": False,
            }

        save_mc_config(project_id, token, install_id)
        config = load_config() or {}
        platforms = config.setdefault("platforms", {})
        mc = platforms.setdefault("swarm_mc", {})
        if isinstance(mc, dict):
            mc["enabled"] = True
            mc["project_id"] = project_id
            mc["install_id"] = install_id
        save_config(config)

        return {
            "id": request_id,
            "ok": True,
            "action": "swarm_connect",
            "message": "Mission Control connected. Collaborations will refresh on the next snapshot.",
            "result": {
                "project_id": project_id,
                "install_id": install_id,
            },
        }
    except Exception as exc:
        return _error_response(request_id, action="swarm_connect", exc=exc)


def _handle_swarm_invite(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    """Invite another Centurion owner's customer id onto the current swarm project."""
    try:
        from gateway.swarm_mc import SwarmMcClient, load_mc_config

        invited = str(request.get("invited_customer_id") or "").strip()
        project_id = str(request.get("project_id") or "").strip()
        role = str(request.get("role") or "operator").strip() or "operator"

        mc = load_mc_config()
        if not project_id:
            project_id = str(mc.get("project_id") or "").strip()
        token = str(mc.get("project_token") or "").strip()
        install_id = str(mc.get("install_id") or "").strip()
        if not project_id or not token or not install_id:
            return {
                "id": request_id,
                "ok": False,
                "action": "swarm_invite",
                "code": "NOT_CONNECTED",
                "error": "Connect this Centurion to Mission Control before inviting a friend.",
                "message": "Connect this Centurion to Mission Control before inviting a friend.",
                "retryable": False,
            }
        if not invited:
            return {
                "id": request_id,
                "ok": False,
                "action": "swarm_invite",
                "code": "INVALID_REQUEST",
                "error": "Friend customer id is required.",
                "message": "Friend customer id is required.",
                "retryable": False,
            }

        client = SwarmMcClient(project_token=token, install_id=install_id)
        result = client.invite_friend(project_id, invited, role=role)
        return {
            "id": request_id,
            "ok": True,
            "action": "swarm_invite",
            "message": "Invite sent. Ask your friend to accept and connect their Centurion.",
            "result": result if isinstance(result, dict) else {"raw": result},
        }
    except Exception as exc:
        return _error_response(request_id, action="swarm_invite", exc=exc)


def _handle_swarm_resolve_signal(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.swarm_state import resolve_signal

        signal_id = str(request.get("signal_id") or "").strip()
        choice_note = str(request.get("choice_note") or "").strip()
        result = resolve_signal(signal_id, choice_note=choice_note)
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


def _error_response(
    request_id: str,
    *,
    action: str,
    exc: BaseException,
    retryable: bool = False,
    attempt_recovery: bool = False,
    retry_text: str = "",
    run_agent: Callable[[str], str] | None = None,
) -> dict[str, Any]:
    code, message = classify_llm_error(exc)
    if attempt_recovery and load_last_known_good() is not None:
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
        "retryable": retryable or code in {"LLM_RATE_LIMIT", "LLM_UNAVAILABLE"},
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


def _run_agent_quiet(
    text: str,
    *,
    session_id: str | None = None,
    request_id: str | None = None,
) -> str:
    """Run one agent turn without polluting stdout (bridge response must be pure JSON).

    When remote events are enabled (NDJSON on stdout), approval prompts are
    emitted as ``{"centurion_event":"approval_request",...}`` lines and the
    final response is still a single JSON object on stdout. Stderr stays quiet.
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
            # Write to the real stdout FD so redirect_stdout(devnull) cannot
            # swallow approval events during the agent turn.
            os.write(1, (json.dumps(event, ensure_ascii=False) + "\n").encode("utf-8"))

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


def _start_approval_stdin_reader(default_session_key: str) -> None:
    """Read follow-up approval_respond lines from stdin while the agent runs."""
    global _approval_stdin_started, _approval_stdin_lock
    import threading

    if _approval_stdin_lock is None:
        _approval_stdin_lock = threading.Lock()
    with _approval_stdin_lock:
        if _approval_stdin_started:
            return
        _approval_stdin_started = True

    def _loop() -> None:
        from tools.approval import resolve_gateway_approval

        while True:
            line = sys.stdin.readline()
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

    threading.Thread(target=_loop, name="remote-approval-stdin", daemon=True).start()


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
    toolsets_list = sorted(_get_platform_tools(cfg, "cli"))
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
    )
    agent.suppress_status_output = True
    agent.stream_delta_callback = None
    agent.tool_gen_callback = None

    result = agent.run_conversation(
        user_message=text,
        conversation_history=history or None,
        task_id=session_id,
    )
    if isinstance(result, dict):
        return str(result.get("final_response") or result.get("response") or "")
    return str(result or "")


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


def _handle_session_new(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        title = str(request.get("title") or "").strip() or None
        session_id = _ensure_remote_session(title=title)
        return {
            "id": request_id,
            "ok": True,
            "action": "session_new",
            "session_id": session_id,
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


def _handle_soul_get(request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.soul_sync import read_soul

        soul = read_soul()
        return {
            "id": request_id,
            "ok": True,
            "action": "soul_get",
            "soul": soul,
        }
    except Exception as exc:
        return _error_response(request_id, action="soul_get", exc=exc)


def _handle_soul_put(request: dict[str, Any], request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.soul_sync import write_soul

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
        soul = write_soul(
            fields if isinstance(fields, dict) else None,
            markdown=markdown if isinstance(markdown, str) else None,
        )
        return {
            "id": request_id,
            "ok": True,
            "action": "soul_put",
            "soul": soul,
            "message": "Saved. Soul changes apply on the next conversation.",
        }
    except Exception as exc:
        return _error_response(request_id, action="soul_put", exc=exc)


def _handle_mission_get(request_id: str) -> dict[str, Any]:
    try:
        from centurion_cli.mission_sync import read_mission

        mission = read_mission()
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
        from centurion_cli.mission_sync import write_mission

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
        mission = write_mission(
            fields if isinstance(fields, dict) else None,
            markdown=markdown if isinstance(markdown, str) else None,
        )
        return {
            "id": request_id,
            "ok": True,
            "action": "mission_put",
            "mission": mission,
            "message": "Saved. Life Mission changes apply on the next conversation.",
        }
    except Exception as exc:
        return _error_response(request_id, action="mission_put", exc=exc)


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
        plan = decide_plan(
            plan_id,
            choice,
            note=request.get("note"),
            reviewer_customer_id=(
                str(request["reviewer_customer_id"]).strip()
                if request.get("reviewer_customer_id")
                else None
            ),
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


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Local bridge used by the native Centurion remote service."
    )
    parser.parse_args(argv)

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
