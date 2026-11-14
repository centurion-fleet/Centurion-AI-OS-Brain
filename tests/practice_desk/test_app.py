"""The desk over HTTP: invitation, enrolment, sign-in, session, stream, refusal.

Every test here drives the real aiohttp application through a real client. The
authenticator is software (there is no browser in a test run), but the ceremony
is the same shape a browser produces, so what is exercised is the code that will
run in front of a partner.

The one test that matters most commercially is
`test_today_reports_unmeasured_panes_as_null_never_zero`: a practice acts on a
number on that page, and a confident zero over a register that does not exist is
the failure that costs a client relationship.
"""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
from types import SimpleNamespace

import pytest
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

from centurion_cli.practice_desk import app as desk_app
from centurion_cli.practice_desk import store as st

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
        noun = "user" if self.seat_limit == 1 else "users"
        return (
            f"{self.label} carries {self.seat_limit} named {noun}, and that is the "
            "whole machine. To add another person you need a bigger edition."
        )


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


async def _enrol(client, settings, *, name="Adrian Barkus", email="adrian@firm.test",
                 role="partner") -> SoftwareAuthenticator:
    store: st.PracticeStore = client.server.app[desk_app.DESK_KEY].store
    person = store.admit_person(name=name, email=email, role=role)
    token = store.issue_invitation(person.id)

    begun = await (await client.post("/api/invite", json={"token": token})).json()
    challenge = desk_app.webauthn.b64url_decode(begun["options"]["challenge"])

    auth = SoftwareAuthenticator(rp_id=RP_ID)
    reg = auth.registration(challenge, origin=ORIGIN)
    response = await client.post(
        "/api/register",
        json={
            "clientDataJSON": desk_app.webauthn.b64url_encode(reg["client_data_json"]),
            "attestationObject": desk_app.webauthn.b64url_encode(reg["attestation_object"]),
        },
    )
    payload = await response.json()
    assert payload["ok"] is True, payload
    return auth


# ── identity ────────────────────────────────────────────────────────────────


def test_an_invitation_enrols_a_passkey_and_opens_a_session(settings):
    async def scenario():
        client = await _client(settings)
        try:
            auth = await _enrol(client, settings)
            me = await (await client.get("/api/me")).json()
            assert me["person"]["name"] == "Adrian Barkus"
            assert me["person"]["role"] == "partner"
            # And the credential is the one the authenticator holds.
            store = client.server.app[desk_app.DESK_KEY].store
            creds = store.credentials_for(me["person"]["id"])
            assert len(creds) == 1
            assert creds[0]["id"] == desk_app.webauthn.b64url_encode(auth.credential_id)
        finally:
            await client.close()

    run(scenario())


def test_a_second_signin_with_the_same_passkey_works(settings):
    async def scenario():
        client = await _client(settings)
        try:
            auth = await _enrol(client, settings)
            await client.post("/api/signout", json={})

            begun = await (await client.post("/api/signin/begin", json={})).json()
            challenge = desk_app.webauthn.b64url_decode(begun["options"]["challenge"])
            assertion = auth.assertion(challenge, origin=ORIGIN)
            response = await client.post("/api/signin/finish", json=assertion)
            payload = await response.json()
            assert payload["ok"] is True, payload

            me = await (await client.get("/api/me")).json()
            assert me["person"]["email"] == "adrian@firm.test"
        finally:
            await client.close()

    run(scenario())


def test_the_desk_refuses_everything_without_a_session(settings):
    async def scenario():
        client = await _client(settings)
        try:
            for path in ("/api/me", "/api/today", "/api/thread"):
                response = await client.get(path)
                assert response.status == 401, path
        finally:
            await client.close()

    run(scenario())


def test_a_replayed_invitation_cannot_enrol_a_second_passkey(settings):
    async def scenario():
        client = await _client(settings)
        try:
            store = client.server.app[desk_app.DESK_KEY].store
            person = store.admit_person(name="A", email="a@firm.test", role="partner")
            token = store.issue_invitation(person.id)

            first = await client.post("/api/invite", json={"token": token})
            assert (await first.json())["ok"] is True

            second = await client.post("/api/invite", json={"token": token})
            assert second.status == 400
            assert "already been used" in (await second.json())["error"]
        finally:
            await client.close()

    run(scenario())


def test_suspending_a_person_bites_on_their_next_request(settings):
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)
            store = client.server.app[desk_app.DESK_KEY].store
            person = store.list_people()[0]

            assert (await client.get("/api/today")).status == 200
            store.set_status(person.id, "suspended", by=person.id)

            assert (await client.get("/api/today")).status == 401
        finally:
            await client.close()

    run(scenario())


# ── the record ──────────────────────────────────────────────────────────────


