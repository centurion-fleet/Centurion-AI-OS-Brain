"""Tests for remote_relay_realtime helpers (no live network)."""

from __future__ import annotations

from centurion_cli.remote_relay_realtime import (
    RelayRealtimeClient,
    encode_outbound_chat_frame,
    realtime_websocket_url,
    relay_topic,
)
from centurion_cli.relay_transport import RelaySession


def test_realtime_websocket_url_https():
    url = realtime_websocket_url("https://abc.supabase.co", "anon-key")
    assert url.startswith("wss://abc.supabase.co/realtime/v1/websocket?")
    assert "apikey=anon-key" in url
    assert "vsn=1.0.0" in url


def test_realtime_websocket_url_http():
    url = realtime_websocket_url("http://localhost:54321", "k")
    assert url.startswith("ws://localhost:54321/realtime/v1/websocket?")


def test_relay_topic(monkeypatch):
    import centurion_cli.remote_relay_service as svc

    monkeypatch.setattr(
        svc, "_load_config", lambda: {"install_id": "brain_abc", "channel_prefix": "brain"}
    )
    assert relay_topic("brain_abc") == "realtime:brain:brain_abc"


def test_handle_inbound_reassembles(monkeypatch):
    session = RelaySession()
    client = RelayRealtimeClient(session=session)
    # Build chunked envelopes against this session's conn without requiring KX
    # (ingest path only checks conn + reassembly).
    from centurion_cli.relay_transport import build_envelopes, new_message_id

    events = build_envelopes(
        conn=session.conn,
        msg_id=new_message_id(),
        kind="frame",
        body=b"secret-bytes",
        chunk_bytes=4,
    )
    assert len(events) > 1
    for ev in events[:-1]:
        assert client.handle_inbound_event(ev) is None
    assert client.handle_inbound_event(events[-1]) == b"secret-bytes"


def test_handle_inbound_single_chunk():
    session = RelaySession()
    client = RelayRealtimeClient(session=session)
    from centurion_cli.relay_transport import build_envelopes, new_message_id

    events = build_envelopes(
        conn=session.conn,
        msg_id=new_message_id(),
        kind="frame",
        body=b"ok",
        chunk_bytes=1_000_000,
    )
    assert client.handle_inbound_event(events[0]) == b"ok"


def test_push_presence_uses_control_plane(tmp_path, monkeypatch):
    import centurion_cli.remote_relay_realtime as rrt
    import centurion_cli.remote_relay_service as svc

    monkeypatch.setenv("CENTURION_HOME", str(tmp_path / ".centurion"))
    (tmp_path / ".centurion").mkdir(parents=True, exist_ok=True)
    monkeypatch.setattr(
        rrt,
        "_cfg",
        lambda: {
            "enabled": True,
            "install_id": "brain_test",
            "control_base": "https://1human1ai.com",
        },
    )
    calls: list[tuple] = []

    def fake(method, path, *, body=None, timeout=15.0):
        calls.append((method, path, body))
        return {"ok": True}

    monkeypatch.setattr(svc, "_control_request", fake)
    assert rrt.push_presence(online=True, conn_epoch="epoch-1") is True
    assert calls
    method, path, body = calls[0]
    assert method == "POST"
    assert path == "/api/remote-relay/presence"
    assert body["install_id"] == "brain_test"
    assert body["online"] is True
    assert body["conn_epoch"] == "epoch-1"


def test_encode_outbound_requires_kx():
    session = RelaySession()
    # Force module session
    import centurion_cli.remote_relay_service as svc

    with svc._STATE_LOCK:
        svc._SESSION = session
    try:
        encode_outbound_chat_frame(b"x")
        assert False, "expected RuntimeError"
    except RuntimeError:
        pass
    session.mark_kx_complete()
    events = encode_outbound_chat_frame(b"x")
    assert events and events[0]["kind"] == "frame"
