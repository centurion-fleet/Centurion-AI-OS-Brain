"""The agent has to know what language the person is reading.

The Brain carries sixteen catalogues for its own interface strings, and until
now nothing told the agent anything about language at all: a French buyer could
set the interface to French and be answered in English, because the system prompt
had no language in it. This is that layer.

Rules under test:
  1. English produces nothing — a setting nobody changed must not alter a prompt
     that has already been verified.
  2. A non-English setting produces a directive naming the language in its own
     words (endonym), not just a code.
  3. Code, paths and identifiers are excluded from translation — a translated
     command does not run.
  4. Every supported code has an endonym, so no language can render as "English".
"""

from __future__ import annotations

import pytest

from agent import i18n
from agent.prompt_builder import build_language_lock


@pytest.fixture(autouse=True)
def _clear_env(monkeypatch):
    monkeypatch.delenv("CENTURION_LANGUAGE", raising=False)


def test_english_gives_no_directive(monkeypatch):
    monkeypatch.setenv("CENTURION_LANGUAGE", "en")
    assert build_language_lock() == ""


def test_french_names_the_language_and_its_code(monkeypatch):
    monkeypatch.setenv("CENTURION_LANGUAGE", "fr")
    lock = build_language_lock()
    assert "Français" in lock
    assert "(fr)" in lock
    assert "Reply in Français" in lock


@pytest.mark.parametrize(
    "value,expected",
    [
        ("de", "Deutsch"),
        ("it", "Italiano"),
        ("es", "Español"),
        ("fr-FR", "Français"),
        ("FR", "Français"),
        ("français", "Français"),
        ("ga-IE", "Gaeilge"),
    ],
)
def test_aliases_and_regional_tags_resolve(monkeypatch, value, expected):
    monkeypatch.setenv("CENTURION_LANGUAGE", value)
    assert i18n.language_name(i18n.get_language()) == expected


def test_unknown_language_falls_back_to_english_silently(monkeypatch):
    monkeypatch.setenv("CENTURION_LANGUAGE", "klingon")
    assert build_language_lock() == ""


def test_code_and_paths_are_excluded_from_translation(monkeypatch):
    monkeypatch.setenv("CENTURION_LANGUAGE", "fr")
    lock = build_language_lock().lower()
    for token in ("code", "file paths", "command lines", "tool names", "identifiers"):
        assert token in lock, token


def test_it_never_announces_the_language(monkeypatch):
    monkeypatch.setenv("CENTURION_LANGUAGE", "fr")
    lock = build_language_lock()
    assert "without announcing it" in lock


def test_the_person_message_outranks_the_setting(monkeypatch):
    monkeypatch.setenv("CENTURION_LANGUAGE", "fr")
    assert "more current than their setting" in build_language_lock()


def test_every_supported_language_has_an_endonym():
    """A code with no name would render as English and be silently wrong."""
    missing = [c for c in i18n.SUPPORTED_LANGUAGES if c not in i18n.LANGUAGE_NAMES]
    assert missing == []


def test_endonyms_are_not_flags_or_english_exonyms():
    """A person must recognise their own language without translating first."""
    assert i18n.language_name("fr") == "Français"
    assert i18n.language_name("hu") == "Magyar"
    assert i18n.language_name("de") == "Deutsch"
