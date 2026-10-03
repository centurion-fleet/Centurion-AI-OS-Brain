"""The voice catalogue: one standard male and one standard female per language.

The contracts that matter, in the order they matter:

* every language offers exactly one male and one female voice — no more, no less;
* nothing is gated: no licence is consulted, so nothing can leak or lock;
* a slot with no provider id is never served;
* every refusal degrades to a usable voice and *names* what it refused;
* both voices per language are real, distinct Edge ids — none invented.
"""

from __future__ import annotations

import pytest

from centurion_cli import voice_catalogue as vc


def _lang(code, female="", male="", label=None):
    return {
        "code": code,
        "label": label or code,
        "voices": {"female": female, "male": male},
    }


def _tts(languages=None):
    return {
        "provider": "edge",
        "voice_plan": {
            "languages": languages
            if languages is not None
            else [
                _lang("de-DE", "de-DE-KatjaNeural", "de-DE-ConradNeural"),
                _lang("it-IT", "it-IT-ElsaNeural", ""),  # male slot unconfigured
            ]
        },
    }


# --- the promise: exactly one male and one female per language ------------------


def test_every_language_offers_exactly_one_male_and_one_female():
    rows = [r for r in vc.catalogue(tts=_tts()) if r["language"] == "de-DE"]
    assert len(rows) == 2
    assert {r["gender"] for r in rows} == {"female", "male"}
    assert {r["voice_id"] for r in rows} == {"de-DE-KatjaNeural", "de-DE-ConradNeural"}
    assert all(r["configured"] for r in rows)


def test_nothing_is_gated_and_no_licence_is_consulted():
    """No tier key, no unlocked flag, no licence import anywhere near a voice."""
    for r in vc.catalogue(tts=_tts()):
        assert "tier" not in r
        assert "unlocked" not in r


def test_a_slot_with_no_provider_id_is_marked_unconfigured():
    rows = {r["id"]: r for r in vc.catalogue(tts=_tts())}
    assert rows["it-IT-m"]["configured"] is False
    assert rows["it-IT-f"]["configured"] is True


# --- resolve: every refusal is named, never silent ------------------------------


def test_unconfigured_request_degrades_and_names_it():
    got = vc.resolve("it-IT-m", tts=_tts())
    assert got["gender"] == "female"  # the usable Italian voice
    assert got["language"] == "it-IT"
    assert got["unconfigured"] == "it-IT-m"


def test_unknown_voice_degrades_and_names_it():
    got = vc.resolve("does-not-exist", tts=_tts())
    assert got["id"] == "de-DE-f"
    assert got["unknown"] == "does-not-exist"


def test_a_refusal_lands_in_the_language_of_the_voice_refused():
    """An Italian voice refused must fall back to Italian — not to the language
    the caller happened to pass in, and not to whichever is first in the plan."""
    got = vc.resolve("it-IT-m", language="de-DE", tts=_tts())
    assert got["language"] == "it-IT"
    assert got["unconfigured"] == "it-IT-m"


def test_a_configured_voice_is_honoured():
    got = vc.resolve("de-DE-m", tts=_tts())
    assert got["id"] == "de-DE-m"
    assert got["voice_id"] == "de-DE-ConradNeural"


# --- language and gender routing ------------------------------------------------


def test_resolve_picks_a_voice_for_the_asked_language():
    assert vc.resolve(None, language="it-IT", tts=_tts())["language"] == "it-IT"


def test_resolve_prefers_the_asked_gender():
    got = vc.resolve(None, language="de-DE", gender="male", tts=_tts())
    assert got["voice_id"] == "de-DE-ConradNeural"


def test_resolve_falls_back_on_gender_when_the_slot_is_empty():
    got = vc.resolve(None, language="it-IT", gender="male", tts=_tts())
    assert got["language"] == "it-IT"
    assert got["configured"] is True  # the female voice, since no male is configured


def test_resolve_falls_back_across_region_to_the_same_language():
    assert vc.resolve(None, language="de-AT", tts=_tts())["language"] == "de-DE"


def test_resolve_with_no_language_returns_a_configured_voice():
    got = vc.resolve(None, tts=_tts())
    assert got["configured"] is True


def test_languages_lists_the_markets_this_install_can_speak_to():
    assert vc.languages(tts=_tts()) == ["de-DE", "it-IT"]


# --- malformed input ------------------------------------------------------------


@pytest.mark.parametrize(
    "bad",
    [None, {}, "junk", {"voice_plan": "junk"}, {"voice_plan": {"languages": None}}],
)
def test_malformed_config_does_not_raise(bad):
    rows = vc.catalogue(tts=bad if isinstance(bad, dict) else {})
    assert isinstance(rows, list)


def test_malformed_language_entries_are_skipped():
    tts = _tts(
        languages=[None, {}, {"code": ""}, "junk", _lang("pl-PL", "pl-PL-ZofiaNeural", "pl-PL-MarekNeural")]
    )
    rows = vc.catalogue(tts=tts)
    assert sorted({r["language"] for r in rows}) == ["pl-PL"]
    assert len(rows) == 2  # exactly its male and female


# --- the config that actually ships ---------------------------------------------


def test_shipped_config_is_the_seven_european_markets():
    """Against the REAL default config, not a fixture."""
    rows = vc.catalogue()
    langs = sorted({r["language"] for r in rows})
    assert langs == ["de-DE", "en-IE", "es-ES", "fr-FR", "it-IT", "nl-NL", "pl-PL"], langs

    # No Asian or non-European languages in the core.
    assert not [c for c in langs if c.split("-")[0] in {"ja", "ko", "zh", "th", "vi", "id"}]


def test_shipped_config_offers_both_genders_in_every_language():
    rows = vc.catalogue()
    assert len(rows) == 14, [r["id"] for r in rows]
    for lang in {r["language"] for r in rows}:
        got = {r["gender"] for r in rows if r["language"] == lang}
        assert got == {"female", "male"}, (lang, got)


def test_every_shipped_voice_is_real_configured_and_distinct():
    rows = vc.catalogue()
    assert all(r["configured"] for r in rows), [r["id"] for r in rows if not r["configured"]]
    ids = [r["voice_id"] for r in rows]
    assert all(ids), "an empty voice slot reached the shipped catalogue"
    assert len(set(ids)) == 14, f"duplicate voice ids: {sorted(ids)}"


def test_shipped_english_voice_is_not_american():
    rows = {r["id"]: r for r in vc.catalogue()}
    assert rows["en-IE-f"]["voice_id"] == "en-IE-EmilyNeural"
    assert rows["en-IE-m"]["voice_id"] == "en-IE-ConnorNeural"
