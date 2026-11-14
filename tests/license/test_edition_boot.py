"""The edition read at boot, the seat limit enforced, and a re-bind refused.

The rule these tests hold (business/EDITIONS.md §1, §8): the edition is fixed at
provisioning and bound to the machine; the licence server is authoritative and an
edition edited on a machine is a lie until the next check-in; a re-bind is a
repair, never an upgrade. Fail closed, always.
"""

from __future__ import annotations

import json

import pytest

import importlib

from centurion.license import edition as edition_mod
from centurion.license.audit import audit_path
from centurion.license.edition import (
    Edition,
    edition_label,
    more_restrictive,
    rebind_refusal,
    resolve_edition,
)
from centurion.license.store import Entitlement


@pytest.fixture(autouse=True)
def _clean_boot_record():
    edition_mod.reset_cache()
    yield
    edition_mod.reset_cache()


def _phone_home_module():
    """The module, not the function of the same name exported by the package."""
    return importlib.import_module("centurion.license.phone_home")


def _events() -> list[dict]:
    path = audit_path()
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def _write_prior(tier: str, *, fingerprint=None, verified_at=None) -> None:
    path = edition_mod.boot_record_path()
    path.write_text(
        json.dumps(
            {
                "tier": tier,
                "seats": 1,
                "fingerprint": fingerprint or resolution_fingerprint(),
                "state": "subscription_active",
                "verified_at": verified_at,
            }
        )
    )


def resolution_fingerprint():
    from centurion.license.fingerprint import compute_fingerprint

    return compute_fingerprint(include_remote=False)


# ── What the machine says about itself ───────────────────────────────────────


def test_a_bare_machine_resolves_to_the_brain_with_the_instrument_greyed():
    ed = resolve_edition(Entitlement())
    assert ed.tier == "brain"
    assert ed.label == "Centurion Brain"
    assert ed.seat_limit == 1
    assert ed.instrument_unlocked is False


def test_a_practice_resolves_to_its_sold_seats_and_a_live_instrument():
    ed = resolve_edition(Entitlement(tier="practice", seats=6))
    assert ed.is_practice
    assert ed.seat_limit == 6
    assert ed.instrument_unlocked is True
    assert ed.label == "Centurion Accountant Practice"


@pytest.mark.parametrize("tier", ["accountant", "association"])
def test_a_vertical_brain_is_one_user_and_live(tier):
    ed = resolve_edition(Entitlement(tier=tier))
    assert ed.seat_limit == 1
    assert ed.instrument_unlocked is True
    assert ed.label == edition_label(tier)


def test_boot_writes_a_record_and_the_second_boot_is_quiet():
    first = resolve_edition(Entitlement(tier="accountant"))
    assert edition_mod.read_boot_record()["tier"] == "accountant"
    second = resolve_edition(Entitlement(tier="accountant"))
    assert second.tampered is False
    assert second.tier == first.tier


# ── A local edit cannot grant a capability ───────────────────────────────────


def test_an_edition_edited_on_disk_is_held_back_until_a_check_in():
    _write_prior("brain")
    ed = resolve_edition(Entitlement(tier="practice", seats=10, last_verified_at=None))
    assert ed.tier == "brain", "a local edit must not become a capability"
    assert ed.seat_limit == 1
    assert ed.instrument_unlocked is False
    assert ed.tampered is True
    assert "holding at" in ed.note
    assert any(e["event"] == "edition_tamper_detected" for e in _events())


def test_a_verified_check_in_makes_a_new_edition_believable():
    _write_prior("brain", verified_at=1_000.0)
    ed = resolve_edition(Entitlement(tier="practice", seats=4, last_verified_at=2_000.0))
    assert ed.tier == "practice"
    assert ed.tampered is False
    assert "confirmed at check-in" in ed.note


def test_a_different_fingerprint_is_a_replacement_not_a_tamper():
    _write_prior("practice", fingerprint="some-other-machine", verified_at=1_000.0)
    ed = resolve_edition(Entitlement(tier="brain", last_verified_at=None))
    assert ed.tier == "brain"
    assert ed.tampered is False


def test_a_downgrade_on_disk_is_taken_because_it_is_the_safer_reading():
    _write_prior("practice")
    ed = resolve_edition(Entitlement(tier="brain"))
    assert ed.tier == "brain"
    assert ed.instrument_unlocked is False


def test_more_restrictive_always_answers_with_the_lower_edition():
    assert more_restrictive("practice", "brain") == "brain"
    assert more_restrictive("brain", "practice") == "brain"
    assert more_restrictive("accountant", "practice") == "accountant"
    # An unknown tier normalises to the Brain before the comparison, so it can
    # never win one: fail closed.
    assert more_restrictive("nonsense", "association") == "brain"


# ── Seats ────────────────────────────────────────────────────────────────────


def test_practice_admits_ten_named_users_and_refuses_the_eleventh():
    ed = resolve_edition(Entitlement(tier="practice", seats=10))
    assert ed.admits(10) is True
    assert ed.admits(11) is False
    refusal = ed.refusal(11)
    assert "eleventh" in refusal
    assert "second machine" in refusal


def test_a_vertical_brain_refuses_the_second_user():
    ed = resolve_edition(Entitlement(tier="accountant"))
    assert ed.admits(1) is True
    assert ed.admits(2) is False
    assert "second" in ed.refusal(2)


