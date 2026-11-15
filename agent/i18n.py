"""Lightweight internationalization (i18n) for Centurion static user-facing messages.

Scope (thin slice, by design): only the highest-impact static strings shown
to the user by Centurion itself -- approval prompts, a handful of gateway slash
command replies, restart-drain notices.  Agent-generated output, log lines,
error tracebacks, tool outputs, and slash-command descriptions all stay in
English.

Catalog files live under ``agent/locales/<lang>.yaml`` -- inside the package,
so a wheel ships them with the code that reads them.  Each
catalog is a flat dict keyed by dotted paths (e.g. ``approval.choose`` or
``gateway.approval_expired``).  Missing keys fall back to English; if English
is missing too, the key path itself is returned so a broken catalog never
crashes the agent.

Usage::

    from agent.i18n import t
    print(t("approval.choose_long"))                       # current lang
    print(t("gateway.draining", count=3))                  # {count} formatted
    print(t("approval.choose_long", lang="de"))            # explicit override

Language resolution order:
    1. Explicit ``lang=`` argument passed to :func:`t`
    2. ``CENTURION_LANGUAGE`` environment variable (for tests / quick override)
    3. ``display.language`` from config.yaml
    4. ``"en"`` (baseline)

Supported languages live in :data:`SUPPORTED_LANGUAGES` -- a catalogue file
``agent/locales/<lang>.yaml`` must exist for every code in that tuple, and
``tests/agent/test_i18n.py`` asserts full key parity with English.  Unknown
values fall back to en.
"""

from __future__ import annotations

import logging
import os
import threading
from functools import lru_cache
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

# The markets Centurion sells into: every official language of the European
# Union except Irish, plus Russian. Irish is out because the Irish market is
# served in English and a catalogue nobody reads is maintenance, not coverage.
#
# Codes are the ones the website publishes pages for; en-AU/en-US resolve to
# "en" through the alias table rather than shipping a duplicate catalogue.
SUPPORTED_LANGUAGES: tuple[str, ...] = (
    "en", "fr", "de", "nl", "pl", "es", "it", "pt", "ru", "hu",
    "bg", "cs", "da", "el", "et", "fi", "hr", "lt", "lv", "mt", "ro", "sk", "sl", "sv",
)
DEFAULT_LANGUAGE = "en"

# Endonyms, because a language is not a country and a French buyer should not
# have to recognise "French" to find his own. These are never shown as flags.
LANGUAGE_NAMES: dict[str, str] = {
    "en": "English",
    "fr": "Français",
    "de": "Deutsch",
    "nl": "Nederlands",
    "pl": "Polski",
    "es": "Español",
    "it": "Italiano",
    "pt": "Português",
    "ru": "Русский",
    "hu": "Magyar",
    "bg": "Български",
    "cs": "Čeština",
    "da": "Dansk",
    "el": "Ελληνικά",
    "et": "Eesti",
    "fi": "Suomi",
    "hr": "Hrvatski",
    "lt": "Lietuvių",
    "lv": "Latviešu",
    "mt": "Malti",
    "ro": "Română",
    "sk": "Slovenčina",
    "sl": "Slovenščina",
    "sv": "Svenska",
}


def normalize_language(value: Any) -> "str | None":
    """Strict public normaliser: the code, or None if we do not ship that language.

    ``_normalize_lang`` falls back to English because a *reader* of an unknown
    value should still get a usable string. A *writer* is a different question:
    silently turning whatever somebody typed into English is how a French user
    ends up with an English interface and no error to explain it. Callers that
    persist a setting use this and refuse the value instead.
    """
    if not isinstance(value, str):
        return None
    key = value.strip().lower()
    if not key:
        return None
    if key in SUPPORTED_LANGUAGES:
        return key
    if key in _LANGUAGE_ALIASES:
        return _LANGUAGE_ALIASES[key]
    base = key.split("-", 1)[0]
    if base in SUPPORTED_LANGUAGES:
        return base
    return None


def language_name(code: str | None = None) -> str:
    """Return the endonym for a language code, resolving aliases first.

    Used where a person has to recognise their own language in a list, and where
    the agent has to be told what language it is being asked to speak.
    """
    resolved = _normalize_lang(code) if code else get_language()
    return LANGUAGE_NAMES.get(resolved, LANGUAGE_NAMES[DEFAULT_LANGUAGE])


