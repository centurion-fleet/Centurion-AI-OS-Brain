"""The voice catalogue: one free house voice per language, premium male/female above it.

The contracts that matter, in the order they matter:

* a stock install cannot leak a paid voice;
* the free house voice per language is never lockable (intelligibility is the floor);
* a premium voice needs BOTH the licence tier AND a real configured provider id —
  an unconfigured slot must never be served;
* every refusal degrades to the house voice and *names* what it refused.
"""

from __future__ import annotations

import pytest

from centurion_cli import voice_catalogue as vc


def _lang(code, house, fem="", male="", label=None):
    return {
        "code": code,
        "label": label or code,
        "house_voice": house,
        "premium_voice_ids": {"female": fem, "male": male},
    }


def _tts(pack_tiers=None, languages=None):
    return {
        "provider": "edge",
        "voice_pack_tiers": list(pack_tiers or []),
        "voice_plan": {
            "languages": languages
            if languages is not None
            else [
                _lang("de-DE", "de-DE-KatjaNeural", "real-de-f", "real-de-m"),
                _lang("it-IT", "it-IT-ElsaNeural", "", ""),
            ]
        },
    }


# --- the floor: a free house voice per language, never lockable -----------------


def test_every_language_offers_exactly_one_free_house_voice():
    rows = vc.catalogue(tts=_tts(), tier="")
    de = [r for r in rows if r["language"] == "de-DE" and r["tier"] == vc.FREE_TIER]
    assert len(de) == 1
    assert de[0]["voice_id"] == "de-DE-KatjaNeural"
    assert de[0]["unlocked"] is True


def test_free_house_voice_is_never_lockable_on_any_tier():
    for tier in ("", "core", "brain", "anything", None):
        rows = vc.catalogue(tts=_tts(), tier=tier)
        free = [r for r in rows if r["tier"] == vc.FREE_TIER]
        assert free and all(r["unlocked"] is True for r in free)


def test_every_language_offers_two_premium_voices():
    rows = vc.catalogue(tts=_tts(), tier="core")
    prem = [r for r in rows if r["language"] == "de-DE" and r["tier"] == vc.PREMIUM_TIER]
    assert {r["gender"] for r in prem} == {"female", "male"}


# --- the two conditions on a premium voice --------------------------------------


def test_stock_install_unlocks_nothing_premium():
    """Empty voice_pack_tiers — a shipped product must not leak a paid voice."""
    rows = vc.catalogue(tts=_tts(), tier="core")
    assert not [r for r in rows if r["tier"] == vc.PREMIUM_TIER and r["unlocked"]]


def test_pack_tier_plus_configured_id_unlocks_and_does_not_over_unlock():
    tts = _tts(pack_tiers=["core"])
    rows = {r["id"]: r for r in vc.catalogue(tts=tts, tier="core")}
    assert rows["de-DE-premium-f"]["unlocked"] is True
    # configured, but the licence does NOT carry the pack
    rows_brain = {r["id"]: r for r in vc.catalogue(tts=tts, tier="brain")}
    assert rows_brain["de-DE-premium-f"]["unlocked"] is False


def test_configured_slot_still_locked_without_the_pack_tier():
    rows = {r["id"]: r for r in vc.catalogue(tts=_tts(), tier="core")}
    assert rows["de-DE-premium-f"]["configured"] is True
    assert rows["de-DE-premium-f"]["unlocked"] is False


def test_unconfigured_slot_is_never_unlocked_even_with_the_pack_tier():
    """An empty provider id must never be served, whatever the licence says."""
    rows = {r["id"]: r for r in vc.catalogue(tts=_tts(pack_tiers=["core"]), tier="core")}
    assert rows["it-IT-premium-f"]["configured"] is False
    assert rows["it-IT-premium-f"]["unlocked"] is False


# --- resolve: every refusal is named, never silent ------------------------------


def test_locked_request_degrades_to_house_and_names_it():
    got = vc.resolve("de-DE-premium-f", tts=_tts(), tier="core")
    assert got["tier"] == vc.FREE_TIER
    assert got["locked_out"] == "de-DE-premium-f"


def test_unconfigured_request_degrades_and_names_it():
    got = vc.resolve("it-IT-premium-m", tts=_tts(pack_tiers=["core"]), tier="core")
    assert got["tier"] == vc.FREE_TIER
    assert got["unconfigured"] == "it-IT-premium-m"


def test_unknown_voice_degrades_and_names_it():
    got = vc.resolve("does-not-exist", tts=_tts(), tier="core")
    assert got["id"] == "de-DE-house"
    assert got["unknown"] == "does-not-exist"


