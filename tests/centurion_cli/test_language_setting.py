"""Choosing a language has to mean something.

The dashboard carried a language picker that wrote one value to browser
localStorage and stopped: nothing ever wrote `display.language`, so the Python
side never learned the choice, and the agent had no idea what language to speak.
Closing the tab forgot the setting; opening the Brain showed English.

These tests hold the two halves together — the value is persisted where the
agent can read it, and an unknown value is refused rather than silently
becoming English (a person left with an English machine and no error has no way
to tell a bug from their own mistake).
"""

from __future__ import annotations

import pytest


@pytest.fixture
def brain_home(tmp_path, monkeypatch):
    (tmp_path / "state").mkdir()
    (tmp_path / "config.yaml").write_text(
        "display:\n  language: en\n", encoding="utf-8"
    )
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path))
    monkeypatch.delenv("CENTURION_LANGUAGE", raising=False)

    from agent import i18n

    i18n.reset_language_cache()
    yield tmp_path
    i18n.reset_language_cache()


@pytest.fixture
def client(brain_home):
    fastapi_testclient = pytest.importorskip("fastapi.testclient")
    from centurion_cli import web_server

    # Every /api/ route is behind the ephemeral session token; a test that
    # forgets the header measures the auth middleware, not the endpoint.
    headers = {web_server._SESSION_HEADER_NAME: web_server._SESSION_TOKEN}
    return fastapi_testclient.TestClient(web_server.app, headers=headers)


def test_setting_a_language_persists_it_where_the_agent_reads_it(client, brain_home):
    resp = client.put("/api/language", json={"language": "fr"})
    assert resp.status_code == 200
    assert resp.json() == {"ok": True, "language": "fr", "name": "Français"}

    # The file the agent reads at boot, not just a variable in memory.
    assert "language: fr" in (brain_home / "config.yaml").read_text(encoding="utf-8")

    from agent.i18n import get_language

    assert get_language() == "fr"

    # And it survives a fresh read of the config (a restart, in effect).
    from agent.i18n import reset_language_cache

    reset_language_cache()
    assert get_language() == "fr"


def test_the_agent_then_speaks_it(client):
    client.put("/api/language", json={"language": "de"})
    from agent.prompt_builder import build_language_lock

    assert "Deutsch" in build_language_lock()


def test_an_alias_is_normalised_before_it_is_stored(client, brain_home):
    assert client.put("/api/language", json={"language": "Français"}).json()["language"] == "fr"
    assert "language: fr" in (brain_home / "config.yaml").read_text(encoding="utf-8")


def test_an_unknown_language_is_refused_not_silently_english(client, brain_home):
    resp = client.put("/api/language", json={"language": "klingon"})
    assert resp.status_code == 400
    assert "klingon" in resp.json()["detail"]
    # Nothing was written: a refused setting must not leave a half-state behind.
    assert "language: en" in (brain_home / "config.yaml").read_text(encoding="utf-8")


def test_the_endpoint_lists_what_the_brain_can_actually_speak(client):
    """The picker's options come from the agent, not a hand-kept copy in React."""
    body = client.get("/api/language").json()
    codes = [entry["code"] for entry in body["supported"]]
    from agent.i18n import SUPPORTED_LANGUAGES

    assert codes == list(SUPPORTED_LANGUAGES)
    assert all(entry["name"] for entry in body["supported"])


def test_english_is_a_real_setting_and_clears_the_directive(client):
    client.put("/api/language", json={"language": "fr"})
    client.put("/api/language", json={"language": "en"})
    from agent.prompt_builder import build_language_lock

    assert build_language_lock() == ""