def test_today_reports_unmeasured_panes_as_null_never_zero(settings):
    """An unreadable register is not an empty one. A partner acts on this page."""
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)
            data = await (await client.get("/api/today")).json()

            for key, pane in data["panes"].items():
                assert pane["value"] is None, f"{key} invented a value"
                assert pane["reason"], f"{key} gave no reason"
            assert len(data["unmeasured"]) == 4
            assert data["seats"]["held"] == 1
        finally:
            await client.close()

    run(scenario())


def test_the_desk_refuses_a_post_that_did_not_come_from_the_desk(settings):
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)
            response = await client.post(
                "/api/chat",
                json={"message": "hello"},
                headers={"Origin": "https://not-the-desk.example"},
            )
            assert response.status == 403
        finally:
            await client.close()

    run(scenario())


def test_a_static_path_cannot_escape_the_static_directory(settings):
    async def scenario():
        client = await _client(settings)
        try:
            for path in ("/static/../app.py", "/static/..%2fapp.py"):
                response = await client.get(path)
                assert response.status == 404, path
        finally:
            await client.close()

    run(scenario())


def test_the_health_endpoint_says_how_many_seats_are_held(settings):
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)
            data = await (await client.get("/healthz")).json()
            assert data["ok"] is True
            assert data["seats"]["held"] == 1
        finally:
            await client.close()

    run(scenario())


# ── the stream ──────────────────────────────────────────────────────────────


class FakeBrain:
    """A stand-in for the Brain's OpenAI-compatible endpoint."""

    def __init__(self) -> None:
        self.requests: list[dict] = []

    async def chat(self, request: web.Request) -> web.StreamResponse:
        body = await request.json()
        self.requests.append(body)
        response = web.StreamResponse(headers={"Content-Type": "text/event-stream"})
        await response.prepare(request)
        for word in ("Your year end ", "is 31 March."):
            await response.write(
                f"data: {json.dumps({'choices': [{'delta': {'content': word}}]})}\n\n".encode()
            )
        await response.write(b"data: [DONE]\n\n")
        await response.write_eof()
        return response


def test_chat_streams_from_the_brain_and_lands_in_the_record(settings):
    async def scenario():
        brain = FakeBrain()
        brain_app = web.Application()
        brain_app.router.add_post("/v1/chat/completions", brain.chat)
        brain_server = TestServer(brain_app)
        await brain_server.start_server()
        settings.brain_url = str(brain_server.make_url("")).rstrip("/")

        client = await _client(settings)
        try:
            await _enrol(client, settings)

            response = await client.post("/api/chat", json={"message": "When is Hargreaves' year end?"})
            assert response.status == 200
            raw = await response.text()
            assert '"delta": "Your year end "' in raw or "Your year end" in raw
            assert '"done": true' in raw

            # The Brain was told who was asking, not just what was asked.
            sent = brain.requests[0]["messages"]
            assert "Adrian Barkus" in sent[0]["content"]
            assert "partner" in sent[0]["content"]

            # And the exchange is in the practice's record.
            thread = await (await client.get("/api/thread")).json()
            roles = [m["role"] for m in thread["messages"]]
            assert roles == ["user", "assistant"]
            assert thread["messages"][1]["content"] == "Your year end is 31 March."
        finally:
            await client.close()
            await brain_server.close()

    run(scenario())


def test_a_failed_brain_call_is_reported_and_not_recorded_as_an_answer(settings):
    async def scenario():
        async def broken(request):
            return web.json_response({"error": "no credit"}, status=402)

        brain_app = web.Application()
        brain_app.router.add_post("/v1/chat/completions", broken)
        brain_server = TestServer(brain_app)
        await brain_server.start_server()
        settings.brain_url = str(brain_server.make_url("")).rstrip("/")

        client = await _client(settings)
        try:
            await _enrol(client, settings)
            response = await client.post("/api/chat", json={"message": "hello"})
            raw = await response.text()
            assert "error" in raw
            assert "402" in raw

            thread = await (await client.get("/api/thread")).json()
            roles = [m["role"] for m in thread["messages"]]
            # The question is kept; no empty answer is invented.
            assert roles == ["user"]

            actions = [r["action"] for r in client.server.app[desk_app.DESK_KEY].store.audit_log()]
            assert "answer_failed" in actions
        finally:
            await client.close()
            await brain_server.close()

    run(scenario())


def test_the_desk_refuses_to_serve_a_network_address_without_tls(settings):
    """Browsers will not register a passkey over plain HTTP on a LAN address."""
    settings.host = "0.0.0.0"
    settings.tls_cert = None
    with pytest.raises(SystemExit) as caught:
        desk_app.serve(settings)
    assert "TLS" in str(caught.value)
