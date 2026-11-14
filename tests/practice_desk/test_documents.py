"""The Documents pane: provenance, aggregated from what the practice actually filed.

Two things are being proved here.

First, the derivation. A "library" pane that lists a folder is a lie in both
directions — it claims files nobody used and misses the ones that settled a
number. The citations carried by the drafts register are the only honest source,
so these tests pin the shapes a citation arrives in and the grouping the pane
renders.

Second, the invariant this desk is not allowed to break: a pane backed by a
register that does not exist reports `null` plus a reason, never `0`. A partner
acts on a number on that page; a confident zero over work nobody has started
reads as "nothing here" when it means "nobody has filed anything yet".
"""

from __future__ import annotations

import asyncio

import pytest
from aiohttp.test_utils import TestClient, TestServer

from centurion_cli.practice_desk import app as desk_app
from centurion_cli.practice_desk import store as st
from centurion_cli.practice_desk.documents import library_use, normalise_citation

from .authenticator import SoftwareAuthenticator

ORIGIN = "http://localhost:8765"
RP_ID = "localhost"


def run(coro):
    return asyncio.run(coro)


class FakeEdition:
    def __init__(self, seat_limit: int) -> None:
        self.seat_limit = seat_limit
        self.label = "Centurion Accountant Practice"

    def admits(self, named_users):
        try:
            return 0 <= int(named_users) <= self.seat_limit
        except (TypeError, ValueError):
            return False

    def refusal(self, named_users):
        if self.admits(named_users):
            return None
        return "This machine carries a fixed number of named users."


@pytest.fixture()
def settings(tmp_path, monkeypatch):
    import centurion.license.edition as edition_mod

    monkeypatch.setattr(edition_mod, "current_edition", lambda: FakeEdition(10))
    return desk_app.Settings(
        rp_id=RP_ID,
        origin=ORIGIN,
        host="127.0.0.1",
        port=8765,
        brain_url="",
        db_path=tmp_path / "practice.db",
        tls_cert=None,
    )


async def _client(settings) -> TestClient:
    app = desk_app.create_app(settings)
    client = TestClient(TestServer(app), headers={"Origin": ORIGIN})
    await client.start_server()
    return client


async def _sign_in(client) -> str:
    store: st.PracticeStore = client.server.app[desk_app.DESK_KEY].store
    person = store.admit_person(name="Ada Fenwick", email="ada@firm.test", role="partner")
    token = store.issue_invitation(person.id)

    begun = await (await client.post("/api/invite", json={"token": token})).json()
    challenge = desk_app.webauthn.b64url_decode(begun["options"]["challenge"])
    auth = SoftwareAuthenticator(rp_id=RP_ID)
    reg = auth.registration(challenge, origin=ORIGIN)
    payload = await (
        await client.post(
            "/api/register",
            json={
                "clientDataJSON": desk_app.webauthn.b64url_encode(reg["client_data_json"]),
                "attestationObject": desk_app.webauthn.b64url_encode(reg["attestation_object"]),
            },
        )
    ).json()
    assert payload["ok"] is True, payload
    return person.id


# ── the derivation ──────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "cite,path,line",
    [
        ("/lib/clients/ash.md:112", "/lib/clients/ash.md", 112),
        ("/lib/clients/ash.md, line 9", "/lib/clients/ash.md", 9),
        ("/lib/clients/ash.md (line 7)", "/lib/clients/ash.md", 7),
        ("  /lib/clients/ash.md  ", "/lib/clients/ash.md", None),
        ("/lib/house-style.md", "/lib/house-style.md", None),
        ("", "", None),
    ],
)
def test_a_citation_keeps_its_path_and_lifts_its_line(cite, path, line):
    parsed = normalise_citation(cite)
    assert parsed["path"] == path
    assert parsed["line"] == line


def test_the_same_file_cited_twice_is_one_document_with_two_lines():
    payload = library_use(
        [
            {
                "id": "d1",
                "client_slug": "ash-street",
                "created_at": "2026-11-01T09:00:00Z",
                "cites": ["/lib/ash.md:112", "/lib/ash.md:40", "/lib/style.md"],
                "unsettled": [],
            },
            {
                "id": "d2",
                "client_slug": "brook-house",
                "created_at": "2026-11-03T09:00:00Z",
                "cites": ["/lib/ash.md:112"],
                "unsettled": ["no deadline recorded"],
            },
        ]
    )
    assert payload["files"] == 2
    assert payload["citations"] == 4
    assert payload["drafts"] == 2
    assert payload["drafts_with_citations"] == 2
    assert payload["drafts_with_unsettled"] == 1

    first = payload["documents"][0]
    assert first["path"] == "/lib/ash.md"
    assert first["citations"] == 3
    assert first["lines"] == [40, 112]
    assert first["clients"] == ["ash-street", "brook-house"]
    # Newest citation wins the last_cited stamp.
    assert first["last_cited"] == "2026-11-03T09:00:00Z"
    assert sorted(first["draft_ids"]) == ["d1", "d2"]


def test_no_drafts_at_all_is_unmeasured_not_zero():
    payload = library_use([])
    assert payload["files"] == 0
    assert payload["unmeasured"] is not None
    assert "not measured" in payload["unmeasured"]
    assert "no draft" in payload["unmeasured"]


