"""Tests for Brain remote_relay control plane (no network)."""

from __future__ import annotations

from centurion_cli import remote_relay_service as rrs
from centurion_cli.relay_transport import RelaySession
from centurion_cli.remote_bridge import handle_request


class _DummyRealtime:
    def start_background(self) -> bool:
        return True

    def stop(self) -> None:
        return None


def _reset_relay_state() -> None:
    with rrs._STATE_LOCK:
        rrs._PRESENCE.update(
            {"online": False, "conn_epoch": None, "last_error": None, "updated_at": None}
        )
        rrs._SESSION = None
        rrs._REALTIME = None


def _mock_control_plane(monkeypatch, *, health_ok=True, enable_ok=True, presence_ok=True):
    """Stub Vercel health/enable/presence so tests never hit 1human1ai.com."""
    calls: list[tuple[str, str, dict | None]] = []

    def fake(method, path, *, body=None, timeout=15.0):
        calls.append((method, path, body))
        if path.endswith("/health"):
            if not health_ok:
                return {"ok": False, "error": "cloud down"}
            return {
                "ok": True,
                "supabase_url": "https://example.supabase.co",
                "supabase_anon_key": "anon-test-key",
            }
        if path.endswith("/enable"):
            if not enable_ok:
                return {"ok": False, "error": "enable denied"}
            return {"ok": True, "channel": "brain:test"}
        if path.endswith("/presence"):
            if not presence_ok:
                return {"ok": False, "error": "presence fail"}
            return {"ok": True}
        return {"ok": False, "error": f"unexpected path {path}"}

    monkeypatch.setattr(rrs, "_control_request", fake)
    monkeypatch.setattr(rrs, "_ensure_realtime_client", lambda: _DummyRealtime())
    return calls


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
    _reset_relay_state()

    resp = handle_request({"id": "1", "action": "remote_relay_status"})
    assert resp["ok"] is True
    assert resp["enabled"] is False
    assert "websockets_installed" in resp
    assert "realtime_pipe_ready" in resp
    assert resp["control_base"] == rrs.DEFAULT_CONTROL_BASE
    assert resp["lan_crypto_chat"]["unchanged"] is True
    assert resp["lan_crypto_chat"]["preferred_when_reachable"] is True


def test_enable_fails_closed_without_cloud(tmp_path, monkeypatch):
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path / ".centurion"))
    (tmp_path / ".centurion").mkdir(parents=True, exist_ok=True)
    _reset_relay_state()
    _mock_control_plane(monkeypatch, health_ok=False)

    enabled = handle_request({"id": "2", "action": "remote_relay_enable"})
    assert enabled["ok"] is False
    assert enabled["enabled"] is False
    assert "cloud down" in str(enabled.get("error") or enabled.get("message") or "")
    assert enabled.get("supabase_url_configured") is False


def test_bridge_remote_relay_enable_disable(tmp_path, monkeypatch):
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path / ".centurion"))
    (tmp_path / ".centurion").mkdir(parents=True, exist_ok=True)
    _reset_relay_state()
    calls = _mock_control_plane(monkeypatch)

    enabled = handle_request({"id": "2", "action": "remote_relay_enable"})
    assert enabled["ok"] is True
    assert enabled["enabled"] is True
    assert enabled["install_id"]
    assert enabled["supabase_url"] == "https://example.supabase.co"
    assert enabled["supabase_anon_key"] == "anon-test-key"
    assert enabled["supabase_url_configured"] is True
    assert enabled["presence"]["online"] is True
    assert enabled["channel"].startswith("brain:")
    assert any(path.endswith("/health") for _, path, _ in calls)
    assert any(path.endswith("/enable") for _, path, _ in calls)

    disabled = handle_request({"id": "3", "action": "remote_relay_disable"})
    assert disabled["ok"] is True
    assert disabled["enabled"] is False
    assert disabled["presence"]["online"] is False


def test_hash_pair_token_stable():
    assert rrs.hash_pair_token("abc") == rrs.hash_pair_token("abc")
    assert rrs.hash_pair_token("abc") != rrs.hash_pair_token("abd")
