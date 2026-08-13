"""Brain-side Chat-from-anywhere relay control + outbound presence.

LAN Crypto Chat (:9119) is unchanged. When ``remote_relay.enabled`` is true,
the Brain dials *out* to Centurion Supabase Realtime and advertises presence
so the App Store iPhone can reach the same bridge without a home IP.

This module owns:
- reading ``remote_relay`` config
- minting/storing install_id
- building RelaySession envelopes for opaque Crypto Chat frames
- bridge actions: ``remote_relay_status`` / ``remote_relay_enable`` / ``remote_relay_disable``

The live Supabase websocket client is intentionally thin here — operators
point ``supabase_url`` + anon/service credentials at the Centurion project;
Vercel mint/revoke lives under ``cloud/remote-relay/``.
"""

from __future__ import annotations

import hashlib
import logging
import secrets
import threading
import time
import uuid
from typing import Any

from centurion_cli.relay_transport import RelaySession, new_conn_id

logger = logging.getLogger(__name__)

_STATE_LOCK = threading.Lock()
_SESSION: RelaySession | None = None
_REALTIME = None  # RelayRealtimeClient | None — set lazily to avoid circular import
_PRESENCE: dict[str, Any] = {
    "online": False,
    "conn_epoch": None,
    "last_error": None,
    "updated_at": None,
}


def _load_config() -> dict[str, Any]:
    try:
        from centurion_cli.config import load_config

        cfg = load_config() or {}
        section = cfg.get("remote_relay")
        return section if isinstance(section, dict) else {}
    except Exception:
        return {}


def _save_config_patch(patch: dict[str, Any]) -> None:
    try:
        from centurion_cli.config import load_config, save_config

        cfg = load_config() or {}
        section = dict(cfg.get("remote_relay") or {})
        section.update(patch)
        cfg["remote_relay"] = section
        save_config(cfg)
    except Exception as exc:
        logger.warning("remote_relay config save failed: %s", exc)


def ensure_install_id() -> str:
    cfg = _load_config()
    install_id = str(cfg.get("install_id") or "").strip()
    if install_id:
        return install_id
    install_id = f"brain_{uuid.uuid4().hex[:16]}"
    _save_config_patch({"install_id": install_id})
    return install_id


def channel_name(install_id: str | None = None) -> str:
    cfg = _load_config()
    prefix = str(cfg.get("channel_prefix") or "brain").strip() or "brain"
    iid = (install_id or ensure_install_id()).strip()
    return f"{prefix}:{iid}"


def get_relay_session() -> RelaySession:
    global _SESSION
    with _STATE_LOCK:
        if _SESSION is None:
            cfg = _load_config()
            max_reassembled = int(cfg.get("max_reassembled_bytes") or 1_048_576)
            _SESSION = RelaySession(max_reassembled=max_reassembled)
        return _SESSION


def _websockets_installed() -> bool:
    try:
        import websockets  # type: ignore  # noqa: F401

        return True
    except ImportError:
        return False


def status() -> dict[str, Any]:
    cfg = _load_config()
    with _STATE_LOCK:
        presence = dict(_PRESENCE)
    # Anon key is safe to return over Crypto Chat so the phone can cache
    # cloud endpoints for away reconnect (same class as public Supabase anon).
    anon = str(cfg.get("supabase_anon_key") or "").strip()
    ws_ok = _websockets_installed()
    enabled = bool(cfg.get("enabled"))
    return {
        "enabled": enabled,
        "install_id": str(cfg.get("install_id") or ""),
        "channel": channel_name(str(cfg.get("install_id") or "") or None)
        if cfg.get("install_id")
        else "",
        "supabase_url": str(cfg.get("supabase_url") or "").strip(),
        "supabase_url_configured": bool(str(cfg.get("supabase_url") or "").strip()),
        "supabase_anon_key": anon,
        "websockets_installed": ws_ok,
        "realtime_pipe_ready": bool(enabled and ws_ok and presence.get("online")),
        "presence": presence,
        "lan_crypto_chat": {
            "port": 9119,
            "unchanged": True,
            "preferred_when_reachable": True,
        },
        "hint": (
            None
            if ws_ok
            else "Install Away deps: pip install 'centurionai-os[remote-relay]' "
            "(or run Brain Settings → Check for update)."
        ),
    }


def _ensure_realtime_client():
    """Singleton Realtime outbound pump (one thread for the process)."""
    global _REALTIME
    with _STATE_LOCK:
        if _REALTIME is not None:
            return _REALTIME
    from centurion_cli.remote_relay_realtime import RelayRealtimeClient

    # Wire Crypto Chat tunnel: inbound Realtime → localhost :9119 splice.
    client = RelayRealtimeClient(session=get_relay_session())
    with _STATE_LOCK:
        if _REALTIME is None:
            _REALTIME = client
        return _REALTIME