def test_a_refusal_lands_in_the_same_language_as_the_voice_refused():
    """A German premium voice refused must fall back to the German house voice,
    not to whichever language happens to be first in the plan. de-DE's slot is
    configured but the licence does not carry the pack -> locked_out."""
    got = vc.resolve("de-DE-premium-m", tts=_tts(pack_tiers=["core"]), tier="brain")
    assert got["language"] == "de-DE"
    assert got["voice_id"] == "de-DE-KatjaNeural"
    assert got["locked_out"] == "de-DE-premium-m"


def test_an_unconfigured_refusal_also_lands_in_its_own_language():
    got = vc.resolve("it-IT-premium-f", tts=_tts(pack_tiers=["core"]), tier="core")
    assert got["language"] == "it-IT"
    assert got["voice_id"] == "it-IT-ElsaNeural"
    assert got["unconfigured"] == "it-IT-premium-f"


def test_unlocked_request_is_honoured():
    got = vc.resolve("de-DE-premium-f", tts=_tts(pack_tiers=["core"]), tier="core")
    assert got["id"] == "de-DE-premium-f"
    assert got["voice_id"] == "real-de-f"


# --- language routing -----------------------------------------------------------


def test_resolve_picks_the_house_voice_for_the_asked_language():
    assert vc.resolve(None, language="it-IT", tts=_tts(), tier="")["id"] == "it-IT-house"


def test_resolve_falls_back_across_region_to_the_same_language():
    assert vc.resolve(None, language="de-AT", tts=_tts(), tier="")["id"] == "de-DE-house"


def test_resolve_with_no_language_returns_a_house_voice():
    got = vc.resolve(None, tts=_tts(), tier="")
    assert got["tier"] == vc.FREE_TIER
    assert got["configured"] is True


def test_languages_lists_the_markets_this_install_can_speak_to():
    assert vc.languages(tts=_tts()) == ["de-DE", "it-IT"]


# --- malformed input ------------------------------------------------------------


@pytest.mark.parametrize("bad", [None, {}, "junk", {"voice_plan": "junk"}, {"voice_plan": {"languages": None}}])
def test_malformed_config_does_not_raise(bad):
    rows = vc.catalogue(tts=bad if isinstance(bad, dict) else {}, tier="core")
    assert rows and all(r["unlocked"] for r in rows)


def test_malformed_language_entries_are_skipped():
    tts = _tts(languages=[None, {}, {"code": ""}, "junk", _lang("pl-PL", "pl-PL-ZofiaNeural")])
    rows = vc.catalogue(tts=tts, tier="")
    assert sorted({r["language"] for r in rows}) == ["pl-PL"]  # only the valid one survived
    assert len(rows) == 3  # its house voice + its two premium slots


# --- the config that actually ships ---------------------------------------------


def test_shipped_config_is_european_and_leaks_nothing_premium():
    """Against the REAL default config, not a fixture."""
    rows = vc.catalogue()
    free = [r for r in rows if r["tier"] == vc.FREE_TIER]
    prem = [r for r in rows if r["tier"] == vc.PREMIUM_TIER]

    langs = sorted(r["language"] for r in free)
    assert langs == ["de-DE", "en-IE", "es-ES", "fr-FR", "it-IT", "nl-NL", "pl-PL"], langs

    # No Asian or non-European languages in the core.
    assert not [c for c in langs if c.split("-")[0] in {"ja", "ko", "zh", "th", "vi", "id"}]

    # Every free house voice is real and configured.
    assert all(r["configured"] for r in free), [r for r in free if not r["configured"]]

    # Two premium slots per language, all filled, none unlocked.
    assert len(prem) == 14
    assert all(r["configured"] for r in prem), [r["id"] for r in prem if not r["configured"]]
    assert not any(r["unlocked"] for r in prem)

    # Every premium id is a real, distinct provider id — and none is invented.
    ids = [r["voice_id"] for r in prem]
    assert all(ids), "an empty premium slot reached the shipped catalogue"
    assert len(set(ids)) == 14, f"duplicate premium voice ids: {sorted(ids)}"

    # Both genders are offered per language.
    for lang in langs:
        got = {r["gender"] for r in prem if r["language"] == lang}
        assert got == {"female", "male"}, (lang, got)

    # Gender is a reading of the name, never asserted as verified fact.
    assert not any(r["gender_verified"] for r in prem)

    # And the shipped English voice is not American.
    en = next(r for r in free if r["language"] == "en-IE")
    assert en["voice_id"] == "en-IE-EmilyNeural"


def test_shipped_premium_quality_is_recorded_and_the_weak_slots_are_known():
    """The uneven slots are a known, recorded fact — not a surprise in front of a buyer."""
    prem = {r["id"]: r for r in vc.catalogue() if r["tier"] == vc.PREMIUM_TIER}
    assert prem["de-DE-premium-f"]["quality"] == "low"
    assert prem["it-IT-premium-m"]["quality"] == "x_low"
    assert prem["pl-PL-premium-m"]["quality"] == "high"
    # every slot states a quality, so the tier can be judged before it is sold
    assert all(r["quality"] for r in prem.values())
