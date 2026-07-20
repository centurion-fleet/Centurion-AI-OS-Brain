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
    run_agent: Callable[[str], str] | None,
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

    if run_agent is None:
        run_agent = _run_agent_quiet

    routed_connector_id = None
    routed_display_name = ""
    try:
        if get_routing_mode() == "phoenix":
            from centurion_cli.phoenix_router import describe_route, resolve as phoenix_resolve

            routed_connector_id = phoenix_resolve(text.strip())
            if routed_connector_id:
                switch = apply_remote_switch(routed_connector_id, probe=False)
                if switch.ok:
                    routed_display_name = describe_route(routed_connector_id)
    except Exception:
        routed_connector_id = None

    try:
        response = run_agent(text.strip())
        record_successful_turn()
        payload = {
            "id": request_id,
            "ok": True,
            "action": "chat",
            "text": response or "",
        }
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
        payload = {
            "id": request_id,
            "ok": bool(result.get("ok")),
            "action": "remote_model_save_key",
            "result": result,
        }
        if not result.get("ok"):
            payload["message"] = result.get("message", "Could not save API key.")
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


def _run_agent_quiet(text: str) -> str:
    """Run one agent turn without polluting stdout (bridge response must be pure JSON)."""
    import logging
    import os
    from contextlib import redirect_stderr, redirect_stdout

    from centurion_cli.oneshot import _run_agent
    from centurion_cli.oversight import should_enable_remote_yolo

    logging.disable(logging.CRITICAL)
    # Only max-autonomy (or approvals.mode=off) gets YOLO on remote chat.
    # Lower levels rely on host approval / deny paths instead of auto-approving.
    if should_enable_remote_yolo():
        os.environ.setdefault("CENTURION_YOLO_MODE", "1")
    else:
        os.environ.pop("CENTURION_YOLO_MODE", None)
    os.environ.setdefault("CENTURION_ACCEPT_HOOKS", "1")
    os.environ["CENTURION_DISABLE_OPENROUTER"] = "1"
    os.environ["CENTURION_PLATFORM"] = "remote"
    with open(os.devnull, "w", encoding="utf-8") as devnull, redirect_stdout(
        devnull
    ), redirect_stderr(devnull):
        return _run_agent(text) or ""


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


def _read_request() -> dict[str, Any]:
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
