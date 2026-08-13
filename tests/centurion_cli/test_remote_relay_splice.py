"""Tests for Away Realtime → localhost :9119 Crypto Chat splice."""

from __future__ import annotations

import struct

from centurion_cli.relay_transport import RelaySession
from centurion_cli.remote_relay_splice import RelayLanSplice


def test_outbound_frame_echoes_msg_id():
    session = RelaySession()
    session.mark_kx_complete()
    events = session.outbound_frame(b"cipher", msg_id="req-1", expect_response=False)
    assert events[0]["id"] == "req-1"
    assert events[0]["kind"] == "frame"


def test_adopt_conn_invalidates_keys():
    session = RelaySession()
    session.mark_kx_complete()
    old = session.conn
    session.adopt_conn("abc123deadbeef")
    assert session.conn == "abc123deadbeef"
    assert session.conn != old
    assert session.session_keys_valid is False


def test_ingest_kx_client_adopts_peer_conn():
    session = RelaySession()
    peer_conn = "peerconn001"
    env = {
        "v": 1,
        "conn": peer_conn,
        "id": "kx1",
        "kind": "kx_client",
        "chunk_i": 0,
        "chunk_n": 1,
        "body_b64": __import__("base64").b64encode(b"\x01" + b"\x00" * 32).decode(),
    }
    kind, body = session.ingest_event(env)
    assert kind == "kx_client"
    assert body is not None
    assert session.conn == peer_conn


def test_splice_publishes_kx_server(monkeypatch):
    """LAN splice answers kx_client with kx_server and marks keys valid."""
    published: list[list[dict]] = []
    session = RelaySession()
    splice = RelayLanSplice(session=session, publish=lambda ev: published.append(ev))

    class FakeSock:
        def __init__(self):
            self._sent = bytearray()
            self._kx = b"\x01" + b"\x02" * 32
            self._ready = struct.pack(">I", 4) + b"dead"  # placeholder frame
            self._read_phase = 0

        def sendall(self, data: bytes) -> None:
            self._sent.extend(data)

        def recv(self, n: int) -> bytes:
            if self._read_phase == 0:
                self._read_phase = 1
                return self._kx
            # Frame reader may call recv — return empty to stop
            return b""

        def settimeout(self, *_a):
            return None

        def close(self) -> None:
            return None

    fake = FakeSock()

    def fake_create_connection(addr, timeout=None):
        return fake

    monkeypatch.setattr(
        "centurion_cli.remote_relay_splice.socket.create_connection",
        fake_create_connection,
    )
    # Avoid blocking reader — stop immediately after KX
    original_start = splice._start_reader

    def no_reader():
        splice._kx_done = True

    monkeypatch.setattr(splice, "_start_reader", no_reader)

    body = b"\x01" + b"\x03" * 32
    splice.handle_inbound("kx_client", body, "kx-id")
    assert session.session_keys_valid is True
    assert published
    assert published[0][0]["kind"] == "kx_server"
    assert fake._sent == body
