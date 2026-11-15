"""Edge voice matching: the interface language should decide the accent.

The Brain can speak eleven languages but used to read all of them in one
American voice -- a Dutch sentence in English phonemes is not Dutch, it is
noise with Dutch spelling. These tests pin the matching rule only; the network
call to Edge's voice list is stubbed, because a test that needs the internet is
a test that will be skipped on the machine that matters.
"""

from __future__ import annotations

import asyncio

import pytest

from tools.tts_tool import (
    DEFAULT_EDGE_VOICE,
    _default_voice_for_language,
    _pick_voice_for_language,
)

VOICES = [
    {"ShortName": "en-US-AriaNeural", "Locale": "en-US"},
    {"ShortName": "en-GB-SoniaNeural", "Locale": "en-GB"},
    {"ShortName": "nl-NL-ColetteNeural", "Locale": "nl-NL"},
    {"ShortName": "nl-NL-MaartenNeural", "Locale": "nl-NL"},
    {"ShortName": "nl-BE-DenaNeural", "Locale": "nl-BE"},
    {"ShortName": "pl-PL-ZofiaNeural", "Locale": "pl-PL"},
    {"ShortName": "de-DE-KatjaNeural", "Locale": "de-DE"},
    {"ShortName": "de-DE-ResembleMultilingualNeural", "Locale": "de-DE"},
    {"ShortName": "ga-IE-OrlaNeural", "Locale": "ga-IE"},
]


def test_dutch_resolves_to_a_dutch_voice():
    assert _pick_voice_for_language(VOICES, "nl").startswith("nl-")


def test_polish_resolves_to_a_polish_voice():
    assert _pick_voice_for_language(VOICES, "pl") == "pl-PL-ZofiaNeural"


def test_a_region_variant_prefers_the_exact_tag():
    """nl-be should get the Belgian voice, not a Dutch one, when it exists."""
    assert _pick_voice_for_language(VOICES, "nl-be") == "nl-BE-DenaNeural"


def test_unknown_region_falls_back_to_the_language():
    assert _pick_voice_for_language(VOICES, "nl-au").startswith("nl-")


def test_multilingual_voices_are_a_last_resort():
    """They accept any text but carry an accent from nowhere in particular."""
    voice = _pick_voice_for_language(VOICES, "de")
    assert voice == "de-DE-KatjaNeural"


def test_a_language_edge_does_not_ship_returns_none():
    assert _pick_voice_for_language(VOICES, "xx") is None


def test_empty_language_returns_none():
    assert _pick_voice_for_language(VOICES, "") is None


def test_lookup_failure_falls_back_to_the_default_voice(monkeypatch):
    """Offline must mean English, never silence."""
    import tools.tts_tool as tts

    class BrokenEdge:
        @staticmethod
        async def list_voices():
            raise RuntimeError("no network")

    monkeypatch.setattr(tts, "_EDGE_LOCALE_VOICES", None)
    voice = asyncio.run(_default_voice_for_language(BrokenEdge, "nl"))
    assert voice == DEFAULT_EDGE_VOICE


def test_voice_list_is_fetched_once(monkeypatch):
    import tools.tts_tool as tts

    calls = {"n": 0}

    class CountingEdge:
        @staticmethod
        async def list_voices():
            calls["n"] += 1
            return VOICES

    monkeypatch.setattr(tts, "_EDGE_LOCALE_VOICES", None)
    try:
        asyncio.run(_default_voice_for_language(CountingEdge, "nl"))
        asyncio.run(_default_voice_for_language(CountingEdge, "pl"))
        assert calls["n"] == 1
    finally:
        monkeypatch.setattr(tts, "_EDGE_LOCALE_VOICES", None)
