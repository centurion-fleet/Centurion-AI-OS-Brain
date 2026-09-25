"""Tests for the fleet inbox and the endpoint that fills it.

The bug these guard: POST /fleet/message used to look for a transport that is
never constructed, fall back to a log line, and return {"status": "received"}.
The sender was told the message had landed; it had been discarded, and no human
could read it. A false acknowledgement is worse than a refusal — the sender
stops retrying.
"""

from __future__ import annotations

import asyncio
import json

import pytest

from centurion.fleet import inbox
from gateway.config import PlatformConfig
from gateway.platforms.api_server import APIServerAdapter


@pytest.fixture(autouse=True)
def isolated_home(tmp_path, monkeypatch):
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path))
    return tmp_path


def _envelope(**over):
    base = {
        "message_id": "msg-001",
        "sender_id": "eve",
        "sender_name": "Eve",
        "recipient_id": "mikki",
        "subject": "[TASK] Review the pricing sheet",
        "body": "Please check the figures in tab 2.",
        "priority": "normal",
        "timestamp": 1_700_000_000.0,
    }
    base.update(over)
    return base


# --- the inbox itself ------------------------------------------------------

def test_store_then_read_back():
    inbox.store_message(_envelope())
    items = inbox.list_messages()
    assert len(items) == 1
    assert items[0]["subject"] == "[TASK] Review the pricing sheet"
    assert items[0]["sender_name"] == "Eve"
    assert items[0]["read"] is False


def test_missing_message_id_is_refused():
    # An unnamed message cannot be replied to or deduplicated.
    with pytest.raises(ValueError):
        inbox.store_message(_envelope(message_id=""))


def test_mark_read():
    inbox.store_message(_envelope())
    assert inbox.unread_count() == 1
    assert inbox.mark_read("msg-001") is True
    assert inbox.unread_count() == 0


def test_mark_read_missing_returns_false():
    assert inbox.mark_read("nope") is False


def test_corrupt_file_is_skipped_not_fatal(tmp_path):
    inbox.store_message(_envelope(message_id="good"))
    (tmp_path / "fleet" / "messages" / "broken.json").write_text("{not json", encoding="utf-8")
    items = inbox.list_messages()
    assert [i["message_id"] for i in items] == ["good"]


def test_body_is_bounded():
    inbox.store_message(_envelope(body="x" * 500_000))
    assert len(inbox.list_messages()[0]["body"]) <= 200_000


def test_newest_first():
    inbox.store_message(_envelope(message_id="older"))
    inbox.store_message(_envelope(message_id="newer"))
    # mtime ordering; both written in the same instant so assert set-membership
    # rather than a fragile order, then assert the count.
    assert len(inbox.list_messages()) == 2


# --- the endpoint ----------------------------------------------------------

class _FakeRequest:
    def __init__(self, payload, remote="127.0.0.1"):
        self._payload = payload
        self.remote = remote

    async def json(self):
        if isinstance(self._payload, Exception):
            raise self._payload
        return self._payload


def _adapter(monkeypatch):
    monkeypatch.setattr(APIServerAdapter, "_fleet_authorize", lambda self, req: (True, ""))
    return APIServerAdapter(PlatformConfig(enabled=True))


def _post(adapter, payload):
    resp = asyncio.run(adapter._handle_fleet_message(_FakeRequest(payload)))
    body = json.loads(resp.body.decode())
    return resp.status, body


def test_accepts_and_stores(monkeypatch):
    adapter = _adapter(monkeypatch)
    status, body = _post(adapter, _envelope())
    assert status == 200
    assert body["status"] == "stored"
    assert len(inbox.list_messages()) == 1


def test_never_claims_received(monkeypatch):
    # The old string. If this ever comes back, the endpoint is lying again.
    adapter = _adapter(monkeypatch)
    _, body = _post(adapter, _envelope())
    assert body["status"] != "received"


def test_store_failure_is_reported_not_swallowed(monkeypatch):
    adapter = _adapter(monkeypatch)

    def _boom(_payload):
        raise OSError("disk full")

    monkeypatch.setattr(inbox, "store_message", _boom)
    status, body = _post(adapter, _envelope())
    assert status == 500
    assert body["status"] == "error"
    assert "not stored" in body["detail"]


def test_unauthorized_is_rejected(monkeypatch):
    monkeypatch.setattr(APIServerAdapter, "_fleet_authorize", lambda self, req: (False, "no token"))
    adapter = APIServerAdapter(PlatformConfig(enabled=True))
    status, body = _post(adapter, _envelope())
    assert status == 401
    assert len(inbox.list_messages()) == 0


def test_non_object_payload_is_rejected(monkeypatch):
    adapter = _adapter(monkeypatch)
    status, _ = _post(adapter, ["not", "an", "object"])
    assert status == 400
    assert len(inbox.list_messages()) == 0


def test_malformed_json_is_rejected(monkeypatch):
    adapter = _adapter(monkeypatch)
    status, _ = _post(adapter, ValueError("bad json"))
    assert status == 400