def test_an_unreadable_user_count_is_refused_rather_than_guessed():
    ed = resolve_edition(Entitlement(tier="practice", seats=5))
    assert ed.admits("five") is False
    assert ed.admits(None) is False


# ── Re-bind is a repair, never an upgrade ───────────────────────────────────


@pytest.mark.parametrize("tier", ["brain", "accountant", "association", "practice"])
def test_rebinding_to_the_same_edition_is_allowed(tier):
    assert rebind_refusal(tier, tier) is None


@pytest.mark.parametrize(
    "current,requested",
    [("brain", "practice"), ("accountant", "practice"), ("practice", "brain")],
)
def test_rebinding_across_editions_is_refused(current, requested):
    refusal = rebind_refusal(current, requested)
    assert refusal is not None
    assert "repair, never an upgrade" in refusal


def test_no_requested_edition_means_no_refusal():
    assert rebind_refusal("practice", None) is None
    assert rebind_refusal("practice", "") is None


def test_request_reissue_refuses_before_it_sends_anything(monkeypatch):
    from centurion.license.activate import request_reissue

    monkeypatch.setattr(
        "centurion.license.activate.load_entitlement",
        lambda: Entitlement(tier="accountant", license_id="lic-1"),
    )
    sent = []
    monkeypatch.setattr(
        "centurion.license.activate._post_json",
        lambda url, payload, **kw: sent.append(payload) or {},
    )

    result = request_reissue(reason="hardware_failure", requested_edition="practice")

    assert result.ok is False
    assert "repair, never an upgrade" in result.error
    assert sent == [], "the request must never leave the machine"
    assert any(e["event"] == "reissue_refused_edition_change" for e in _events())


def test_request_reissue_sends_the_edition_and_seats_it_is_repairing(monkeypatch):
    from centurion.license.activate import request_reissue

    ent = Entitlement(tier="practice", seats=7, license_id="lic-2")
    monkeypatch.setattr("centurion.license.activate.load_entitlement", lambda: ent)
    sent = []

    def fake_post(url, payload, **kw):
        sent.append(payload)
        return {"ok": True, "status": "pending", "edition": "practice"}

    monkeypatch.setattr("centurion.license.activate._post_json", fake_post)

    result = request_reissue(reason="dead_box")

    assert result.ok is True
    assert sent[0]["edition"] == "practice"
    assert sent[0]["seats"] == 7


def test_a_server_answer_on_a_different_edition_is_refused(monkeypatch):
    from centurion.license.activate import request_reissue

    monkeypatch.setattr(
        "centurion.license.activate.load_entitlement",
        lambda: Entitlement(tier="brain", license_id="lic-3"),
    )
    monkeypatch.setattr(
        "centurion.license.activate._post_json",
        lambda url, payload, **kw: {"ok": True, "status": "issued", "edition": "practice"},
    )

    result = request_reissue(reason="hardware_failure")

    assert result.ok is False
    assert any(e["event"] == "reissue_refused_server_edition_change" for e in _events())


# ── The check-in carries the edition both ways ──────────────────────────────


def test_checkin_sends_the_edition_and_applies_the_server_seat_count(monkeypatch):
    from centurion.license.phone_home import phone_home as check_in

    ent = Entitlement(tier="practice", seats=2, license_id="lic-4", state="subscription_active")
    sent = {}

    def fake_post(url, payload, timeout=15.0):
        sent.update(payload)
        return {"ok": True, "state": "subscription_active", "tier": "practice", "seats": 9}

    monkeypatch.setattr(_phone_home_module(), "_post_json", fake_post)

    result = check_in(entitlement=ent, force=True)

    assert result.ok is True
    assert sent["edition"] == "practice"
    assert sent["seats"] == 2
    assert result.seats == 9
    assert ent.seats == 9
    assert ent.seat_limit() == 9


def test_a_checkin_without_seats_leaves_the_local_value_alone(monkeypatch):
    from centurion.license.phone_home import phone_home as check_in

    ent = Entitlement(tier="practice", seats=5, state="subscription_active")
    monkeypatch.setattr(
        _phone_home_module(),
        "_post_json",
        lambda url, payload, timeout=15.0: {"ok": True},
    )

    check_in(entitlement=ent, force=True)
    assert ent.seats == 5


def test_the_server_cannot_hand_a_machine_more_than_ten_seats(monkeypatch):
    from centurion.license.phone_home import phone_home as check_in

    ent = Entitlement(tier="practice", seats=2, state="subscription_active")
    monkeypatch.setattr(
        _phone_home_module(),
        "_post_json",
        lambda url, payload, timeout=15.0: {"ok": True, "seats": 99},
    )

    check_in(entitlement=ent, force=True)
    assert ent.seat_limit() == 10


def test_a_brain_cannot_be_given_seats_by_the_server(monkeypatch):
    from centurion.license.phone_home import phone_home as check_in

    ent = Entitlement(tier="brain", state="subscription_active")
    monkeypatch.setattr(
        _phone_home_module(),
        "_post_json",
        lambda url, payload, timeout=15.0: {"ok": True, "seats": 8},
    )

    check_in(entitlement=ent, force=True)
    assert ent.seats == 8  # stored, but the edition still governs
    assert ent.seat_limit() == 1


def test_edition_resolution_is_idempotent_and_never_raises():
    ed = resolve_edition(None)
    assert isinstance(ed, Edition)
    assert ed.tier in {"brain", "accountant", "association", "practice"}
