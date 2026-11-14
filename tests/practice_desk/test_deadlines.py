"""Deadlines: the arithmetic, and the obligation an entity type does or does not have.

The second half matters more than the first. A corporation tax date on a farm is
not a rounding error, it is the reason a partner stops trusting the pane — so the
tests here assert absence as firmly as presence.
"""

from __future__ import annotations

import datetime as dt

import pytest

from centurion_cli.practice_desk import deadlines as dl


def _client(**kw) -> dl.ClientRecord:
    base = dict(slug="c", name="Client", entity="Limited company", year_end=dt.date(2026, 12, 31))
    base.update(kw)
    return dl.ClientRecord(**base)


def _kinds(obligations) -> set[str]:
    return {o.kind for o in obligations}


# ── arithmetic ──────────────────────────────────────────────────────────────


def test_corporation_tax_is_nine_months_and_one_day_after_the_period_end():
    client = _client(year_end=dt.date(2026, 12, 31), entity="Limited company")
    found = dl.obligations_for(client, today=dt.date(2027, 8, 1), horizon_days=90)
    ct = [o for o in found if o.kind == "Corporation tax"]
    assert ct, "corporation tax missing for a company"
    assert ct[0].due == dt.date(2027, 10, 1)


def test_a_month_end_year_end_does_not_overflow_the_month():
    """30 June + 9 months is 30 March, not 2 April."""
    client = _client(year_end=dt.date(2026, 6, 30))
    found = dl.obligations_for(client, today=dt.date(2027, 2, 1), horizon_days=90)
    ct = [o for o in found if o.kind == "Corporation tax"][0]
    assert ct.due == dt.date(2027, 3, 31)  # 30 March + 1 day


def test_vat_is_one_month_and_seven_days_after_the_quarter_end():
    client = _client(vat_quarter_ends=[dt.date(2026, 9, 30)], payroll=False)
    found = dl.obligations_for(client, today=dt.date(2026, 10, 1), horizon_days=60)
    vat = [o for o in found if o.kind == "VAT return and payment"][0]
    # Quarter ending 30 September: the published deadline is 7 November, not the
    # 6th, which is what "one month plus seven days" produces if taken literally.
    assert vat.due == dt.date(2026, 11, 7)


def test_next_occurrence_rolls_forward_and_survives_a_leap_day():
    assert dl.next_occurrence(dt.date(2026, 1, 31), dt.date(2026, 1, 1)) == dt.date(2026, 1, 31)
    assert dl.next_occurrence(dt.date(2026, 1, 31), dt.date(2026, 2, 1)) == dt.date(2027, 1, 31)
    # 29 February in a non-leap year resolves to the 28th rather than raising.
    assert dl.next_occurrence(dt.date(2024, 2, 29), dt.date(2027, 1, 1)) == dt.date(2027, 2, 28)


def test_only_obligations_inside_the_horizon_are_returned():
    client = _client(year_end=dt.date(2026, 12, 31))
    found = dl.obligations_for(client, today=dt.date(2027, 9, 1), horizon_days=10)
    assert all(0 <= o.days_remaining <= 10 for o in found)
    assert not [o for o in found if o.kind == "Corporation tax"]


# ── the obligation belongs to the entity ────────────────────────────────────


def test_a_sole_trader_has_no_corporation_tax_and_no_statutory_accounts():
    client = _client(entity="Sole trader", year_end=dt.date(2026, 4, 5))
    found = dl.obligations_for(client, today=dt.date(2026, 11, 14), horizon_days=200)
    kinds = _kinds(found)
    assert "Corporation tax" not in kinds
    assert "Statutory accounts" not in kinds
    assert "Self assessment filing" in kinds


def test_a_partnership_files_a_partnership_return_not_corporation_tax():
    client = _client(entity="Partnership", year_end=dt.date(2026, 4, 5))
    found = dl.obligations_for(client, today=dt.date(2026, 11, 14), horizon_days=200)
    kinds = _kinds(found)
    assert "Partnership return" in kinds
    assert "Corporation tax" not in kinds


def test_a_limited_company_does_not_file_a_self_assessment():
    """The directors do, personally. The company file must not say otherwise."""
    client = _client(entity="Limited company")
    found = dl.obligations_for(client, today=dt.date(2026, 11, 14), horizon_days=400)
    kinds = _kinds(found)
    assert "Self assessment filing" not in kinds
    assert "Second payment on account" not in kinds
    assert "Corporation tax" in kinds
    assert "Statutory accounts" in kinds


def test_an_llp_files_accounts_but_not_corporation_tax():
    client = _client(entity="LLP", year_end=dt.date(2026, 3, 31))
    found = dl.obligations_for(client, today=dt.date(2026, 11, 14), horizon_days=200)
    kinds = _kinds(found)
    assert "Statutory accounts" in kinds
    assert "Corporation tax" not in kinds
    assert "Self assessment filing" in kinds


def test_p11d_only_where_there_is_a_payroll():
    with_payroll = dl.obligations_for(
        _client(payroll=True), today=dt.date(2026, 6, 1), horizon_days=60
    )
    without = dl.obligations_for(
        _client(payroll=False), today=dt.date(2026, 6, 1), horizon_days=60
    )
    assert "P11D" in _kinds(with_payroll)
    assert "P11D" not in _kinds(without)


# ── what it will not guess ──────────────────────────────────────────────────


def test_an_uncertain_client_is_reported_as_unsettled_rather_than_dated():
    client = _client(unsettled=["Year end changed; acknowledgement never received."])
    found = dl.obligations_for(client, today=dt.date(2026, 11, 14), horizon_days=30)
    unsettled = [o for o in found if o.unsettled]
    assert len(unsettled) == 1
    assert "acknowledgement" in unsettled[0].unsettled
    # And it is not counted among the settled obligations.
    assert dl.summarise(found)["count"] == len([o for o in found if not o.unsettled])


# ── the library ─────────────────────────────────────────────────────────────


def test_the_sample_practice_parses_and_produces_deadlines(tmp_path):
    from centurion_cli.practice_desk.demo import build_demo_library

    library = build_demo_library(tmp_path)
    records = dl.load_library(library)
    assert len(records) == 8
    assert all(r.year_end for r in records), "a client record is missing its year end"

    found = dl.upcoming(library, today=dt.date(2026, 11, 14), horizon_days=60)
    assert found, "the sample practice produced no deadlines at all"
    assert any(o.unsettled for o in found), "the sample must demonstrate an unsettled entry"

    # Entities are not mixed up: the farm must never carry corporation tax.
    farm = [o for o in found if "Fenwick" in o.client]
    assert farm and not [o for o in farm if o.kind == "Corporation tax"]
