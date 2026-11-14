"""Editions and seat limits on the licence entitlement.

The rule these tests hold: the edition is fixed at provisioning, the seat limit
fails closed, and only Practice can exceed one named user. A corrupt entitlement
must never grant more capability than a valid one.
"""

from __future__ import annotations

import pytest

from centurion.license.store import (
    DEFAULT_TIER,
    EDITION_TIERS,
    PRACTICE_MAX_SEATS,
    PRACTICE_MIN_SEATS,
    Entitlement,
    normalise_tier,
)


def test_default_entitlement_is_the_most_restrictive_edition():
    ent = Entitlement()
    assert ent.edition() == "brain"
    assert ent.seat_limit() == 1
    assert ent.instrument_unlocked() is False


@pytest.mark.parametrize("tier", ["accountant", "association"])
def test_vertical_editions_unlock_the_instrument_for_one_user(tier):
    ent = Entitlement(tier=tier, seats=10)  # seats must be ignored outside Practice
    assert ent.edition() == tier
    assert ent.instrument_unlocked() is True
    assert ent.seat_limit() == 1


def test_practice_carries_the_seats_it_was_sold():
    ent = Entitlement(tier="practice", seats=6)
    assert ent.seat_limit() == 6
    assert ent.instrument_unlocked() is True


@pytest.mark.parametrize("seats,expected", [(10, 10), (11, PRACTICE_MAX_SEATS), (99, PRACTICE_MAX_SEATS)])
def test_practice_cannot_exceed_ten_users(seats, expected):
    assert Entitlement(tier="practice", seats=seats).seat_limit() == expected


@pytest.mark.parametrize("seats", [0, 1, -5])
def test_practice_floor_is_two_users(seats):
    assert Entitlement(tier="practice", seats=seats).seat_limit() == PRACTICE_MIN_SEATS


@pytest.mark.parametrize("junk", ["ten", None, object()])
def test_a_corrupt_seat_value_falls_back_to_the_practice_floor(junk):
    assert Entitlement(tier="practice", seats=junk).seat_limit() == PRACTICE_MIN_SEATS


def test_a_float_seat_value_is_truncated_not_trusted():
    assert Entitlement(tier="practice", seats=3.7).seat_limit() == 3


@pytest.mark.parametrize("tier", ["enterprise", "PRACTICE-PLUS", "", None, "admin"])
def test_unknown_tiers_fail_closed_to_the_brain(tier):
    ent = Entitlement(tier=tier)
    assert ent.edition() == "brain"
    assert ent.seat_limit() == 1
    assert ent.instrument_unlocked() is False


def test_tier_matching_is_case_and_space_insensitive():
    assert normalise_tier("  PRACTICE ") == "practice"
    assert Entitlement(tier=" Accountant ").edition() == "accountant"


def test_every_edition_in_the_published_spec_is_known():
    assert set(EDITION_TIERS) == {"brain", "accountant", "association", "practice"}
    assert DEFAULT_TIER == "brain"


def test_seats_survive_a_dict_round_trip():
    original = Entitlement(tier="practice", seats=7)
    restored = Entitlement.from_dict(original.to_dict())
    assert restored.tier == "practice"
    assert restored.seats == 7
    assert restored.seat_limit() == 7


def test_an_old_entitlement_without_seats_still_loads_as_one_user():
    legacy = {"tier": "accountant", "state": "subscription_active"}
    restored = Entitlement.from_dict(legacy)
    assert restored.seats == 1
    assert restored.seat_limit() == 1
