"""Tests for the packaged-Brain release channel update check.

The bug this guards: a Brain installed from a Get Brain download was detected as
a `pip` install, so the update check asked PyPI about a Python package, failed,
and told the customer to open a Terminal:

    Could not reach PyPI to check for updates.
      Use: uv pip install --upgrade 'centurionai-os'

The app only lights its update badge on `update_available` or `up_to_date`, so
the failure was invisible.
"""

from __future__ import annotations

import pathlib

import pytest

from centurion_cli import brain_release as br
from centurion_cli.config import (
    detect_install_method,
    is_brain_install,
    recommended_update_command_for_method,
)


# --- version comparison ---------------------------------------------------

@pytest.mark.parametrize(
    "lower,higher",
    [
        ("6.0.6", "6.0.7"),
        ("6.0.7", "7.0.0"),
        ("5.9.9", "6.0.0"),
        ("6.0.7", "6.0.10"),  # numeric, not lexicographic
    ],
)
def test_version_key_orders_numerically(lower, higher):
    assert br._version_key(lower) < br._version_key(higher)


def test_version_key_tolerates_junk():
    # A malformed version must not make the update check throw.
    assert br._version_key("6.0.7") == (6, 0, 7)
    assert br._version_key("") == (0,)
    assert br._version_key("garbage") == (0,)
    assert br._version_key("6.0.7-rc1") == (6, 0, 7)


# --- the packaging release must not masquerade as a version -------------------

@pytest.mark.parametrize(
    "published,expected",
    [
        ("7.0.0-5", "7.0.0"),      # RPM Release suffix — packaging, not a version
        ("7.0.1-1", "7.0.1"),
        ("7.0.0", "7.0.0"),         # already clean
        ("6.0.7-rc1", "6.0.7-rc1"),  # a non-numeric suffix IS part of the version
    ],
)
def test_release_version_strips_only_the_packaging_release(published, expected):
    assert br._release_version(published) == expected


def test_newest_build_is_not_told_to_update_to_itself(monkeypatch):
    """The live defect, 28 Sep 2026.

    The installed ``__version__`` was ``7.0.0`` while the channel served ``7.0.0-5``. The
    old comparison tupled the packaging release in — ``(7,0,0,5) > (7,0,0)`` — so every
    Brain running the newest build was offered an update to the build it was already on.
    """
    monkeypatch.setattr(br, "fetch_latest_release", lambda *a, **k: {"version": "7.0.0-5"})
    out = br.check_brain_release("7.0.0")
    assert out["status"] == br.STATUS_UP_TO_DATE
    assert out["latest_version"] == "7.0.0"


def test_a_real_new_version_is_offered_without_the_packaging_suffix(monkeypatch):
    monkeypatch.setattr(br, "fetch_latest_release", lambda *a, **k: {"version": "7.0.1-1"})
    out = br.check_brain_release("7.0.0")
    assert out["status"] == br.STATUS_UPDATE_AVAILABLE
    assert out["latest_version"] == "7.0.1"
    assert "7.0.1" in out["message"]
    assert "7.0.1-1" not in out["message"]


def test_a_republished_same_version_is_up_to_date(monkeypatch):
    """Publishing 7.0.0-6 for 7.0.0-5 is a packaging revision of one build.

    The owner's rule makes this unreachable in practice — the third digit moves every
    release, and the publisher refuses a duplicate version — but the client must not
    invent an update if it ever happens.
    """
    monkeypatch.setattr(br, "fetch_latest_release", lambda *a, **k: {"version": "7.0.0-6"})
    assert br.check_brain_release("7.0.0")["status"] == br.STATUS_UP_TO_DATE


# --- the check itself -----------------------------------------------------

def test_up_to_date(monkeypatch):
    monkeypatch.setattr(br, "fetch_latest_release", lambda *a, **k: {"version": "6.0.7"})
    out = br.check_brain_release("6.0.7")
    assert out["status"] == br.STATUS_UP_TO_DATE
    assert out["latest_version"] == "6.0.7"


def test_update_available(monkeypatch):
    monkeypatch.setattr(br, "fetch_latest_release", lambda *a, **k: {"version": "6.0.7"})
    out = br.check_brain_release("6.0.6")
    assert out["status"] == br.STATUS_UPDATE_AVAILABLE
    assert out["latest_version"] == "6.0.7"
    assert "6.0.7" in out["message"]


def test_newer_installed_than_published_is_not_an_update(monkeypatch):
    # A dev build ahead of the channel must not report an update.
    monkeypatch.setattr(br, "fetch_latest_release", lambda *a, **k: {"version": "6.0.7"})
    assert br.check_brain_release("6.0.8")["status"] == br.STATUS_UP_TO_DATE


def test_unreachable_channel_reports_unavailable(monkeypatch):
    monkeypatch.setattr(br, "fetch_latest_release", lambda *a, **k: None)
    out = br.check_brain_release("6.0.7")
    assert out["status"] == br.STATUS_UNAVAILABLE
    assert out["latest_version"] is None
    # Must not blame PyPI, and must not suggest a terminal command.
    assert "PyPI" not in out["message"]
    assert "pip" not in out["message"]


class _FakeResponse:
    def __init__(self, body: bytes):
        self._body = body

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def read(self) -> bytes:
        return self._body


def test_fetch_rejects_payload_without_a_version(monkeypatch):
    monkeypatch.setattr(
        br.urllib.request,
        "urlopen",
        lambda *a, **k: _FakeResponse(b'{"ok": true, "release": {"title": "no version"}}'),
    )
    assert br.fetch_latest_release() is None


def test_fetch_rejects_non_json(monkeypatch):
    monkeypatch.setattr(
        br.urllib.request, "urlopen", lambda *a, **k: _FakeResponse(b"<html>not json</html>")
    )
    assert br.fetch_latest_release() is None


def test_fetch_reads_a_good_payload(monkeypatch):
    monkeypatch.setattr(
        br.urllib.request,
        "urlopen",
        lambda *a, **k: _FakeResponse(b'{"ok": true, "release": {"version": "6.0.7"}}'),
    )
    release = br.fetch_latest_release()
    assert release is not None and release["version"] == "6.0.7"


# --- install detection ----------------------------------------------------

def test_brain_install_detected_for_packaged_root():
    assert is_brain_install(pathlib.Path("/usr/lib/centurion/Centurion-AI-OS")) is True


def test_brain_install_not_claimed_for_an_ordinary_path(tmp_path, monkeypatch):
    monkeypatch.setattr(
        "centurion_cli.config.get_centurion_home", lambda: tmp_path / "no-such-home"
    )
    assert is_brain_install(tmp_path) is False


def test_git_checkout_is_not_detected_as_brain(tmp_path, monkeypatch):
    # A developer's checkout must keep the git path.
    (tmp_path / ".git").mkdir()
    monkeypatch.setattr(
        "centurion_cli.config.get_centurion_home", lambda: tmp_path / "no-such-home"
    )
    assert detect_install_method(tmp_path) == "git"


def test_brain_method_has_no_terminal_command():
    assert recommended_update_command_for_method("brain") == ""
