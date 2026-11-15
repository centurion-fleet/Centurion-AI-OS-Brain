"""Gate 0 of the interface programme — the client's own surface.

A web client that is the product, rather than a window onto somebody else's
product, needs three things from the Brain that a messenger never asked for:
its conversations can be reopened, it is served by the Brain itself, and it is
told what the contract is. These tests hold that surface still.
"""

from __future__ import annotations

import json

import pytest
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

from centurion_state import SessionDB
from gateway.config import PlatformConfig
from gateway.platforms.api_server import APIServerAdapter


def _make_adapter(api_key: str = "sk-secret") -> APIServerAdapter:
    extra = {"key": api_key} if api_key else {}
    return APIServerAdapter(PlatformConfig(enabled=True, extra=extra))


def _create_app(adapter: APIServerAdapter) -> web.Application:
    app = web.Application()
    app["api_server_adapter"] = adapter
    app.router.add_get("/v1/capabilities", adapter._handle_capabilities)
    app.router.add_get("/api/threads", adapter._handle_threads)
    app.router.add_get("/api/threads/{session_id}", adapter._handle_thread)
    app.router.add_get("/desk", adapter._handle_desk_static)
    app.router.add_get("/desk/{path:.*}", adapter._handle_desk_static)
    return app


@pytest.fixture
def db(tmp_path):
    store = SessionDB(tmp_path / "sessions.db")
    store.create_session("sess-abc", source="desk")
    store.set_session_title("sess-abc", "Webinar plan")
    store.append_message("sess-abc", "user", "Design the webinar series")
    store.append_message("sess-abc", "assistant", "Three chapters, one deck each.")
    yield store
    store.close()


@pytest.fixture
def adapter(db, monkeypatch):
    made = _make_adapter()
    monkeypatch.setattr(made, "_ensure_session_db", lambda: db)
    return made


AUTH = {"Authorization": "Bearer sk-secret"}


class TestThreads:
    @pytest.mark.asyncio
    async def test_a_client_can_list_what_it_could_reopen(self, adapter):
        async with TestClient(TestServer(_create_app(adapter))) as client:
            response = await client.get("/api/threads", headers=AUTH)
            assert response.status == 200
            body = await response.json()
        assert body["object"] == "list"
        ids = [t["id"] for t in body["threads"]]
        assert "sess-abc" in ids
        thread = next(t for t in body["threads"] if t["id"] == "sess-abc")
        assert thread["title"] == "Webinar plan"
        assert thread["size_of_conversation"] >= 2

    @pytest.mark.asyncio
    async def test_a_thread_with_no_title_still_has_a_name(self, adapter, db):
        db.create_session("sess-untitled", source="desk")
        db.append_message("sess-untitled", "user", "What is the state of the practice box?")
        async with TestClient(TestServer(_create_app(adapter))) as client:
            body = await (await client.get("/api/threads", headers=AUTH)).json()
        thread = next(t for t in body["threads"] if t["id"] == "sess-untitled")
        assert thread["title"]
        assert thread["title"] != "None"

    @pytest.mark.asyncio
    async def test_the_transcript_reads_in_order(self, adapter):
        async with TestClient(TestServer(_create_app(adapter))) as client:
            response = await client.get("/api/threads/sess-abc", headers=AUTH)
            assert response.status == 200
            body = await response.json()
        roles = [m["role"] for m in body["messages"]]
        assert roles == ["user", "assistant"]
        assert body["messages"][0]["content"] == "Design the webinar series"
        assert body["title"] == "Webinar plan"
        assert body["truncated"] is False

    @pytest.mark.asyncio
    async def test_a_prefix_from_a_link_still_lands(self, adapter):
        async with TestClient(TestServer(_create_app(adapter))) as client:
            response = await client.get("/api/threads/sess", headers=AUTH)
            assert response.status == 200
            assert (await response.json())["id"] == "sess-abc"

    @pytest.mark.asyncio
    async def test_an_unknown_thread_is_a_404_not_an_empty_chat(self, adapter):
        async with TestClient(TestServer(_create_app(adapter))) as client:
            response = await client.get("/api/threads/nope", headers=AUTH)
            assert response.status == 404
            assert (await response.json())["error"]["code"] == "thread_not_found"

    @pytest.mark.asyncio
    async def test_a_huge_tool_dump_is_cut_and_says_so(self, adapter, db):
        db.append_message("sess-abc", "tool", "x" * 9000)
        async with TestClient(TestServer(_create_app(adapter))) as client:
            body = await (await client.get("/api/threads/sess-abc", headers=AUTH)).json()
        last = body["messages"][-1]
        assert len(last["content"]) == 4000
        assert last["truncated"] is True

    @pytest.mark.asyncio
    async def test_threads_are_not_readable_without_the_key(self, adapter):
        async with TestClient(TestServer(_create_app(adapter))) as client:
            assert (await client.get("/api/threads")).status == 401
            assert (await client.get("/api/threads/sess-abc")).status == 401