def test_drafts_without_citations_say_so_rather_than_showing_an_empty_library():
    payload = library_use(
        [{"id": "d1", "client_slug": None, "created_at": "2026-11-01", "cites": [], "unsettled": []}]
    )
    assert payload["documents"] == []
    assert payload["unmeasured"] is not None
    assert "cited a file" in payload["unmeasured"]


def test_a_draft_with_citations_is_measured_and_carries_no_excuse():
    payload = library_use(
        [{"id": "d1", "client_slug": "ash", "created_at": "2026-11-01", "cites": ["/a.md:1"], "unsettled": []}]
    )
    assert payload["unmeasured"] is None
    assert payload["files"] == 1


def test_a_malformed_row_does_not_break_the_pane():
    payload = library_use([{}, {"cites": ["   ", None]}, {"cites": "/not-a-list.md"}])
    # A bare string is one citation, not twelve one-character "files" — the
    # difference between a tidy row and a pane full of noise.
    assert payload["files"] == 1
    assert payload["documents"][0]["path"] == "/not-a-list.md"
    assert payload["documents"][0]["citations"] == 1


def test_rows_with_no_usable_citation_report_unmeasured_rather_than_zero_files():
    payload = library_use([{}, {"cites": ["   ", None]}, {"cites": 7}])
    assert payload["files"] == 0
    assert payload["unmeasured"] is not None


# ── the route ───────────────────────────────────────────────────────────────


def test_the_documents_route_returns_what_the_practice_cited(settings):
    async def scenario():
        client = await _client(settings)
        try:
            person_id = await _sign_in(client)
            store = client.server.app[desk_app.DESK_KEY].store
            person = store.get_person(person_id)
            store.create_draft(
                person=person,
                body="A letter.",
                client_slug=None,
                kind="letter",
                cites=["/lib/clients/ash.md:112", "/lib/house-style.md:9"],
                unsettled=["no deadline recorded"],
            )
            payload = await (await client.get("/api/documents")).json()
            assert payload["ok"] is True
            assert payload["files"] == 2
            assert payload["citations"] == 2
            assert payload["unmeasured"] is None
            assert payload["documents"][0]["path"].startswith("/lib/")
        finally:
            await client.close()

    run(scenario())


def test_the_documents_route_refuses_without_a_session(settings):
    async def scenario():
        client = await _client(settings)
        try:
            response = await client.get("/api/documents")
            assert response.status == 401
        finally:
            await client.close()

    run(scenario())


def test_a_failed_register_read_is_an_error_not_an_empty_library(settings, monkeypatch):
    """The failure the whole desk is built to avoid: a dead read rendered as zero."""

    async def scenario():
        client = await _client(settings)
        try:
            await _sign_in(client)
            store = client.server.app[desk_app.DESK_KEY].store

            def boom(*args, **kwargs):
                raise RuntimeError("database is locked")

            monkeypatch.setattr(store, "drafts", boom)
            response = await client.get("/api/documents")
            assert response.status == 500
            payload = await response.json()
            assert payload["ok"] is False
            assert "could not read" in payload["error"]
            # And specifically: no documents key pretending to be an empty list.
            assert "documents" not in payload
        finally:
            await client.close()

    run(scenario())


# ── the page ────────────────────────────────────────────────────────────────


def test_the_desk_offers_the_four_working_views():
    from pathlib import Path

    html = (
        Path(__file__).resolve().parents[2]
        / "centurion_cli"
        / "practice_desk"
        / "static"
        / "desk.html"
    ).read_text()
    for view in ("today", "work", "documents", "thread"):
        assert f'data-view="{view}"' in html, view
    # The chat is still there; it is no longer the front door.
    assert 'id="view-thread"' in html
    assert 'id="view-work"' in html
    assert 'id="view-documents"' in html
    # And the old "Save as draft" wording, which described a message, is gone.
    assert "Save as draft" not in html


def test_an_answer_s_citations_are_lifted_by_the_page_itself(tmp_path):
    """The work item must carry what the answer read.

    The lift runs in the browser, so it is the real script that is exercised —
    extracted verbatim and handed to node. Skipped, not silently passed, when
    node is absent.
    """
    import re
    import shutil
    import subprocess
    from pathlib import Path

    node = shutil.which("node")
    if not node:
        pytest.skip("node is not installed; the citation lift was not exercised")

    html = (
        Path(__file__).resolve().parents[2]
        / "centurion_cli"
        / "practice_desk"
        / "static"
        / "desk.html"
    ).read_text()
    block = re.search(r"<script(?![^>]*src=)[^>]*>(.*?)</script>", html, re.S).group(1)
    start = block.index("const CITE_RE")
    end = block.index("function renderMessages()")
    script = tmp_path / "cites.mjs"
    script.write_text(
        block[start:end]
        + """
const answer = [
  "I read /lib/clients/ash.md:112 and /lib/clients/ash.md line 118,",
  "plus /lib/house-style.md.",
  "",
  "Could not settle: no election deadline recorded.",
].join(String.fromCharCode(10));
console.log(JSON.stringify({
  cites: citesFrom(answer),
  unsettled: unsettledFrom(answer),
  none: citesFrom("nothing to cite here"),
}));
"""
    )
    result = subprocess.run([node, str(script)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr[:800]
    import json as _json

    out = _json.loads(result.stdout)
    assert out["cites"] == [
        "/lib/clients/ash.md:112",
        "/lib/clients/ash.md:118",
        "/lib/house-style.md",
    ]
    assert out["unsettled"] == ["no election deadline recorded"]
    assert out["none"] == []