# Accept a few natural aliases so a user who types "Deutsch" or "es-ES" gets
# the right catalog instead of silently falling back to English.
#
# Codes for languages we no longer ship (zh, zh-hant, ja, ko, tr, uk, af) are
# deliberately absent rather than kept as dead routes: an alias pointing at a
# code with no catalogue would normalise to something unsupported, and
# normalize_language() would then hand back a language we cannot speak. Absent
# names fall through to English cleanly, and a persisted setting of one of those
# codes is rejected on write instead of being silently accepted.
_LANGUAGE_ALIASES: dict[str, str] = {
    "english": "en", "en-us": "en", "en-gb": "en", "en-au": "en", "en-ie": "en",
    "german": "de", "deutsch": "de", "de-de": "de", "de-at": "de", "de-ch": "de",
    "spanish": "es", "español": "es", "espanol": "es", "es-es": "es", "es-mx": "es", "es-ar": "es",
    "french": "fr", "français": "fr", "france": "fr", "fr-fr": "fr", "fr-be": "fr", "fr-ca": "fr", "fr-ch": "fr",
    # Dutch — the Netherlands and Belgium (Flemish is the same written
    # language; "vlaams" routes here rather than to a catalogue we do not have).
    "dutch": "nl", "nederlands": "nl", "nl-nl": "nl", "nl-be": "nl",
    "flemish": "nl", "vlaams": "nl",
    # Polish — the newest Central European market we sell into.
    "polish": "pl", "polski": "pl", "pl-pl": "pl",
    # Italian
    "italian": "it", "italiano": "it", "it-it": "it", "it-ch": "it",
    "portuguese": "pt", "português": "pt", "portugues": "pt",
    "pt-pt": "pt", "pt-br": "pt", "brazilian": "pt", "brasileiro": "pt",
    # Russian
    "russian": "ru", "русский": "ru", "ru-ru": "ru",
    # Hungarian
    "hungarian": "hu", "magyar": "hu", "hu-hu": "hu",
    # The rest of the European Union, in the order the picker lists them.
    "bulgarian": "bg", "български": "bg", "bg-bg": "bg",
    "czech": "cs", "čeština": "cs", "cestina": "cs", "cs-cz": "cs",
    "danish": "da", "dansk": "da", "da-dk": "da",
    "greek": "el", "ελληνικά": "el", "ellinika": "el", "el-gr": "el",
    "estonian": "et", "eesti": "et", "et-ee": "et",
    "finnish": "fi", "suomi": "fi", "fi-fi": "fi",
    "croatian": "hr", "hrvatski": "hr", "hr-hr": "hr",
    "lithuanian": "lt", "lietuvių": "lt", "lietuviu": "lt", "lt-lt": "lt",
    "latvian": "lv", "latviešu": "lv", "latviesu": "lv", "lv-lv": "lv",
    "maltese": "mt", "malti": "mt", "mt-mt": "mt",
    "romanian": "ro", "română": "ro", "romana": "ro", "ro-ro": "ro",
    "slovak": "sk", "slovenčina": "sk", "slovencina": "sk", "sk-sk": "sk",
    "slovene": "sl", "slovenian": "sl", "slovenščina": "sl", "sl-si": "sl",
    "swedish": "sv", "svenska": "sv", "sv-se": "sv",
}

_catalog_cache: dict[str, dict[str, str]] = {}
_catalog_lock = threading.Lock()


def _locales_dir() -> Path:
    """Return the directory containing locale YAML files.

    Lives *inside* the ``agent`` package on purpose. It used to sit at the repo
    root, which works from a checkout and from the RPM (both ship the whole
    source tree) but not from a wheel: root-level directories are not package
    data, so ``pip install`` produced an ``agent/i18n.py`` with no catalogs
    beside it. Nothing crashed -- :func:`t` fell back to English and the
    installed Brain quietly believed it was translated.
    """
    return Path(__file__).resolve().parent / "locales"


def _normalize_lang(value: Any) -> str:
    """Normalize a user-supplied language value to a supported code.

    Delegates to :func:`normalize_language` and supplies the English fallback,
    so the alias table is read in exactly one place. Two copies of a mapping is
    how a code gets accepted on write and rejected on read.
    """
    return normalize_language(value) or DEFAULT_LANGUAGE


