"""Gate 1 — a Brain that knows which person is asking.

Before this, every request on the Brain carried one shared key, so a firm with
five people had one credential between them and the audit said "something did
it". These tests hold the replacement in place: a passkey per person, sessions
that can be revoked one at a time, and a first claim that only happens on the
machine itself.
"""

from __future__ import annotations

import time

import pytest
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

from centurion_identity import IdentityError, IdentityStore
from gateway.config import PlatformConfig
from gateway.platforms.api_server import APIServerAdapter

SERVICE = {"Authorization": "Bearer " + "sk-service"}


def _make_adapter() -> APIServerAdapter:
    return APIServerAdapter(PlatformConfig(enabled=True, extra={"key": "sk-service"}))


def _create_app(adapter: APIServerAdapter) -> web.Application:
    app = web.Application()
    app["api_server_adapter"] = adapter
    app.router.add_get("/v1/capabilities", adapter._handle_capabilities)
    app.router.add_get("/api/identity", adapter._handle_identity_state)
    app.router.add_post("/api/identity/claim", adapter._handle_identity_claim)
    app.router.add_post("/api/identity/register", adapter._handle_identity_register)
    app.router.add_post("/api/identity/signin/options", adapter._handle_identity_signin_options)
    app.router.add_post("/api/identity/signin", adapter._handle_identity_signin)
    app.router.add_post("/api/identity/signout", adapter._handle_identity_signout)
    app.router.add_post("/api/identity/invite", adapter._handle_identity_invite)
    app.router.add_get("/api/me", adapter._handle_identity_me)
    return app


@pytest.fixture
def store(tmp_path):
    made = IdentityStore(tmp_path / "identity.db")
    yield made
    made.close()


@pytest.fixture
def adapter(store, monkeypatch):
    made = _make_adapter()
    monkeypatch.setattr(made, "_identity", lambda: store)
    return made


class TestTheStore:
    def test_the_first_person_is_the_owner_and_the_second_claim_is_refused(self, store):
        owner = store.claim("Adrian Barkus", "Adrian@Example.com")
        assert owner.role == "owner"
        assert owner.email == "adrian@example.com"  # case folded, so no duplicates
        with pytest.raises(IdentityError):
            store.claim("Someone Else", "else@example.com")

    def test_an_invitation_works_once_and_then_says_so(self, store):
        store.claim("Adrian Barkus", "adrian@example.com")
        mate = store.admit("Peta Barkus", "peta@example.com", role="member")
        token = store.issue_invitation(mate.id)
        assert store.redeem_invitation(token).id == mate.id
        with pytest.raises(IdentityError, match="already been used"):
            store.redeem_invitation(token)

    def test_an_expired_invitation_is_refused(self, store):
        store.claim("Adrian Barkus", "adrian@example.com")
        mate = store.admit("Peta Barkus", "peta@example.com")
        token = store.issue_invitation(mate.id)
        store._conn.execute("UPDATE invitations SET expires_at = ?", (time.time() - 1,))
        store._conn.commit()
        with pytest.raises(IdentityError, match="expired"):
            store.redeem_invitation(token)

    def test_a_session_can_be_closed_without_closing_the_others(self, store):
        owner = store.claim("Adrian Barkus", "adrian@example.com")
        laptop = store.open_session(owner.id)
        phone = store.open_session(owner.id)
        store.close_session(laptop)
        assert store.resolve_session(laptop) is None
        assert store.resolve_session(phone).id == owner.id

    def test_an_expired_session_stops_working(self, store):
        owner = store.claim("Adrian Barkus", "adrian@example.com")
        token = store.open_session(owner.id)
        store._conn.execute("UPDATE sessions SET expires_at = ?", (time.time() - 1,))
        store._conn.commit()
        assert store.resolve_session(token) is None

    def test_sessions_are_stored_hashed_so_a_stolen_database_is_not_a_stolen_key(self, store):
        owner = store.claim("Adrian Barkus", "adrian@example.com")
        token = store.open_session(owner.id)
        rows = store._conn.execute("SELECT token_hash FROM sessions").fetchall()
        assert all(token not in row["token_hash"] for row in rows)

    def test_the_throttle_refuses_after_the_limit_and_survives_a_reopen(self, store, tmp_path):
        for _ in range(5):
            assert store.allow_attempt("signin:1.2.3.4", limit=5, window_seconds=60)
        assert store.allow_attempt("signin:1.2.3.4", limit=5, window_seconds=60) is False
        store.close()
        reopened = IdentityStore(tmp_path / "identity.db")
        try:
            assert reopened.allow_attempt("signin:1.2.3.4", limit=5, window_seconds=60) is False
        finally:
            reopened.close()

    def test_a_member_cannot_be_created_as_a_second_owner(self, store):
        store.claim("Adrian Barkus", "adrian@example.com")
        with pytest.raises(IdentityError, match="only one owner"):
            store.admit("Sneaky", "sneaky@example.com", role="owner")