def start_if_enabled() -> dict[str, Any] | None:
    """On bridge daemon boot: resume Away pump when config already enabled."""
    cfg = _load_config()
    if not cfg.get("enabled"):
        return None
    return enable(
        supabase_url=str(cfg.get("supabase_url") or ""),
        supabase_anon_key=str(cfg.get("supabase_anon_key") or ""),
    )


def publish_relay_envelopes(events: list[dict[str, Any]]) -> None:
    """Publish opaque RelayTransport envelopes on the live Realtime socket."""
    client = _REALTIME
    if client is None:
        return
    client.publish_envelopes(events)


def enable(*, supabase_url: str = "", supabase_anon_key: str = "") -> dict[str, Any]:
    """Turn on Chat from anywhere (Brain dials out). Does not alter LAN :9119."""
    patch: dict[str, Any] = {"enabled": True}
    if supabase_url.strip():
        patch["supabase_url"] = supabase_url.strip()
    if supabase_anon_key.strip():
        patch["supabase_anon_key"] = supabase_anon_key.strip()
    install_id = ensure_install_id()
    patch["install_id"] = install_id
    _save_config_patch(patch)
    session = get_relay_session()
    epoch = session.reset_connection()
    ws_ok = _websockets_installed()
    missing_msg = (
        None
        if ws_ok
        else "websockets not installed — Away Crypto Chat needs "
        "pip install 'centurionai-os[remote-relay]' (or Brain update)."
    )
    with _STATE_LOCK:
        _PRESENCE.update(
            {
                "online": True,
                "conn_epoch": epoch,
                "last_error": missing_msg,
                "updated_at": time.time(),
            }
        )
    try:
        from centurion_cli.remote_relay_realtime import push_presence

        push_presence(online=True, conn_epoch=epoch)
        _ensure_realtime_client().start_background()
    except Exception as exc:
        logger.info("remote_relay outbound start deferred: %s", exc)
        with _STATE_LOCK:
            _PRESENCE["last_error"] = str(exc)[:240]
            _PRESENCE["updated_at"] = time.time()
    return status()


def disable() -> dict[str, Any]:
    global _REALTIME
    _save_config_patch({"enabled": False})
    with _STATE_LOCK:
        client = _REALTIME
        _REALTIME = None
        _PRESENCE.update(
            {
                "online": False,
                "conn_epoch": None,
                "last_error": None,
                "updated_at": time.time(),
            }
        )
    if client is not None:
        try:
            client.stop()
        except Exception:
            pass
    try:
        from centurion_cli.remote_relay_splice import reset_lan_splice

        reset_lan_splice()
    except Exception:
        pass
    try:
        from centurion_cli.remote_relay_realtime import push_presence

        push_presence(online=False)
    except Exception:
        pass
    return status()


def mark_reconnect_required(error: str | None = None) -> list[str]:
    """Realtime drop — full re-KX; return in-flight ids for retryable errors."""
    session = get_relay_session()
    inflight = session.fail_inflight_on_reconnect()
    epoch = session.reset_connection()
    with _STATE_LOCK:
        _PRESENCE.update(
            {
                "online": bool(_load_config().get("enabled")),
                "conn_epoch": epoch,
                "last_error": error,
                "updated_at": time.time(),
            }
        )
    return inflight


def hash_pair_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def mint_local_pair_token() -> dict[str, str]:
    """Dev/local pair token (Vercel mint is the production path)."""
    token = secrets.token_urlsafe(24)
    return {"token": token, "token_hash": hash_pair_token(token)}


def bridge_handle(action: str, request: dict[str, Any]) -> dict[str, Any] | None:
    """Dispatch remote_relay_* bridge actions. Returns None if not ours."""
    if action == "remote_relay_status":
        return {"ok": True, "action": action, **status()}
    if action == "remote_relay_enable":
        return {
            "ok": True,
            "action": action,
            **enable(
                supabase_url=str(request.get("supabase_url") or ""),
                supabase_anon_key=str(request.get("supabase_anon_key") or ""),
            ),
        }
    if action == "remote_relay_disable":
        return {"ok": True, "action": action, **disable()}
    if action == "remote_relay_reconnect":
        inflight = mark_reconnect_required(str(request.get("error") or "") or None)
        return {
            "ok": True,
            "action": action,
            "inflight_ids": inflight,
            **status(),
        }
    return None