def _load_catalog(lang: str) -> dict[str, str]:
    """Load and flatten one locale YAML file into a dotted-key dict.

    YAML files can be nested for human readability; this produces the flat
    key space :func:`t` expects.  Cached per-language for the process.
    """
    with _catalog_lock:
        cached = _catalog_cache.get(lang)
        if cached is not None:
            return cached

    path = _locales_dir() / f"{lang}.yaml"
    if not path.is_file():
        logger.debug("i18n catalog missing for %s at %s", lang, path)
        with _catalog_lock:
            _catalog_cache[lang] = {}
        return {}

    try:
        import yaml  # PyYAML is already a centurion dependency
        with path.open("r", encoding="utf-8") as f:
            raw = yaml.safe_load(f) or {}
    except Exception as exc:
        logger.warning("Failed to load i18n catalog %s: %s", path, exc)
        with _catalog_lock:
            _catalog_cache[lang] = {}
        return {}

    flat: dict[str, str] = {}
    _flatten_into(raw, "", flat)
    with _catalog_lock:
        _catalog_cache[lang] = flat
    return flat


def _flatten_into(node: Any, prefix: str, out: dict[str, str]) -> None:
    if isinstance(node, dict):
        for key, value in node.items():
            child_key = f"{prefix}.{key}" if prefix else str(key)
            _flatten_into(value, child_key, out)
    elif isinstance(node, str):
        out[prefix] = node
    # Non-string, non-dict leaves are ignored -- catalogs are text-only.


@lru_cache(maxsize=1)
def _config_language_cached() -> str | None:
    """Read ``display.language`` from config.yaml once per process.

    Cached because ``t()`` is called in hot paths (every approval prompt,
    every gateway reply) and re-reading YAML each call would be wasteful.
    ``reset_language_cache()`` clears this when config changes at runtime
    (e.g. after the setup wizard).
    """
    try:
        from centurion_cli.config import load_config
        cfg = load_config()
        lang = (cfg.get("display") or {}).get("language")
        if lang:
            return _normalize_lang(lang)
    except Exception as exc:
        logger.debug("Could not read display.language from config: %s", exc)
    return None


def reset_language_cache() -> None:
    """Invalidate cached language resolution and catalogs.

    Call after :func:`centurion_cli.config.save_config` if a running process
    needs to pick up a changed ``display.language`` without restart.
    """
    _config_language_cached.cache_clear()
    with _catalog_lock:
        _catalog_cache.clear()


def get_language() -> str:
    """Resolve the active language using env > config > default order."""
    env_lang = os.environ.get("CENTURION_LANGUAGE")
    if env_lang:
        return _normalize_lang(env_lang)
    cfg_lang = _config_language_cached()
    if cfg_lang:
        return cfg_lang
    return DEFAULT_LANGUAGE


def t(key: str, lang: str | None = None, **format_kwargs: Any) -> str:
    """Translate a dotted key to the active language.

    Parameters
    ----------
    key
        Dotted path into the catalog, e.g. ``"approval.choose_long"``.
    lang
        Explicit language override.  Takes precedence over env + config.
    **format_kwargs
        ``str.format`` substitution arguments (``t("gateway.drain", count=3)``
        expects a catalog entry with a ``{count}`` placeholder).

    Returns
    -------
    The translated string, or the English fallback if the key is missing in
    the target language, or the bare key if English is also missing.
    """
    target = _normalize_lang(lang) if lang else get_language()
    catalog = _load_catalog(target)
    value = catalog.get(key)

    if value is None and target != DEFAULT_LANGUAGE:
        # Fall through to English rather than showing a key path to the user.
        value = _load_catalog(DEFAULT_LANGUAGE).get(key)

    if value is None:
        # Last-ditch: return the key itself.  A broken catalog should not
        # crash anything; it just looks ugly until someone fixes it.
        logger.debug("i18n miss: key=%r lang=%r", key, target)
        value = key

    if format_kwargs:
        try:
            return value.format(**format_kwargs)
        except (KeyError, IndexError, ValueError) as exc:
            logger.warning(
                "i18n format failed for key=%r lang=%r kwargs=%r: %s",
                key, target, format_kwargs, exc,
            )
            return value
    return value


__all__ = [
    "SUPPORTED_LANGUAGES",
    "DEFAULT_LANGUAGE",
    "t",
    "get_language",
    "reset_language_cache",
]
