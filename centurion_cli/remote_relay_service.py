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

DEFAULT_CONTROL_BASE = "https://1human1ai.com"

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


def control_base() -> str:
    """Centurion Vercel origin for health / enable / presence."""
    cfg = _load_config()
    raw = str(cfg.get("control_base") or DEFAULT_CONTROL_BASE).strip().rstrip("/")
    return raw or DEFAULT_CONTROL_BASE


def _control_request(
    method: str,
    path: str,
    *,
    body: dict[str, Any] | None = None,
    timeout: float = 15.0,
) -> dict[str, Any]:
    """JSON GET/POST against the Chat-from-anywhere control plane (no service role)."""
    import json
    import urllib.error
    import urllib.request

    url = control_base() + (path if path.startswith("/") else f"/{path}")
    payload = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(
        url,
        data=payload,
        method=method.upper(),
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8")
            parsed = json.loads(raw) if raw.strip() else {}
            if not isinstance(parsed, dict):
                return {"ok": False, "error": "Unexpected control-plane response."}
            status_code = int(getattr(resp, "status", 200) or 200)
            if status_code >= 400:
                parsed.setdefault("ok", False)
                parsed.setdefault("error", parsed.get("message") or f"HTTP {status_code}")
                return parsed
            parsed.setdefault("ok", True)
            return parsed
    except urllib.error.HTTPError as exc:
        try:
            parsed = json.loads(exc.read().decode("utf-8"))
        except Exception:
            parsed = {}
        if isinstance(parsed, dict) and parsed:
            parsed.setdefault("ok", False)
            parsed.setdefault("error", parsed.get("message") or parsed.get("error") or f"HTTP {exc.code}")
            return parsed
        return {"ok": False, "error": f"Chat from anywhere control HTTP {exc.code}."}
    except Exception as exc:
        return {"ok": False, "error": str(exc)[:240]}


def _enroll_with_cloud(
    *,
    install_id: str,
    supabase_url: str = "",
    supabase_anon_key: str = "",
) -> dict[str, Any]:
    """Fetch public Realtime endpoints and register this Brain. Fail closed."""
    health = _control_request("GET", "/api/remote-relay/health")
    if not health.get("ok"):
        return {
            "ok": False,
            "error": str(health.get("error") or health.get("message") or "").strip()
            or "Could not reach Chat from anywhere (Centurion cloud).",
        }
    url = supabase_url.strip() or str(health.get("supabase_url") or "").strip()
    anon = supabase_anon_key.strip() or str(health.get("supabase_anon_key") or "").strip()
    if not url or not anon:
        return {
            "ok": False,
            "error": "Centurion cloud did not return Realtime endpoints.",
        }
    enrolled = _control_request(
        "POST",
        "/api/remote-relay/enable",
        body={"install_id": install_id},
    )
    if not enrolled.get("ok"):
        return {
            "ok": False,
            "error": str(enrolled.get("error") or enrolled.get("message") or "").strip()
            or "Could not enroll this Brain for Chat from anywhere.",
        }
    return {
        "ok": True,
        "supabase_url": url,
        "supabase_anon_key": anon,
    }


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
        "control_base": control_base(),
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
    url = str(cfg.get("supabase_url") or "")
    anon = str(cfg.get("supabase_anon_key") or "")
    return enable(
        supabase_url=url,
        supabase_anon_key=anon,
        enroll_cloud=not (url.strip() and anon.strip()),
    )


def publish_relay_envelopes(events: list[dict[str, Any]]) -> None:
    """Publish opaque RelayTransport envelopes on the live Realtime socket."""
    client = _REALTIME
    if client is None:
        return
    client.publish_envelopes(events)


def enable(
    *,
    supabase_url: str = "",
    supabase_anon_key: str = "",
    enroll_cloud: bool = True,
) -> dict[str, Any]:
    """Turn on Chat from anywhere (Brain dials out). Does not alter LAN :9119.

    Fail closed when Centurion cloud health/enable cannot run — the GTK/iPhone
    toggle must show the error instead of a silent “On — waiting”.
    """
    install_id = ensure_install_id()
    url = str(supabase_url or "").strip()
    anon = str(supabase_anon_key or "").strip()
    if enroll_cloud:
        enrolled = _enroll_with_cloud(
            install_id=install_id,
            supabase_url=url,
            supabase_anon_key=anon,
        )
        if not enrolled.get("ok"):
            err = str(enrolled.get("error") or "Could not enable Chat from anywhere.")
            with _STATE_LOCK:
                _PRESENCE.update(
                    {
                        "online": False,
                        "last_error": err[:240],
                        "updated_at": time.time(),
                    }
                )
            out = status()
            out["ok"] = False
            out["error"] = err
            out["message"] = err
            out["enabled"] = False
            return out
        url = str(enrolled.get("supabase_url") or url).strip()
        anon = str(enrolled.get("supabase_anon_key") or anon).strip()
    if not url or not anon:
        err = "Chat from anywhere needs Centurion cloud endpoints."
        out = status()
        out["ok"] = False
        out["error"] = err
        out["message"] = err
        return out

    patch: dict[str, Any] = {
        "enabled": True,
        "install_id": install_id,
        "supabase_url": url,
        "supabase_anon_key": anon,
        "control_base": control_base(),
    }
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
    out = status()
    out["ok"] = True
    return out


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
        result = enable(
            supabase_url=str(request.get("supabase_url") or ""),
            supabase_anon_key=str(request.get("supabase_anon_key") or ""),
        )
        result.setdefault("action", action)
        result.setdefault("ok", bool(result.get("ok")))
        return result
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