class TestOverHTTP:
    @pytest.mark.asyncio
    async def test_an_unclaimed_brain_says_so(self, adapter):
        async with TestClient(TestServer(_create_app(adapter))) as client:
            body = await (await client.get("/api/identity")).json()
        assert body["claimed"] is False
        assert body["me"] is None

    @pytest.mark.asyncio
    async def test_the_machine_can_be_claimed_and_hands_back_a_passkey_prompt(self, adapter):
        async with TestClient(TestServer(_create_app(adapter))) as client:
            response = await client.post(
                "/api/identity/claim", json={"name": "Adrian Barkus", "email": "adrian@example.com"}
            )
            assert response.status == 200
            body = await response.json()
        assert body["person"]["role"] == "owner"
        assert body["options"]["rp"]["id"] == "127.0.0.1"
        assert body["options"]["authenticatorSelection"]["residentKey"] == "required"
        assert body["challenge"]

    @pytest.mark.asyncio
    async def test_a_brain_on_a_network_cannot_be_claimed_by_whoever_finds_it(self, adapter):
        async with TestClient(TestServer(_create_app(adapter))) as client:
            response = await client.post(
                "/api/identity/claim",
                json={"name": "Opportunist", "email": "me@example.com"},
                headers={"X-Forwarded-For": "203.0.113.9"},
            )
            assert response.status == 403
            assert (await response.json())["error"]["code"] == "claim_requires_local_access"

    @pytest.mark.asyncio
    async def test_a_half_finished_claim_can_be_resumed_rather_than_stranding_the_brain(
        self, adapter, store
    ):
        async with TestClient(TestServer(_create_app(adapter))) as client:
            first = await (await client.post(
                "/api/identity/claim", json={"name": "Adrian", "email": "adrian@example.com"}
            )).json()
            # The passkey prompt was dismissed. The next visit must not leave the
            # machine owned by somebody who cannot sign in.
            second = await (await client.post(
                "/api/identity/claim", json={"name": "Adrian", "email": "adrian@example.com"}
            )).json()
        assert second["person"]["id"] == first["person"]["id"]
        assert store.people_count() == 1

    @pytest.mark.asyncio
    async def test_a_claimed_brain_refuses_a_second_owner(self, adapter, store):
        store.claim("Adrian Barkus", "adrian@example.com")
        owner = store.person_by_email("adrian@example.com")
        store.add_credential(owner.id, "cred-1", b"\x00" * 32)
        async with TestClient(TestServer(_create_app(adapter))) as client:
            response = await client.post(
                "/api/identity/claim", json={"name": "Someone", "email": "s@example.com"}
            )
            body = await response.json()
        assert response.status == 409
        assert body["error"]["code"] == "already_claimed"

    @pytest.mark.asyncio
    async def test_an_invitation_needs_a_key_and_hands_back_a_one_use_link(self, adapter, store):
        store.claim("Adrian Barkus", "adrian@example.com")
        async with TestClient(TestServer(_create_app(adapter))) as client:
            refused = await client.post(
                "/api/identity/invite", json={"name": "Peta", "email": "peta@example.com"}
            )
            assert refused.status == 401

            made = await client.post(
                "/api/identity/invite",
                json={"name": "Peta Barkus", "email": "peta@example.com", "role": "member"},
                headers=SERVICE,
            )
            assert made.status == 200
            body = await made.json()
        assert body["person"]["role"] == "member"
        assert "#invite=" in body["link"]
        assert store.person_by_email("peta@example.com") is not None

    @pytest.mark.asyncio
    async def test_a_member_cannot_invite_people(self, adapter, store):
        store.claim("Adrian Barkus", "adrian@example.com")
        member = store.admit("Peta Barkus", "peta@example.com", role="member")
        token = store.open_session(member.id)
        async with TestClient(TestServer(_create_app(adapter))) as client:
            response = await client.post(
                "/api/identity/invite",
                json={"name": "Gatecrasher", "email": "gate@example.com"},
                headers={"Authorization": "Bearer " + token},
            )
            assert response.status == 403
            assert (await response.json())["error"]["code"] == "role_refused"

    @pytest.mark.asyncio
    async def test_a_session_token_identifies_the_person_and_says_who(self, adapter, store):
        owner = store.claim("Adrian Barkus", "adrian@example.com")
        token = store.open_session(owner.id)
        async with TestClient(TestServer(_create_app(adapter))) as client:
            body = await (await client.get("/api/me", headers={"Authorization": "Bearer " + token})).json()
        assert body["principal"]["kind"] == "person"
        assert body["principal"]["email"] == "adrian@example.com"
        assert body["principal"]["role"] == "owner"

    @pytest.mark.asyncio
    async def test_the_machines_own_key_still_works_and_is_not_a_person(self, adapter):
        async with TestClient(TestServer(_create_app(adapter))) as client:
            body = await (await client.get("/api/me", headers=SERVICE)).json()
        assert body["principal"]["kind"] == "service"

    @pytest.mark.asyncio
    async def test_signing_out_ends_that_session_and_nothing_else(self, adapter, store):
        owner = store.claim("Adrian Barkus", "adrian@example.com")
        token = store.open_session(owner.id)
        headers = {"Authorization": "Bearer " + token}
        async with TestClient(TestServer(_create_app(adapter))) as client:
            assert (await client.get("/api/me", headers=headers)).status == 200
            assert (await client.post("/api/identity/signout", headers=headers)).status == 200
            assert (await client.get("/api/me", headers=headers)).status == 401

    @pytest.mark.asyncio
    async def test_signing_in_is_throttled_per_address(self, adapter, store):
        async with TestClient(TestServer(_create_app(adapter))) as client:
            statuses = [
                (await client.post("/api/identity/signin/options")).status for _ in range(21)
            ]
        assert statuses[0] == 200
        assert statuses[-1] == 429

    @pytest.mark.asyncio
    async def test_an_expired_ceremony_is_refused_rather_than_accepted(self, adapter):
        async with TestClient(TestServer(_create_app(adapter))) as client:
            response = await client.post(
                "/api/identity/signin", json={"challenge": "not-a-real-challenge"}
            )
            body = await response.json()
        assert response.status == 400
        assert body["error"]["code"] == "ceremony_expired"

    @pytest.mark.asyncio
    async def test_capabilities_advertise_identity(self, adapter):
        async with TestClient(TestServer(_create_app(adapter))) as client:
            body = await (await client.get("/v1/capabilities", headers=SERVICE)).json()
        assert body["features"]["identity"] is True
        assert body["features"]["passkey_signin"] is True
        assert body["features"]["roles"] == ["owner", "admin", "member"]
        assert body["endpoints"]["identity_signin"]["path"] == "/api/identity/signin"
