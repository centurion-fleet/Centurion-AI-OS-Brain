"""Tests for the shared activity board.

Two owners, two linked Centurions, one question: what is actually in progress,
on which machine, right now. A green dot does not answer it. These tests pin the
two rules that keep the board honest:

* it reports real in-progress work and says nothing when there is none — it
  never manufactures busy-looking items;
* a peer that goes quiet keeps its last known state on the board, because an
  emptied board reads as "idle" when the truth is "nobody can see it".
"""

from __future__ import annotations

import asyncio
import json

import pytest

from centurion.fleet import activity
from centurion.fleet.peers import FleetPeer, FleetPeers
from gateway.config import PlatformConfig
from gateway.platforms.api_server import APIServerAdapter


@pytest.fixture(autouse=True)
def isolated_home(tmp_path, monkeypatch):
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path))
    return tmp_path


def _stack(*targets, mission="Scale Centurion", supporting=None):
    """A mission stack shaped like the real one, trimmed to what matters here."""
    return {
        "primary": {
            "title": mission,
            "targets": [dict(t) for t in targets],
        },
        "supporting": supporting or [],
    }


def _target(title, status, target_id="t-1"):
    return {"id": target_id, "title": title, "status": status}


# --- what counts as work ---------------------------------------------------

def test_only_in_progress_counts():
    stack = _stack(
        _target("Instrument the sales funnel", "in_progress", "a"),
        _target("Ship the installer", "not_started", "b"),
        _target("Scale sales to 10/mo", "complete", "c"),
    )
    items = activity.working_items(stack_loader=lambda: stack)
    assert [i["target"] for i in items] == ["Instrument the sales funnel"]


def test_nothing_in_progress_reports_nothing():
    # The honest answer. A board that invents an item to look busy is worse
    # than an empty one.
    stack = _stack(_target("Ship the installer", "not_started"))
    assert activity.working_items(stack_loader=lambda: stack) == []


def test_no_mission_store_is_not_an_error():
    assert activity.working_items(stack_loader=lambda: {}) == []


def test_respects_the_limit_and_keeps_the_primary_mission_first():
    stack = _stack(
        _target("First", "in_progress", "a"),
        _target("Second", "in_progress", "b"),
        _target("Third", "in_progress", "c"),
        _target("Fourth", "in_progress", "d"),
        supporting=[
            {
                "title": "Supporting mission",
                "targets": [_target("Supporting work", "in_progress", "e")],
            }
        ],
    )
    items = activity.working_items(limit=2, stack_loader=lambda: stack)
    assert [i["target"] for i in items] == ["First", "Second"]
    assert items[0]["mission"] == "Scale Centurion"


def test_supporting_missions_are_included_when_the_primary_has_no_work():
    stack = _stack(
        _target("Later", "not_started", "a"),
        supporting=[
            {
                "title": "Living on the yacht",
                "targets": [_target("Find the boat", "in_progress", "b")],
            }
        ],
    )
    items = activity.working_items(stack_loader=lambda: stack)
    assert [i["target"] for i in items] == ["Find the boat"]
    assert items[0]["mission"] == "Living on the yacht"


def test_the_default_path_never_raises():
    # The real loader swallows an absent or broken store and reports no work.
    # Nothing about the board may take down the caller — an owner asking "what
    # is happening" must get an answer, even if that answer is "nothing yet".
    assert activity.working_items() == []
    assert activity.local_activity()["working_on"] == []


def test_reading_does_not_create_a_mission_store(tmp_path):
    # Being asked what someone is doing must not write a database.
    assert not (tmp_path / "life" / "life.db").exists()
    assert activity.working_items() == []
    assert not (tmp_path / "life" / "life.db").exists()


# --- this Centurion's own payload ------------------------------------------

def test_local_activity_has_the_shape_the_board_renders():
    payload = activity.local_activity()
    assert set(payload) == {
        "centurion_id",
        "name",
        "version",
        "working_on",
        "captured_at",
    }
    assert payload["name"], "a Centurion with no name cannot be directed"
    assert payload["working_on"] == []


# --- what we accept from a peer --------------------------------------------

def test_parse_rejects_junk():
    assert activity.parse_activity(None) == {}
    assert activity.parse_activity("nope") == {}
    assert activity.parse_activity([]) == {}
    # An entry with no target is not work.
    assert activity.parse_activity({"working_on": [{}]})["working_on"] == []


def test_parse_bounds_what_a_peer_can_write_into_our_records():
    fat = {
        "name": "E" * 5_000,
        "version": "9" * 5_000,
        "working_on": [
            {"target": "T" * 5_000, "mission": "M" * 5_000}
            for _ in range(50)
        ],
    }
    parsed = activity.parse_activity(fat)
    assert len(parsed["name"]) <= activity.MAX_TEXT
    assert len(parsed["version"]) <= activity.MAX_TEXT
    assert len(parsed["working_on"]) <= activity.MAX_ITEMS_ACCEPTED
    assert all(len(i["target"]) <= activity.MAX_TEXT for i in parsed["working_on"])


