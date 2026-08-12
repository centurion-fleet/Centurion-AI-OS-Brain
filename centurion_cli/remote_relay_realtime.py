"""Brain outbound adapter for Supabase Realtime / presence.

Uses the Phoenix Realtime v1 websocket when ``websockets`` is installed and
``remote_relay.supabase_url`` + anon/service key are set. Presence is also
pushed over REST so phones can see Brain online without a chat yet.

Reconnect ⇒ new ``conn`` epoch + mandatory re-KX (session keys never reused).

LAN TCP Crypto Chat (:9119) is never used by this module.
"""

from __future__ import annotations

import asyncio
import json
import logging
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Callable

from centurion_cli.remote_relay_service import (
    channel_name,
    ensure_install_id,
    get_relay_session,
    status,
)
from centurion_cli.relay_transport import RelayEnvelope, RelaySession

logger = logging.getLogger(__name__)


def _cfg() -> dict[str, Any]:
    try:
        from centurion_cli.config import load_config

        section = (load_config() or {}).get("remote_relay")
        return section if isinstance(section, dict) else {}
    except Exception:
        return {}


def realtime_websocket_url(supabase_url: str, api_key: str) -> str:
    """Build Supabase Realtime Phoenix websocket URL."""
    base = supabase_url.rstrip("/")
    if base.startswith("https://"):
        ws = "wss://" + base[len("https://") :]
    elif base.startswith("http://"):
        ws = "ws://" + base[len("http://") :]
    else:
        ws = base
    qs = urllib.parse.urlencode({"apikey": api_key, "vsn": "1.0.0"})
    return f"{ws}/realtime/v1/websocket?{qs}"


def relay_topic(install_id: str | None = None) -> str:
    """Phoenix topic for private Brain↔phone broadcast."""
    return f"realtime:{channel_name(install_id)}"