class TestClientServedByTheBrain:
    @pytest.mark.asyncio
    async def test_a_brain_with_no_client_says_so_plainly(self, adapter, tmp_path, monkeypatch):
        monkeypatch.setenv("CENTURION_WEB_CLIENT_DIR", str(tmp_path / "nowhere"))
        async with TestClient(TestServer(_create_app(adapter))) as client:
            response = await client.get("/desk")
            assert response.status == 503
            assert (await response.json())["error"]["code"] == "client_not_built"

    @pytest.mark.asyncio
    async def test_the_client_is_served_from_this_machine(self, adapter, tmp_path, monkeypatch):
        root = tmp_path / "client"
        root.mkdir()
        (root / "index.html").write_text("<html>the desk</html>")
        monkeypatch.setenv("CENTURION_WEB_CLIENT_DIR", str(root))
        async with TestClient(TestServer(_create_app(adapter))) as client:
            response = await client.get("/desk")
            assert response.status == 200
            assert "the desk" in await response.text()

    @pytest.mark.asyncio
    async def test_a_client_route_gets_the_client_not_a_404(self, adapter, tmp_path, monkeypatch):
        """A single-page client owns its own URLs; a refresh must not break it."""
        root = tmp_path / "client"
        root.mkdir()
        (root / "index.html").write_text("<html>the desk</html>")
        monkeypatch.setenv("CENTURION_WEB_CLIENT_DIR", str(root))
        async with TestClient(TestServer(_create_app(adapter))) as client:
            response = await client.get("/desk/thread/abc")
            assert response.status == 200
            assert "the desk" in await response.text()

    @pytest.mark.asyncio
    async def test_climbing_out_of_the_client_directory_is_refused(self, adapter, tmp_path, monkeypatch):
        root = tmp_path / "client"
        root.mkdir()
        (root / "index.html").write_text("<html>the desk</html>")
        (tmp_path / "secret.txt").write_text("not yours")
        monkeypatch.setenv("CENTURION_WEB_CLIENT_DIR", str(root))
        async with TestClient(TestServer(_create_app(adapter))) as client:
            response = await client.get("/desk/../secret.txt")
            assert response.status in (400, 404)
            assert "not yours" not in await response.text()


class TestTheContractIsDeclared:
    @pytest.mark.asyncio
    async def test_capabilities_advertise_the_client_surface(self, adapter):
        async with TestClient(TestServer(_create_app(adapter))) as client:
            body = await (await client.get("/v1/capabilities", headers=AUTH)).json()
        endpoints = body["endpoints"]
        assert endpoints["threads"]["path"] == "/api/threads"
        assert endpoints["thread"]["path"] == "/api/threads/{session_id}"
        assert endpoints["client"]["path"] == "/desk"
        assert body["features"]["threads"] is True
        assert body["features"]["client_served_by_brain"] is True
