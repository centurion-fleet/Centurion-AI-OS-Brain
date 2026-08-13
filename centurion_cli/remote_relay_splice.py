"""Splice RelayTransport opaque bodies to local LAN Crypto Chat (:9119).

Away Realtime carries the same KX bytes and secretbox payloads as TCP, without
the 4-byte length prefix. This module opens ``127.0.0.1:9119`` so pairing,
approvals, and ``handle_request`` stay in ``centurion-remote`` (Rust).

Reconnect (new Realtime ``conn``) ⇒ drop the TCP socket ⇒ full re-KX.
"""

from __future__ import annotations

import logging
import select
import socket
import struct
import threading
import time
from typing import Any, Callable

from centurion_cli.relay_transport import RelaySession

logger = logging.getLogger(__name__)

DEFAULT_LAN_HOST = "127.0.0.1"
DEFAULT_LAN_PORT = 9119
MAX_FRAME_BYTES = 8 * 1024 * 1024
KX_BYTES = 33


class RelayLanSplice:
    """One TCP session to local centurion-remote per Realtime connection epoch."""

    def __init__(
        self,
        *,
        session: RelaySession,
        publish: Callable[[list[dict[str, Any]]], None],
        host: str = DEFAULT_LAN_HOST,
        port: int = DEFAULT_LAN_PORT,
    ) -> None:
        self.session = session
        self.publish = publish
        self.host = host
        self.port = port
        self._sock: socket.socket | None = None
        self._lock = threading.RLock()
        self._reader: threading.Thread | None = None
        self._stop = threading.Event()
        self._kx_done = False
        self._pending_response_id: str | None = None
        self._buf = bytearray()

    def reset(self) -> None:
        """Drop LAN splice after Realtime reconnect (mandatory re-KX)."""
        with self._lock:
            self._stop.set()
            sock = self._sock
            self._sock = None
            self._kx_done = False
            self._pending_response_id = None
            self._buf.clear()
        if sock is not None:
            try:
                sock.close()
            except OSError:
                pass
        self._stop = threading.Event()

    def handle_inbound(self, kind: str, body: bytes, envelope_id: str) -> None:
        """Process a fully reassembled Realtime body."""
        if kind == "kx_client":
            self._handle_kx_client(body)
            return
        if kind in ("frame", "frame_chunk"):
            self._handle_frame(body, envelope_id)
            return
        if kind == "kx_server":
            # Brain never receives kx_server (phone is client).
            return

    def _ensure_socket(self, *, start_reader: bool = True) -> socket.socket:
        with self._lock:
            if self._sock is not None:
                return self._sock
            sock = socket.create_connection((self.host, self.port), timeout=10.0)
            sock.settimeout(None)
            self._sock = sock
            self._stop.clear()
            if start_reader:
                self._reader = threading.Thread(
                    target=self._read_loop,
                    name="centurion-relay-lan-splice",
                    daemon=True,
                )
                self._reader.start()
            return sock

    def _start_reader(self) -> None:
        with self._lock:
            if self._reader and self._reader.is_alive():
                return
            self._stop.clear()
            self._reader = threading.Thread(
                target=self._read_loop,
                name="centurion-relay-lan-splice",
                daemon=True,
            )
            self._reader.start()

    def _handle_kx_client(self, body: bytes) -> None:
        if len(body) != KX_BYTES:
            logger.warning("remote_relay kx_client length %d (expected %d)", len(body), KX_BYTES)
            return
        with self._lock:
            # Fresh KX for this epoch — drop any prior TCP session.
            if self._sock is not None:
                try:
                    self._sock.close()
                except OSError:
                    pass
                self._sock = None
                self._kx_done = False
                self._buf.clear()
            self._stop.set()
            self._stop = threading.Event()
            self._reader = None
        try:
            # Do not start the frame reader until after the raw KX exchange —
            # otherwise the reader steals the 33-byte server pubkey.
            sock = self._ensure_socket(start_reader=False)
            sock.sendall(body)
            server_kx = self._recv_exact(sock, KX_BYTES)
        except OSError as exc:
            logger.warning("remote_relay LAN splice KX failed: %s", exc)
            self.reset()
            return
        self.session.mark_kx_complete()
        events = self.session.outbound_kx(server_kx, client=False)
        self.publish(events)
        with self._lock:
            self._kx_done = True
        self._start_reader()
        # Ready / PairRequired follows on the length-prefixed stream.

    def _handle_frame(self, body: bytes, envelope_id: str) -> None:
        if not self.session.session_keys_valid:
            logger.warning("remote_relay frame before KX complete — dropping")
            return
        try:
            sock = self._ensure_socket()
            header = struct.pack(">I", len(body))
            with self._lock:
                self._pending_response_id = envelope_id
            sock.sendall(header + body)
        except OSError as exc:
            logger.warning("remote_relay LAN splice write failed: %s", exc)
            self.reset()
            self.session.session_keys_valid = False

    def _recv_exact(self, sock: socket.socket, n: int) -> bytes:
        buf = bytearray()
        while len(buf) < n:
            chunk = sock.recv(n - len(buf))
            if not chunk:
                raise OSError("LAN Crypto Chat closed during read")
            buf.extend(chunk)
        return bytes(buf)

    def _read_loop(self) -> None:
        """Read length-prefixed secretbox frames from LAN and publish on Realtime."""
        while not self._stop.is_set():
            sock = self._sock
            if sock is None:
                break
            try:
                ready, _, _ = select.select([sock], [], [], 0.5)
                if not ready:
                    continue
                chunk = sock.recv(65536)
                if not chunk:
                    logger.info("remote_relay LAN splice closed by peer")
                    self.reset()
                    self.session.session_keys_valid = False
                    break
                self._buf.extend(chunk)
                self._drain_frames()
            except OSError as exc:
                if not self._stop.is_set():
                    logger.warning("remote_relay LAN splice read error: %s", exc)
                self.reset()
                self.session.session_keys_valid = False
                break

    def _drain_frames(self) -> None:
        while True:
            if len(self._buf) < 4:
                return
            length = struct.unpack(">I", self._buf[:4])[0]
            if length > MAX_FRAME_BYTES:
                logger.warning("remote_relay LAN frame too large (%d)", length)
                self.reset()
                return
            if len(self._buf) < 4 + length:
                return
            payload = bytes(self._buf[4 : 4 + length])
            del self._buf[: 4 + length]
            with self._lock:
                msg_id = self._pending_response_id
                # Keep pending id until a non-push response; approvals may interleave.
            try:
                events = self.session.outbound_frame(payload, expect_response=False)
                self.publish(events)
            except Exception as exc:
                logger.warning("remote_relay publish LAN frame failed: %s", exc)


_SPLICE: RelayLanSplice | None = None
_SPLICE_LOCK = threading.Lock()


def get_lan_splice(
    *,
    session: RelaySession | None = None,
    publish: Callable[[list[dict[str, Any]]], None] | None = None,
) -> RelayLanSplice:
    """Process-wide splice singleton (reset on Realtime reconnect)."""
    global _SPLICE
    from centurion_cli.remote_relay_service import get_relay_session, publish_relay_envelopes

    with _SPLICE_LOCK:
        if _SPLICE is None:
            _SPLICE = RelayLanSplice(
                session=session or get_relay_session(),
                publish=publish or publish_relay_envelopes,
            )
        return _SPLICE


def reset_lan_splice() -> None:
    global _SPLICE
    with _SPLICE_LOCK:
        if _SPLICE is not None:
            _SPLICE.reset()


def on_relay_inbound(kind: str, body: bytes, envelope_id: str = "") -> None:
    """Entry point from ``RelayRealtimeClient.handle_inbound_event``."""
    splice = get_lan_splice()
    splice.handle_inbound(kind, body, envelope_id)