def push_presence(*, online: bool, conn_epoch: str | None = None) -> bool:
    """POST/PATCH presence via Supabase REST."""
    cfg = _cfg()
    if not cfg.get("enabled"):
        return False
    base = str(cfg.get("supabase_url") or "").rstrip("/")
    key = str(cfg.get("supabase_anon_key") or cfg.get("supabase_service_key") or "").strip()
    if not base or not key:
        logger.info("remote_relay presence skipped — supabase_url/key not configured")
        return False
    install_id = ensure_install_id()
    try:
        brain_id = _lookup_brain_id(base, key, install_id)
        if not brain_id:
            return False
        epoch = conn_epoch or get_relay_session().conn
        body = json.dumps(
            {
                "brain_id": brain_id,
                "online": online,
                "conn_epoch": epoch,
            }
        ).encode("utf-8")
        req = urllib.request.Request(
            f"{base}/rest/v1/remote_brain_presence?on_conflict=brain_id",
            data=body,
            method="POST",
            headers={
                "apikey": key,
                "Authorization": f"Bearer {key}",
                "Content-Type": "application/json",
                "Prefer": "resolution=merge-duplicates",
            },
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            return 200 <= getattr(resp, "status", 200) < 300
    except Exception as exc:
        logger.warning("remote_relay presence push failed: %s", exc)
        return False


def _lookup_brain_id(base: str, key: str, install_id: str) -> str | None:
    url = (
        f"{base}/rest/v1/remote_brain_installs"
        f"?install_id=eq.{urllib.request.quote(install_id)}&select=id"
    )
    req = urllib.request.Request(
        url,
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            rows = json.loads(resp.read().decode("utf-8"))
            if isinstance(rows, list) and rows:
                return str(rows[0].get("id") or "") or None
    except urllib.error.HTTPError as exc:
        logger.warning("remote_relay install lookup failed: %s", exc)
    except Exception as exc:
        logger.warning("remote_relay install lookup error: %s", exc)
    return None


class RelayRealtimeClient:
    """Phoenix Realtime envelope pump (optional dependency: websockets).

    Does not decrypt — payloads are opaque. Reconnect ⇒ ``session.reset_connection()``
    and mandatory re-KX before frames.
    """

    def __init__(
        self,
        *,
        on_plaintext_frame: Callable[[bytes], None] | None = None,
        session: RelaySession | None = None,
    ) -> None:
        self.on_plaintext_frame = on_plaintext_frame
        self.session = session or get_relay_session()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._send_queue: asyncio.Queue[list[dict[str, Any]]] | None = None
        self._ref = 0
        self._joined = False

    def start_background(self) -> bool:
        cfg = _cfg()
        if not cfg.get("enabled"):
            return False
        if self._thread and self._thread.is_alive():
            return True
        self._stop.clear()
        self._thread = threading.Thread(
            target=self._run,
            name="centurion-remote-relay",
            daemon=True,
        )
        self._thread.start()
        return True

    def stop(self) -> None:
        self._stop.set()
        if self._loop and self._send_queue is not None:
            try:
                self._loop.call_soon_threadsafe(self._send_queue.put_nowait, [])
            except Exception:
                pass

    def publish_envelopes(self, events: list[dict[str, Any]]) -> None:
        """Queue Realtime broadcast envelopes (no-op if socket not up)."""
        if not events:
            return
        loop = self._loop
        queue = self._send_queue
        if loop is None or queue is None:
            logger.debug("remote_relay publish deferred — socket not ready (%d events)", len(events))
            return
        try:
            loop.call_soon_threadsafe(queue.put_nowait, events)
        except Exception as exc:
            logger.warning("remote_relay publish failed: %s", exc)

    def _next_ref(self) -> str:
        self._ref += 1
        return str(self._ref)

    def _run(self) -> None:
        push_presence(online=True, conn_epoch=self.session.conn)
        try:
            import websockets  # type: ignore  # noqa: F401
        except ImportError:
            logger.info(
                "remote_relay: websockets not installed — presence-only outbound"
            )
            while not self._stop.wait(30.0):
                push_presence(online=True, conn_epoch=self.session.conn)
            push_presence(online=False, conn_epoch=self.session.conn)
            return

        while not self._stop.is_set():
            try:
                asyncio.run(self._session_loop())
            except Exception as exc:
                logger.warning("remote_relay realtime session error: %s", exc)
            # Reconnect = new conn epoch + re-KX
            inflight = self.session.fail_inflight_on_reconnect()
            epoch = self.session.reset_connection()
            if inflight:
                logger.info(
                    "remote_relay reconnect: %d in-flight id(s) need retry",
                    len(inflight),
                )
            push_presence(online=True, conn_epoch=epoch)
            if self._stop.wait(2.0):
                break
        push_presence(online=False, conn_epoch=self.session.conn)

    async def _session_loop(self) -> None:
        import websockets

        cfg = _cfg()
        base = str(cfg.get("supabase_url") or "").rstrip("/")
        key = str(cfg.get("supabase_anon_key") or cfg.get("supabase_service_key") or "").strip()
        if not base or not key:
            # Presence-only until cloud credentials are configured.
            while not self._stop.wait(30.0):
                push_presence(online=True, conn_epoch=self.session.conn)
            return

        url = realtime_websocket_url(base, key)
        topic = relay_topic()
        logger.info(
            "remote_relay connecting to Realtime channel %s (install=%s)",
            topic,
            ensure_install_id(),
        )
        self._loop = asyncio.get_running_loop()
        self._send_queue = asyncio.Queue()
        self._joined = False

        async with websockets.connect(url, ping_interval=20, ping_timeout=20) as ws:
            join = {
                "topic": topic,
                "event": "phx_join",
                "payload": {
                    "config": {
                        "broadcast": {"ack": False, "self": False},
                        "presence": {"key": ensure_install_id()},
                    }
                },
                "ref": self._next_ref(),
            }
            await ws.send(json.dumps(join))

            last_presence = time.time()
            while not self._stop.is_set():
                # Drain outbound queue without blocking forever
                try:
                    while True:
                        events = self._send_queue.get_nowait()
                        if not events:
                            continue
                        for env in events:
                            msg = {
                                "topic": topic,
                                "event": "broadcast",
                                "payload": {
                                    "type": "broadcast",
                                    "event": "centurion_frame",
                                    "payload": env,
                                },
                                "ref": self._next_ref(),
                            }
                            await ws.send(json.dumps(msg))
                except asyncio.QueueEmpty:
                    pass

                try:
                    raw = await asyncio.wait_for(ws.recv(), timeout=1.0)
                except asyncio.TimeoutError:
                    if time.time() - last_presence > 25:
                        push_presence(online=True, conn_epoch=self.session.conn)
                        last_presence = time.time()
                    continue

                try:
                    msg = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                event = str(msg.get("event") or "")
                if event == "phx_reply":
                    status_txt = (
                        (msg.get("payload") or {}).get("status")
                        if isinstance(msg.get("payload"), dict)
                        else None
                    )
                    if status_txt == "ok":
                        self._joined = True
                    continue
                if event in ("broadcast", "phx_broadcast"):
                    payload = msg.get("payload") or {}
                    if isinstance(payload, dict):
                        # Supabase: { event: "centurion_frame", payload: <envelope> }
                        inner = payload.get("payload") if payload.get("event") == "centurion_frame" else payload
                        if isinstance(inner, dict) and "body_b64" in inner:
                            self.handle_inbound_event(inner)
                elif event == "phx_error":
                    raise RuntimeError(f"realtime phx_error: {msg}")

    def handle_inbound_event(self, raw: dict[str, Any]) -> bytes | None:
        kind, body = self.session.ingest_event(raw)
        if body is None:
            return None
        if kind in ("kx_client", "kx_server"):
            return body
        if self.on_plaintext_frame and self.session.session_keys_valid:
            self.on_plaintext_frame(body)
        return body

    def snapshot(self) -> dict[str, Any]:
        return {
            **status(),
            "session_keys_valid": self.session.session_keys_valid,
            "conn": self.session.conn,
            "joined": self._joined,
        }


def encode_outbound_chat_frame(ciphertext: bytes) -> list[dict[str, Any]]:
    """Helper: wrap secretbox bytes as RelayTransport Realtime events."""
    session = get_relay_session()
    session.ensure_ready_for_frames()
    return session.outbound_frame(ciphertext)