def test_parse_tolerates_a_missing_timestamp():
    parsed = activity.parse_activity({"working_on": [{"target": "Ship it"}]})
    assert parsed["captured_at"] == 0.0


# --- storing what a peer told us -------------------------------------------

def _register_peer(peer_id="eve-1", name="Eve", address="http://127.0.0.1:9"):
    FleetPeers().register(FleetPeer(centurion_id=peer_id, name=name, address=address))


def _peer(peer_id="eve-1") -> FleetPeer:
    peer = FleetPeers().get(peer_id)
    assert peer is not None, f"{peer_id} should be registered"
    return peer


def test_activity_is_stored_against_the_right_peer():
    _register_peer()
    ok = activity.record_peer_activity(
        "eve-1",
        {"name": "Eve", "version": "6.0.10", "working_on": [{"target": "Pricing sheet"}]},
    )
    assert ok is True
    stored = _peer().activity
    assert stored["working_on"][0]["target"] == "Pricing sheet"
    assert stored["version"] == "6.0.10"


def test_unknown_peer_is_refused_rather_than_invented():
    assert activity.record_peer_activity("stranger", {"working_on": []}) is False


def test_unusable_activity_leaves_the_last_known_state_alone():
    _register_peer()
    activity.record_peer_activity("eve-1", {"working_on": [{"target": "Real work"}]})
    assert activity.record_peer_activity("eve-1", None) is False
    # The earlier, real report must survive a later malformed one.
    assert _peer().activity["working_on"][0]["target"] == "Real work"


def test_stored_activity_survives_a_reload(tmp_path):
    _register_peer()
    activity.record_peer_activity("eve-1", {"working_on": [{"target": "Pricing sheet"}]})
    assert _peer().activity["working_on"][0]["target"] == "Pricing sheet"


# --- the endpoints ---------------------------------------------------------

class _FakeRequest:
    def __init__(self, payload=None, remote="127.0.0.1"):
        self._payload = payload or {}
        self.remote = remote
        self.query = {}

    async def json(self):
        if isinstance(self._payload, Exception):
            raise self._payload
        return self._payload


def _adapter(monkeypatch):
    monkeypatch.setattr(APIServerAdapter, "_fleet_authorize", lambda self, req: (True, ""))
    return APIServerAdapter(PlatformConfig(enabled=True))


def _checkin(adapter, payload):
    resp = asyncio.run(adapter._handle_fleet_checkin(_FakeRequest(payload)))
    return resp.status, json.loads(resp.body.decode())


def test_checkin_records_what_the_peer_is_working_on(monkeypatch):
    _register_peer()
    adapter = _adapter(monkeypatch)
    status, body = _checkin(
        adapter,
        {
            "centurion_id": "eve-1",
            "status": "active",
            "version": "6.0.10",
            "activity": {"working_on": [{"target": "Pricing sheet"}]},
        },
    )
    assert status == 200
    assert body["status"] == "acknowledged"
    assert body["activity_recorded"] is True
    peer = _peer()
    assert peer.version == "6.0.10"
    assert peer.last_seen > 0
    assert peer.activity["working_on"][0]["target"] == "Pricing sheet"


def test_checkin_without_activity_still_acknowledges(monkeypatch):
    # Presence alone is a legitimate check-in; it must not be an error.
    _register_peer()
    adapter = _adapter(monkeypatch)
    status, body = _checkin(adapter, {"centurion_id": "eve-1", "version": "6.0.10"})
    assert status == 200
    assert body["activity_recorded"] is False
    assert _peer().version == "6.0.10"


def test_checkin_from_an_unknown_peer_is_still_acknowledged(monkeypatch):
    # A peer we have not stored cannot have activity filed against it, but the
    # check-in itself is valid and must not read as a failure.
    adapter = _adapter(monkeypatch)
    status, body = _checkin(
        adapter,
        {"centurion_id": "mikki-1", "version": "6.0.10", "activity": {"working_on": []}},
    )
    assert status == 200
    assert body["activity_recorded"] is False


def test_checkin_is_refused_without_the_fleet_token(monkeypatch):
    monkeypatch.setattr(
        APIServerAdapter, "_fleet_authorize", lambda self, req: (False, "no token")
    )
    adapter = APIServerAdapter(PlatformConfig(enabled=True))
    status, body = _checkin(adapter, {"centurion_id": "eve-1"})
    assert status == 401
    assert body["status"] == "unauthorized"
