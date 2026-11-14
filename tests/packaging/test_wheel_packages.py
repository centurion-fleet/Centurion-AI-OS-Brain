"""The wheel must actually contain the packages the CLI imports.

`[tool.setuptools.packages.find] include` is a list of patterns, and
`"centurion_cli"` matches only that package — not `centurion_cli.practice_desk`,
`centurion_cli.proxy` or `centurion_cli.adrian`. Those subpackages sit in the repo
and are importable from a checkout, so every test passes; then `pip install`
leaves them out of site-packages and the installed CLI cannot import them.

Found on 14 Nov 2026 building 7.0.12: the RPM shipped a `centurion practice-desk`
subcommand whose module was not in the venv at all — the release's headline
feature was unreachable on a customer's machine, with a green test suite.

The first assertion needs no third-party import (it reads pyproject.toml). The
second proves discovery for real when setuptools is available; a skip is honest,
a green test that never ran is not.
"""

from __future__ import annotations

import tomllib
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SUBPACKAGES = (
    "centurion_cli.practice_desk",
    "centurion_cli.proxy",
    "centurion_cli.adrian",
)


def _include_patterns() -> list[str]:
    cfg = tomllib.loads((ROOT / "pyproject.toml").read_text())
    return cfg["tool"]["setuptools"]["packages"]["find"]["include"]


def test_the_include_list_covers_centurion_cli_subpackages():
    patterns = _include_patterns()
    assert "centurion_cli" in patterns
    assert "centurion_cli.*" in patterns, (
        "`centurion_cli` alone does not match its subpackages — a subcommand in "
        "centurion_cli/<name>/ will be missing from the installed wheel."
    )


def test_setuptools_discovers_the_subpackages():
    setuptools = pytest.importorskip("setuptools", reason="setuptools not installed here")
    from setuptools import find_packages  # noqa: PLC0415

    found = set(find_packages(where=str(ROOT), include=_include_patterns()))
    missing = [p for p in SUBPACKAGES if p not in found]
    assert not missing, f"setuptools would not ship these packages: {missing}"
