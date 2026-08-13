"""Tests for Brain remote_relay control plane (no network)."""

from __future__ import annotations

from centurion_cli import remote_relay_service as rrs
from centurion_cli.relay_transport import RelaySession
from centurion_cli.remote_bridge import handle_request


def test_relay_session_reconnect_invalidates_keys():
    session = RelaySession()
    session.mark_kx_complete()
    events = session.outbound_kx(b"\x01" + b"\x00" * 32, client=True)
    assert events[0]["kind"] == "kx_client"
    session.mark_kx_complete()
    frame_events = session.outbound_frame(b"cipher")
    assert frame_events[0]["kind"] == "frame"
    inflight = session.fail_inflight_on_reconnect()
    assert frame_events[0]["id"] in inflight
    session.reset_connection()
    assert session.session_keys_valid is False


def test_bridge_remote_relay_status(tmp_path, monkeypatch):
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path))
    # Reset module presence between tests
    with rrs._STATE_LOCK:
        rrs._PRESENCE.update(
            {"online": False, "conn_epoch": None, "last_error": None, "updated_at": None}
        )
        rrs._SESSION = None
        rrs._REALTIME = None

    resp = handle_request({"id": "1", "action": "remote_relay_status"})
    assert resp["ok"] is True
    assert resp["enabled"] is False
    assert "websockets_installed" in resp
    assert "realtime_pipe_ready" in resp
    assert resp["lan_crypto_chat"]["unchanged"] is True
    assert resp["lan_crypto_chat"]["preferred_when_reachable"] is True


def test_bridge_remote_relay_enable_disable(tmp_path, monkeypatch):
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path / ".centurion"))
    (tmp_path / ".centurion").mkdir(parents=True, exist_ok=True)
    with rrs._STATE_LOCK:
        rrs._SESSION = None
        rrs._REALTIME = None

    enabled = handle_request({"id": "2", "action": "remote_relay_enable"})
    assert enabled["ok"] is True
    assert enabled["enabled"] is True
    assert enabled["install_id"]
    assert enabled["presence"]["online"] is True
    assert enabled["channel"].startswith("brain:")

    disabled = handle_request({"id": "3", "action": "remote_relay_disable"})
    assert disabled["ok"] is True
    assert disabled["enabled"] is False
    assert disabled["presence"]["online"] is False


def test_hash_pair_token_stable():
    assert rrs.hash_pair_token("abc") == rrs.hash_pair_token("abc")
    assert rrs.hash_pair_token("abc") != rrs.hash_pair_token("abd")
