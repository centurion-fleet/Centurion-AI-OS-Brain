"""The i18n catalogs must travel with the code that reads them.

Until 7.1.0 the catalogs sat at ``locales/`` in the repo root. That works from a
checkout and from the RPM, both of which ship the whole source tree -- and it
fails from a wheel, because a root-level directory is not package data. The
failure is silent by design: ``agent.i18n.t()`` catches a missing catalog and
falls back to English, so a pip-installed Brain would have answered every
French user in English while every test stayed green.

So: assert the catalogs are inside a package, assert that package declares them
as package data, and assert a file exists for every language the code claims to
support. Cheap assertions over pyproject.toml -- the same shape as
``test_wheel_packages.py``, for the same reason: the version of this test that
builds a real wheel takes a minute and gets skipped.
"""

from __future__ import annotations

import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG_DIR = ROOT / "agent" / "locales"


def _package_data() -> dict[str, list[str]]:
    cfg = tomllib.loads((ROOT / "pyproject.toml").read_text())
    return {
        k: list(v) for k, v in cfg["tool"]["setuptools"].get("package-data", {}).items()
    }


def test_catalogs_live_inside_a_package():
    """Root-level data is invisible to a wheel build."""
    assert CATALOG_DIR.is_dir(), (
        "agent/locales/ is missing -- the catalogs must live inside the agent "
        "package, not at the repo root, or wheels ship without them"
    )
    assert not (ROOT / "locales").is_dir(), (
        "a repo-root locales/ directory should not exist; the catalogs moved "
        "into agent/locales/ in 7.1.0"
    )


def test_the_agent_package_declares_the_catalogs_as_package_data():
    data = _package_data().get("agent", [])
    assert any("locales" in pattern for pattern in data), (
        "pyproject.toml [tool.setuptools.package-data] has no `agent` entry "
        "covering locales -- `pip install` would drop every catalog"
    )


def test_every_supported_language_has_a_catalog_in_the_package():
    from agent import i18n  # noqa: PLC0415

    missing = [
        lang for lang in i18n.SUPPORTED_LANGUAGES
        if not (CATALOG_DIR / f"{lang}.yaml").is_file()
    ]
    assert not missing, f"no catalog shipped for: {missing}"


def test_the_loader_resolves_to_the_packaged_directory():
    """The path the code computes must be the path that ships."""
    from agent import i18n  # noqa: PLC0415

    assert Path(i18n._locales_dir()).resolve() == CATALOG_DIR.resolve()
