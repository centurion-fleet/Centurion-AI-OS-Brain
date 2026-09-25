"""Tests for the fleet send path and inbox actions.

The behaviour under test is honesty about delivery. The receiving endpoint used
to answer {"status": "received"} for a message it had discarded, and the sender
treated HTTP 200 as arrival — so two owners could believe work was moving
between their Centurions when nothing had been delivered.
"""

from __future__ import annotations

import json

import pytest

from centurion.fleet.peers import FleetPeer, FleetPeers
from centurion_cli.remote_bridge import (
    _handle_fleet_inbox,
    _handle_fleet_mark_read,
    _handle_fleet_send,
)


@pytest.fixture(autouse=True)
def isolated_home(tmp_path, monkeypatch):
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path))
    monkeypatch.setenv("CENTURION_FLEET_TOKEN", "test-token")
    return tmp_path


def _register(name="Eve", peer_id="eve-1", address="http://127.0.0.1:9"):
    FleetPeers().register(
        FleetPeer(centurion_id=peer_id, name=name, address=address, auth_token="test-token")
    )


class _Resp:
    def __init__(self, body: bytes, status=200):
        self._body = body
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def read(self) -> bytes:
        return self._body


# --- input validation ------------------------------------------------------

def test_no_peer_named():
    out = _handle_fleet_send({"body": "hello"}, "r1")
    assert out["ok"] is False and out["code"] == "NO_PEER"


def test_empty_body_refused():
    _register()
    out = _handle_fleet_send({"peer_id": "Eve", "body": "   "}, "r1")
    assert out["ok"] is False and out["code"] == "EMPTY"


def test_unknown_peer_is_named_back():
    out = _handle_fleet_send({"peer_id": "Mikki", "body": "hello"}, "r1")
    assert out["ok"] is False and out["code"] == "UNKNOWN_PEER"
    assert "Mikki" in out["message"]


# --- honesty about delivery ------------------------------------------------

def test_receiver_saying_received_is_not_delivery(monkeypatch):
    """The old endpoint's answer must never be read as success."""
    _register()
    monkeypatch.setattr(
        "urllib.request.urlopen",
        lambda *a, **k: _Resp(b'{"status": "received", "message_id": "m1"}'),
    )
    out = _handle_fleet_send({"peer_id": "Eve", "body": "hello"}, "r1")
    assert out["ok"] is True
    assert out["delivered"] is False
    assert out["queued"] is True
    assert "queued" in out["message"].lower()


def test_stored_is_delivery(monkeypatch):
    _register()
    monkeypatch.setattr(
        "urllib.request.urlopen",
        lambda *a, **k: _Resp(b'{"status": "stored", "message_id": "m1"}'),
    )
    out = _handle_fleet_send({"peer_id": "Eve", "body": "hello"}, "r1")
    assert out["delivered"] is True and out["queued"] is False
    assert "Sent to Eve" in out["message"]


def test_non_json_receipt_is_not_delivery(monkeypatch):
    _register()
    monkeypatch.setattr("urllib.request.urlopen", lambda *a, **k: _Resp(b"<html>oops</html>"))
    out = _handle_fleet_send({"peer_id": "Eve", "body": "hello"}, "r1")
    assert out["delivered"] is False


def test_unreachable_peer_is_queued_not_claimed(monkeypatch):
    _register(address="http://127.0.0.1:9")  # nothing listening on port 9

    def _boom(*a, **k):
        raise OSError("connection refused")

    monkeypatch.setattr("urllib.request.urlopen", _boom)
    out = _handle_fleet_send({"peer_id": "Eve", "body": "hello"}, "r1")
    assert out["ok"] is True
    assert out["delivered"] is False and out["queued"] is True


def test_peer_can_be_addressed_by_name(monkeypatch):
    _register(name="Eve")
    monkeypatch.setattr(
        "urllib.request.urlopen",
        lambda *a, **k: _Resp(b'{"status": "stored"}'),
    )
    out = _handle_fleet_send({"peer_id": "eve", "body": "hello"}, "r1")
    assert out["delivered"] is True


# --- the inbox actions -----------------------------------------------------

def test_inbox_lists_what_arrived():
    from centurion.fleet.inbox import store_message

    store_message(
        {
            "message_id": "msg-9",
            "sender_id": "eve-1",
            "sender_name": "Eve",
            "subject": "[TASK] Pricing",
            "body": "Please check tab 2.",
            "priority": "normal",
            "timestamp": 1.0,
        }
    )
    out = _handle_fleet_inbox({}, "r1")
    assert out["ok"] is True
    assert out["count"] == 1
    assert out["unread"] == 1
    assert out["messages"][0]["sender_name"] == "Eve"


def test_mark_read_clears_unread():
    from centurion.fleet.inbox import store_message

    store_message(
        {
            "message_id": "msg-9",
            "sender_id": "eve-1",
            "sender_name": "Eve",
            "subject": "hi",
            "body": "x",
            "priority": "normal",
            "timestamp": 1.0,
        }
    )
    out = _handle_fleet_mark_read({"message_id": "msg-9"}, "r1")
    assert out["ok"] is True and out["unread"] == 0


def test_mark_read_requires_an_id():
    out = _handle_fleet_mark_read({}, "r1")
    assert out["ok"] is False and out["code"] == "NO_MESSAGE_ID"
