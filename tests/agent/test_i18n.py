"""Tests for agent.i18n -- catalog parity, fallback, language resolution."""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from agent import i18n


LOCALES_DIR = Path(__file__).resolve().parents[2] / "agent" / "locales"


def _load_raw(lang: str) -> dict:
    with (LOCALES_DIR / f"{lang}.yaml").open("r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def _flatten(d, prefix="") -> dict:
    flat = {}
    for k, v in (d or {}).items():
        key = f"{prefix}.{k}" if prefix else k
        if isinstance(v, dict):
            flat.update(_flatten(v, key))
        else:
            flat[key] = v
    return flat


# ---------------------------------------------------------------------------
# Catalog completeness -- this is the key invariant test.  If someone adds a
# new key to en.yaml they MUST add it to every other locale, else runtime
# falls back to English for those users and defeats the feature.
# ---------------------------------------------------------------------------

def test_all_locales_exist():
    """Every supported language must have a catalog file on disk."""
    for lang in i18n.SUPPORTED_LANGUAGES:
        assert (LOCALES_DIR / f"{lang}.yaml").is_file(), f"missing locales/{lang}.yaml"


@pytest.mark.parametrize("lang", [l for l in i18n.SUPPORTED_LANGUAGES if l != "en"])
def test_catalog_keys_match_english(lang: str):
    """Every non-English catalog must have exactly the same key set as English."""
    en_keys = set(_flatten(_load_raw("en")).keys())
    lang_keys = set(_flatten(_load_raw(lang)).keys())
    missing = en_keys - lang_keys
    extra = lang_keys - en_keys
    assert not missing, f"{lang}.yaml missing keys: {sorted(missing)}"
    assert not extra, f"{lang}.yaml has keys not in en.yaml: {sorted(extra)}"


@pytest.mark.parametrize("lang", list(i18n.SUPPORTED_LANGUAGES))
def test_catalog_placeholders_match_english(lang: str):
    """Every translated value must use the same {placeholder} tokens as English.

    A mistranslated placeholder (e.g. ``{description}`` typoed as ``{descricao}``)
    would either raise KeyError at runtime or silently drop the interpolated
    value.  Pin parity at the test layer.
    """
    import re
    placeholder_re = re.compile(r"\{([a-zA-Z_][a-zA-Z0-9_]*)\}")
    en_flat = _flatten(_load_raw("en"))
    lang_flat = _flatten(_load_raw(lang))
    for key, en_value in en_flat.items():
        en_placeholders = set(placeholder_re.findall(en_value))
        lang_value = lang_flat.get(key, "")
        lang_placeholders = set(placeholder_re.findall(lang_value))
        assert en_placeholders == lang_placeholders, (
            f"{lang}.yaml key={key!r}: placeholders {lang_placeholders} "
            f"don't match English {en_placeholders}"
        )


# ---------------------------------------------------------------------------
# Language resolution
# ---------------------------------------------------------------------------

def test_normalize_lang_accepts_supported():
    assert i18n._normalize_lang("nl") == "nl"
    assert i18n._normalize_lang("EN") == "en"


def test_normalize_lang_accepts_aliases():
    assert i18n._normalize_lang("Deutsch") == "de"
    assert i18n._normalize_lang("español") == "es"
    assert i18n._normalize_lang("Irish") != "ga"
    assert i18n._normalize_lang("Slovenian") == "sl"
    assert i18n._normalize_lang("sl-SI") == "sl"
    assert i18n._normalize_lang("Malti") == "mt"
    assert i18n._normalize_lang("Ελληνικά") == "el"
    assert i18n._normalize_lang("Hungarian") == "hu"
    assert i18n._normalize_lang("Magyar") == "hu"
    assert i18n._normalize_lang("ru-RU") == "ru"
    # The website's two English codes collapse onto the one English catalogue.
    assert i18n._normalize_lang("en-AU") == "en"
    assert i18n._normalize_lang("en-US") == "en"


@pytest.mark.parametrize("dropped", ["zh", "zh-hant", "ja", "ko", "tr", "uk", "af", "ga"])
def test_dropped_languages_are_not_offered(dropped: str):
    """Languages we do not sell into must not resolve to anything.

    Kept as a named test rather than deleted with the catalogues: if a stale
    config or a re-fork reintroduces one of these codes, the picker would offer
    a language the Brain cannot speak, and nobody would notice until a buyer
    hit it. normalize_language() returns None so a writer refuses the value.
    """
    assert dropped not in i18n.SUPPORTED_LANGUAGES
    assert i18n.normalize_language(dropped) is None


def test_normalize_lang_unknown_falls_back():
    assert i18n._normalize_lang("klingon") == "en"
    assert i18n._normalize_lang("") == "en"
    assert i18n._normalize_lang(None) == "en"


def test_env_var_override(monkeypatch):
    """CENTURION_LANGUAGE wins over config."""
    i18n.reset_language_cache()
    monkeypatch.setenv("CENTURION_LANGUAGE", "hu")
    assert i18n.get_language() == "hu"


def test_env_var_normalized(monkeypatch):
    i18n.reset_language_cache()
    monkeypatch.setenv("CENTURION_LANGUAGE", "Magyar")
    assert i18n.get_language() == "hu"


def test_default_when_nothing_set(monkeypatch):
    """With no env var and no config override, falls back to English."""
    monkeypatch.delenv("CENTURION_LANGUAGE", raising=False)
    # Force config lookup to return None -- patch the cached reader.
    i18n.reset_language_cache()
    monkeypatch.setattr(i18n, "_config_language_cached", lambda: None)
    assert i18n.get_language() == "en"


# ---------------------------------------------------------------------------
# t() semantics
# ---------------------------------------------------------------------------

def test_t_explicit_lang():
    assert i18n.t("approval.denied", lang="en").endswith("Denied")
    assert i18n.t("approval.denied", lang="de").endswith("Abgelehnt")
    assert i18n.t("approval.denied", lang="hu").endswith("Elutasítva")
    assert i18n.t("approval.denied", lang="sv").endswith("Nekat")


def test_t_formats_placeholders():
    msg = i18n.t("gateway.draining", lang="en", count=3)
    assert "3" in msg


def test_t_missing_key_returns_key():
    """A missing key returns its own path -- ugly but never crashes."""
    result = i18n.t("nonexistent.key.path", lang="en")
    assert result == "nonexistent.key.path"


def test_t_missing_key_in_non_english_falls_back_to_english(tmp_path, monkeypatch):
    """If a key exists in English but not in the target locale, fall back."""
    # Stand up a fake incomplete locale under a temp locales dir.
    fake_locales = tmp_path / "locales"
    fake_locales.mkdir()
    (fake_locales / "en.yaml").write_text("foo: English Foo\n", encoding="utf-8")
    (fake_locales / "nl.yaml").write_text("# intentionally empty\n", encoding="utf-8")
    monkeypatch.setattr(i18n, "_locales_dir", lambda: fake_locales)
    i18n.reset_language_cache()
    try:
        assert i18n.t("foo", lang="nl") == "English Foo"
    finally:
        # Clear the cache on teardown so subsequent tests don't see the
        # fake "foo: English Foo" catalog instead of the real locales/*.yaml.
        i18n.reset_language_cache()


def test_t_unknown_language_uses_english():
    """Unknown lang codes normalize to English, not to a key-path fallback."""
    assert i18n.t("approval.denied", lang="klingon") == i18n.t("approval.denied", lang="en")


# ---------------------------------------------------------------------------
# The two pickers -- Python and the web dashboard -- keep separate lists of
# languages, in separate files, edited by different hands.  A language added to
# one and forgotten in the other is invisible: the server rejects a value the
# picker offers, or the picker hides a language the Brain can speak.  Pin them
# to each other.
# ---------------------------------------------------------------------------

def test_web_locale_union_matches_supported_languages():
    """The dashboard's Locale union must list exactly SUPPORTED_LANGUAGES."""
    import re
    from pathlib import Path

    types_ts = Path(__file__).resolve().parents[2] / "web/src/i18n/types.ts"
    source = types_ts.read_text(encoding="utf-8")
    union = re.search(r"export type Locale =(.*?);", source, re.S)
    assert union, "could not find the Locale union in web/src/i18n/types.ts"
    web_locales = set(re.findall(r'"([a-z-]+)"', union.group(1)))
    assert web_locales == set(i18n.SUPPORTED_LANGUAGES), (
        f"web Locale union and SUPPORTED_LANGUAGES disagree: "
        f"web-only={sorted(web_locales - set(i18n.SUPPORTED_LANGUAGES))} "
        f"python-only={sorted(set(i18n.SUPPORTED_LANGUAGES) - web_locales)}"
    )


def test_web_catalog_exists_for_every_supported_language():
    """Every language the Brain speaks must have a dashboard catalogue."""
    from pathlib import Path

    web_i18n = Path(__file__).resolve().parents[2] / "web/src/i18n"
    missing = [
        lang for lang in i18n.SUPPORTED_LANGUAGES
        if not (web_i18n / f"{lang}.ts").is_file()
    ]
    assert not missing, f"missing web/src/i18n/*.ts catalogues for: {missing}"


def test_every_supported_language_has_an_endonym():
    """A code with no endonym shows up in the picker as nothing at all."""
    missing = [lang for lang in i18n.SUPPORTED_LANGUAGES if lang not in i18n.LANGUAGE_NAMES]
    assert not missing, f"missing LANGUAGE_NAMES entries for: {missing}"
