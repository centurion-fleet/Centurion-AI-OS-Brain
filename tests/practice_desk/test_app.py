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

            # The drafts register now exists, so that pane is a real count (zero,
            # because nothing has been submitted). Every pane without a register
            # behind it still refuses to invent one.
            assert data["panes"]["drafts_awaiting_signature"]["value"] == 0
            for key in ("clients_chased_no_reply", "hours_returned_this_month",
                        "deadlines_inside_14_days"):
                pane = data["panes"][key]
                assert pane["value"] is None, f"{key} invented a value"
                assert pane["reason"], f"{key} gave no reason"
            assert len(data["unmeasured"]) == 3
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


# ── people ──────────────────────────────────────────────────────────────────


def test_a_partner_can_admit_a_person_and_gets_a_working_link(settings):
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)   # Adrian, partner
            response = await client.post(
                "/api/people/invite",
                json={"name": "Peta Barkus", "email": "peta@firm.test", "role": "manager"},
            )
            data = await response.json()
            assert response.status == 200, data
            assert data["link"].startswith(ORIGIN + "/#invite=")
            assert "peta@firm.test" in json.dumps(data)

            listed = await (await client.get("/api/people")).json()
            emails = {p["email"] for p in listed["people"]}
            assert emails == {"adrian@firm.test", "peta@firm.test"}
            assert listed["seats"]["held"] == 2
        finally:
            await client.close()

    run(scenario())


def test_an_associate_cannot_admit_anyone(settings):
    """The sentence matters: it names the role rather than saying 'forbidden'."""
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings, name="Adrian Barkus", email="adrian@firm.test",
                         role="partner")
            # admit + enrol an associate directly through the store
            store = client.server.app[desk_app.DESK_KEY].store
            associate = store.admit_person(name="Junior", email="junior@firm.test",
                                           role="associate")
            store.add_credential(associate.id, credential_id="c2", public_key=b"k", algorithm=-7)
            from centurion_cli.practice_desk.store import _hash_token  # noqa: PLC0415

            token = store.open_session(associate.id)
        finally:
            await client.close()

        # A second client carrying the associate's session.
        client2 = await _client(settings)
        try:
            client2.session.cookie_jar.update_cookies({"pd_session": token})
            for path in ("/api/people",):
                response = await client2.get(path)
                assert response.status == 400
                assert "associate" in (await response.json())["error"]
            response = await client2.post(
                "/api/people/invite", json={"name": "X", "email": "x@firm.test"}
            )
            assert response.status == 400
        finally:
            await client2.close()

    run(scenario())


def test_the_eleventh_person_is_refused_in_the_licences_own_words(settings, monkeypatch):
    import centurion.license.edition as edition_mod

    monkeypatch.setattr(edition_mod, "current_edition", lambda: FakeEdition(2))

    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)
            ok = await client.post(
                "/api/people/invite", json={"name": "Second", "email": "second@firm.test"}
            )
            assert ok.status == 200

            refused = await client.post(
                "/api/people/invite", json={"name": "Third", "email": "third@firm.test"}
            )
            assert refused.status == 400
            message = (await refused.json())["error"]
            assert "2 named users" in message
            assert "bigger edition" in message
        finally:
            await client.close()

    run(scenario())


def test_a_partner_cannot_suspend_their_own_seat(settings):
    """Otherwise the last partner locks the practice out of its own machine."""
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)
            me = await (await client.get("/api/me")).json()
            response = await client.post(
                "/api/people/status", json={"id": me["person"]["id"], "status": "suspended"}
            )
            assert response.status == 400
            assert "own seat" in (await response.json())["error"]
        finally:
            await client.close()

    run(scenario())


# ── client threads ──────────────────────────────────────────────────────────


def _add_person_with_session(client, *, name, email, role):
    """Straight to the store: this is about the thread, not the ceremony."""
    store = client.server.app[desk_app.DESK_KEY].store
    person = store.admit_person(name=name, email=email, role=role)
    store.add_credential(
        person.id, credential_id=f"cred-{person.id}", public_key=b"k", algorithm=-7
    )
    return person, store.open_session(person.id)


def test_a_client_thread_is_shared_and_carries_who_said_what(settings, tmp_path):
    from centurion_cli.practice_desk.demo import build_demo_library

    settings.practice_library = build_demo_library(tmp_path)

    async def scenario():
        partner_client = await _client(settings)
        associate_client = await _client(settings)
        try:
            await _enrol(partner_client, settings)
            _person, token = _add_person_with_session(
                partner_client, name="Peta Barkus", email="peta@firm.test", role="manager"
            )
            associate_client.session.cookie_jar.update_cookies({"pd_session": token})

            # The client list comes from the practice library.
            clients = await (await partner_client.get("/api/clients")).json()
            assert len(clients["clients"]) == 8
            slug = clients["clients"][0]["slug"]

            # A manager is not assigned yet, so the file is not hers to read.
            refused = await associate_client.get(f"/api/thread?scope=client&client={slug}")
            assert refused.status == 400
            assert "not assigned" in (await refused.json())["error"]

            # The partner assigns her, and only then does the thread open.
            assigned = await partner_client.post(
                "/api/clients/assign",
                json={"client": slug, "person": _person.id, "action": "assign"},
            )
            assert assigned.status == 200, await assigned.json()

            # The partner writes in the shared thread.
            await partner_client.post(
                f"/api/chat?scope=client&client={slug}", json={"message": "What is due here?"}
            )

            # The manager sees it, attributed to the partner rather than to "You".
            shared = await (
                await associate_client.get(f"/api/thread?scope=client&client={slug}")
            ).json()
            assert shared["conversation"]["scope"] == "client"
            her_view = [m for m in shared["messages"] if m["role"] == "user"]
            assert her_view and her_view[0]["author"] == "Adrian Barkus"

            # But not the partner's private thread.
            private = await (await associate_client.get("/api/thread")).json()
            assert private["messages"] == []
        finally:
            await partner_client.close()
            await associate_client.close()

    run(scenario())


def test_a_client_thread_without_a_client_is_refused(settings):
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)
            response = await client.get("/api/thread?scope=client")
            assert response.status == 400
            assert "must name its client" in (await response.json())["error"]
        finally:
            await client.close()

    run(scenario())


# ── drafts: the thing a partner signs ───────────────────────────────────────


def test_a_draft_moves_from_prepared_to_signed_and_records_both_people(settings):
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)
            created = await (
                await client.post("/api/drafts", json={"body": "Dear Sirs, your year end.", "kind": "letter"})
            ).json()
            draft = created["draft"]
            assert draft["status"] == "draft"

            submitted = await (
                await client.post("/api/drafts/action", json={"id": draft["id"], "action": "submit"})
            ).json()
            assert submitted["draft"]["status"] == "awaiting_signature"

            today = await (await client.get("/api/today")).json()
            assert today["panes"]["drafts_awaiting_signature"]["value"] == 1

            signed = await (
                await client.post("/api/drafts/action", json={"id": draft["id"], "action": "sign"})
            ).json()
            assert signed["draft"]["status"] == "signed"
            assert signed["draft"]["signed_by"]
            assert signed["draft"]["signed_at"]

            today = await (await client.get("/api/today")).json()
            assert today["panes"]["drafts_awaiting_signature"]["value"] == 0
        finally:
            await client.close()

    run(scenario())


def test_only_a_partner_signs(settings):
    async def scenario():
        boss = await _client(settings)
        staff = await _client(settings)
        try:
            await _enrol(boss, settings)
            worker, token = _add_person_with_session(
                boss, name="Worker", email="worker@firm.test", role="associate"
            )
            staff.session.cookie_jar.update_cookies({"pd_session": token})

            draft = (await (
                await staff.post("/api/drafts", json={"body": "A covering email."})
            ).json())["draft"]
            await staff.post("/api/drafts/action", json={"id": draft["id"], "action": "submit"})

            refused = await staff.post(
                "/api/drafts/action", json={"id": draft["id"], "action": "sign"}
            )
            assert refused.status == 400
            assert "Only a partner can sign" in (await refused.json())["error"]

            # And the draft is still waiting, rather than silently signed.
            still = await (await boss.get("/api/drafts?status=awaiting_signature")).json()
            assert [d["id"] for d in still["drafts"]] == [draft["id"]]
        finally:
            await boss.close()
            await staff.close()

    run(scenario())


def test_only_the_preparer_may_submit_a_draft(settings):
    async def scenario():
        boss = await _client(settings)
        staff = await _client(settings)
        try:
            await _enrol(boss, settings)
            worker, token = _add_person_with_session(
                boss, name="Worker", email="worker@firm.test", role="manager"
            )
            staff.session.cookie_jar.update_cookies({"pd_session": token})

            draft = (await (
                await staff.post("/api/drafts", json={"body": "Prepared by the manager."})
            ).json())["draft"]

            refused = await boss.post(
                "/api/drafts/action", json={"id": draft["id"], "action": "submit"}
            )
            assert refused.status == 400
            assert "prepared" in (await refused.json())["error"]
        finally:
            await boss.close()
            await staff.close()

    run(scenario())


def test_a_draft_cannot_be_signed_without_being_submitted_first(settings):
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)
            draft = (await (
                await client.post("/api/drafts", json={"body": "Straight to signature."})
            ).json())["draft"]
            refused = await client.post(
                "/api/drafts/action", json={"id": draft["id"], "action": "sign"}
            )
            assert refused.status == 400
            assert "cannot become signed" in (await refused.json())["error"]
        finally:
            await client.close()

    run(scenario())


def test_signing_your_own_draft_is_allowed_and_says_so_on_the_record(settings):
    """A sole practitioner signs their own work. Pretending two people looked at
    it would be a worse record than saying plainly that one did."""
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)
            draft = (await (
                await client.post("/api/drafts", json={"body": "Sole practitioner letter."})
            ).json())["draft"]
            await client.post("/api/drafts/action", json={"id": draft["id"], "action": "submit"})
            await client.post("/api/drafts/action", json={"id": draft["id"], "action": "sign"})

            store = client.server.app[desk_app.DESK_KEY].store
            actions = [(r["action"], r["detail"]) for r in store.audit_log(30)]
            assert ("draft_signed", "signed by its own preparer") in actions
        finally:
            await client.close()

    run(scenario())


def test_you_cannot_draft_on_a_client_you_are_not_assigned_to(settings, tmp_path):
    from centurion_cli.practice_desk.demo import build_demo_library

    settings.practice_library = build_demo_library(tmp_path)

    async def scenario():
        boss = await _client(settings)
        staff = await _client(settings)
        try:
            await _enrol(boss, settings)
            _worker, token = _add_person_with_session(
                boss, name="Worker", email="worker@firm.test", role="associate"
            )
            staff.session.cookie_jar.update_cookies({"pd_session": token})
            refused = await staff.post(
                "/api/drafts", json={"body": "Hello.", "client": "fenwick-farm"}
            )
            assert refused.status == 400
            assert "not assigned" in (await refused.json())["error"]
        finally:
            await boss.close()
            await staff.close()

    run(scenario())


# ── the Firm rule: who may see which client ─────────────────────────────────


def test_an_unassigned_associate_is_refused_at_the_door_and_the_attempt_is_recorded(
    settings, tmp_path
):
    from centurion_cli.practice_desk.demo import build_demo_library

    settings.practice_library = build_demo_library(tmp_path)

    async def scenario():
        boss = await _client(settings)
        junior_client = await _client(settings)
        try:
            await _enrol(boss, settings)
            junior, token = _add_person_with_session(
                boss, name="Junior", email="junior@firm.test", role="associate"
            )
            junior_client.session.cookie_jar.update_cookies({"pd_session": token})
            slug = "hargreaves-and-sons"

            # Reading is refused.
            read = await junior_client.get(f"/api/thread?scope=client&client={slug}")
            assert read.status == 400
            assert "not assigned" in (await read.json())["error"]

            # And so is writing — the chat route is not a way round the refusal.
            write = await junior_client.post(
                f"/api/chat?scope=client&client={slug}", json={"message": "hello"}
            )
            assert write.status == 400

            # The refusal itself is on the record, with the person's role.
            store = boss.server.app[desk_app.DESK_KEY].store
            actions = [(r["action"], r["detail"]) for r in store.audit_log(50)]
            assert ("client_access_refused", "role associate") in actions
        finally:
            await boss.close()
            await junior_client.close()

    run(scenario())


def test_assignment_opens_the_thread_and_unassignment_closes_it_again(settings, tmp_path):
    from centurion_cli.practice_desk.demo import build_demo_library

    settings.practice_library = build_demo_library(tmp_path)

    async def scenario():
        boss = await _client(settings)
        staff = await _client(settings)
        try:
            await _enrol(boss, settings)
            worker, token = _add_person_with_session(
                boss, name="Worker", email="worker@firm.test", role="associate"
            )
            staff.session.cookie_jar.update_cookies({"pd_session": token})
            slug = "millfield-joinery"

            await boss.post(
                "/api/clients/assign",
                json={"client": slug, "person": worker.id, "action": "assign"},
            )
            opened = await staff.get(f"/api/thread?scope=client&client={slug}")
            assert opened.status == 200
            assert (await opened.json())["conversation"]["scope"] == "client"

            await boss.post(
                "/api/clients/assign",
                json={"client": slug, "person": worker.id, "action": "unassign"},
            )
            closed = await staff.get(f"/api/thread?scope=client&client={slug}")
            assert closed.status == 400
        finally:
            await boss.close()
            await staff.close()

    run(scenario())


def test_an_administrator_sees_no_client_files_even_when_assigned(settings, tmp_path):
    """The role runs the machine. Giving it client access is how confidentiality
    failures start, so the assignment does not open a door it should not."""
    from centurion_cli.practice_desk.demo import build_demo_library

    settings.practice_library = build_demo_library(tmp_path)

    async def scenario():
        boss = await _client(settings)
        it_client = await _client(settings)
        try:
            await _enrol(boss, settings)
            it_person, token = _add_person_with_session(
                boss, name="IT", email="it@firm.test", role="administrator"
            )
            it_client.session.cookie_jar.update_cookies({"pd_session": token})
            await boss.post(
                "/api/clients/assign",
                json={"client": "fenwick-farm", "person": it_person.id, "action": "assign"},
            )
            refused = await it_client.get("/api/thread?scope=client&client=fenwick-farm")
            assert refused.status == 400

            listed = await (await it_client.get("/api/clients")).json()
            assert listed["clients"] == []
            assert listed["hidden_count"] == 8
        finally:
            await boss.close()
            await it_client.close()

    run(scenario())


def test_only_a_partner_may_assign_a_client(settings, tmp_path):
    from centurion_cli.practice_desk.demo import build_demo_library

    settings.practice_library = build_demo_library(tmp_path)

    async def scenario():
        boss = await _client(settings)
        manager_client = await _client(settings)
        try:
            await _enrol(boss, settings)
            manager, token = _add_person_with_session(
                boss, name="Manager", email="manager@firm.test", role="manager"
            )
            manager_client.session.cookie_jar.update_cookies({"pd_session": token})
            response = await manager_client.post(
                "/api/clients/assign",
                json={"client": "quill-street-studio", "person": manager.id, "action": "assign"},
            )
            assert response.status == 400
            assert "Only a partner" in (await response.json())["error"]
        finally:
            await boss.close()
            await manager_client.close()

    run(scenario())


def test_the_client_list_does_not_advertise_files_the_person_cannot_open(settings, tmp_path):
    from centurion_cli.practice_desk.demo import build_demo_library

    settings.practice_library = build_demo_library(tmp_path)

    async def scenario():
        boss = await _client(settings)
        staff = await _client(settings)
        try:
            await _enrol(boss, settings)
            worker, token = _add_person_with_session(
                boss, name="Worker", email="worker@firm.test", role="associate"
            )
            staff.session.cookie_jar.update_cookies({"pd_session": token})
            await boss.post(
                "/api/clients/assign",
                json={"client": "brook-house-dental", "person": worker.id, "action": "assign"},
            )

            mine = await (await staff.get("/api/clients")).json()
            assert [c["slug"] for c in mine["clients"]] == ["brook-house-dental"]
            assert mine["hidden_count"] == 7
            assert mine["clients"][0]["assigned"] == ["Worker"]

            everything = await (await boss.get("/api/clients")).json()
            assert len(everything["clients"]) == 8
            assert everything["hidden_count"] == 0
        finally:
            await boss.close()
            await staff.close()

    run(scenario())


# ── deadlines ───────────────────────────────────────────────────────────────


def test_the_deadline_list_is_computed_from_the_client_library(settings, tmp_path):
    """Guards the route itself: a handler reaching for the wrong app key 500s,
    which the page reads as 'could not read the record' and nobody is told why."""
    from centurion_cli.practice_desk.demo import build_demo_library

    settings.practice_library = build_demo_library(tmp_path)

    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)
            response = await client.get("/api/deadlines?days=45")
            assert response.status == 200
            data = await response.json()
            assert data["ok"] is True
            assert data["obligations"], "the sample practice produced no obligations"
            first = data["obligations"][0]
            for key in ("client", "kind", "due", "days", "rule"):
                assert key in first, key
            assert isinstance(first["due"], str), "a date must not reach JSON as an object"
        finally:
            await client.close()

    run(scenario())


def test_the_deadline_pane_is_measured_once_a_library_exists(settings, tmp_path):
    from centurion_cli.practice_desk.demo import build_demo_library

    settings.practice_library = build_demo_library(tmp_path)

    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)
            data = await (await client.get("/api/today")).json()
            pane = data["panes"]["deadlines_inside_14_days"]
            assert pane["value"] is not None
            assert isinstance(pane["value"], int)
            # The panes with no register behind them still refuse to invent zero.
            assert data["panes"]["clients_chased_no_reply"]["value"] is None
            assert data["panes"]["hours_returned_this_month"]["value"] is None
            assert data["panes"]["drafts_awaiting_signature"]["value"] == 0
            assert len(data["unmeasured"]) == 2
        finally:
            await client.close()

    run(scenario())


# ── capability by role ──────────────────────────────────────────────────────


def test_a_non_partner_browser_session_is_narrowed_before_it_reaches_the_brain(settings):
    """A junior must not be able to ask the Centurion for a shell on the box.

    Exercised directly on the stream helper rather than through two browsers: what
    is being tested is the body the desk sends, and a two-client scenario spends
    its difficulty on test plumbing instead of on the rule.
    """
    brain = FakeBrain()
    brain_app = web.Application()
    brain_app.router.add_post("/v1/chat/completions", brain.chat)
    brain_server = TestServer(brain_app)

    store = st.PracticeStore(settings.db_path)
    partner = store.admit_person(name="Adrian", email="a@firm.test", role="partner")
    associate = store.admit_person(name="Junior", email="j@firm.test", role="associate")

    async def scenario():
        await brain_server.start_server()
        try:
            settings.brain_url = str(brain_server.make_url("")).rstrip("/")
            desk = desk_app.Desk(settings=settings, store=store)

            async for _ in desk_app._stream_from_brain(desk, partner, [{"role": "user", "content": "hi"}]):
                pass
            async for _ in desk_app._stream_from_brain(desk, associate, [{"role": "user", "content": "hi"}]):
                pass
        finally:
            await brain_server.close()

    run(scenario())

    partner_body, junior_body = brain.requests[0], brain.requests[1]
    assert "toolsets" not in partner_body, "a partner keeps the platform's set"
    assert sorted(junior_body["toolsets"]) == sorted(desk_app.PRACTICE_TOOLSETS)
    for forbidden in ("terminal", "code_execution", "cronjob", "delegation"):
        assert forbidden not in junior_body["toolsets"]


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


# ── roles: what a person is allowed to be ───────────────────────────────────


def _sideline(client, *, name: str, email: str, role: str) -> str:
    """Admit someone and give the caller a live session token for them.

    No passkey ceremony: the point of these tests is what a role permits once
    a person is signed in, not how they got there.
    """
    store = client.server.app[desk_app.DESK_KEY].store
    person = store.admit_person(name=name, email=email, role=role)
    store.set_status(person.id, "active")
    return store.open_session(person.id)


def test_a_promotion_bites_on_the_next_request_without_a_signin(settings):
    """A role is read per request, so nothing cached can go stale.

    The same session that was refused a moment ago is allowed after the
    promotion — no sign-out and no new passkey.
    """
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)  # Adrian, partner
            token = _sideline(client, name="Junior", email="junior@firm.test",
                              role="associate")
            store = client.server.app[desk_app.DESK_KEY].store
            junior = store.person_by_email("junior@firm.test")
            adrian = store.person_by_email("adrian@firm.test")
            adrian_token = store.open_session(adrian.id)
        finally:
            await client.close()

        before = await _client(settings)
        try:
            before.session.cookie_jar.update_cookies({"pd_session": token})
            refused = await before.get("/api/people")
            assert refused.status == 400
            assert "associate" in (await refused.json())["error"]
        finally:
            await before.close()

        promoter = await _client(settings)
        try:
            promoter.session.cookie_jar.update_cookies({"pd_session": adrian_token})
            response = await promoter.post(
                "/api/people/role", json={"id": junior.id, "role": "partner"}
            )
            data = await response.json()
            assert response.status == 200, data
            assert data["person"]["role"] == "partner"
        finally:
            await promoter.close()

        after = await _client(settings)
        try:
            after.session.cookie_jar.update_cookies({"pd_session": token})
            allowed = await after.get("/api/people")
            assert allowed.status == 200
            assert (await allowed.json())["ok"] is True
        finally:
            await after.close()

    run(scenario())


def test_an_administrator_cannot_promote_themselves_to_partner(settings):
    """An administrator runs the machine. Partner means the signature and the
    client files. Letting the machine's keeper grant that to themselves is
    privilege escalation with a friendly label, so the route refuses it."""
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)  # Adrian, partner
            token = _sideline(client, name="Ops", email="ops@firm.test",
                              role="administrator")
            store = client.server.app[desk_app.DESK_KEY].store
            ops = store.person_by_email("ops@firm.test")
        finally:
            await client.close()

        keeper = await _client(settings)
        try:
            keeper.session.cookie_jar.update_cookies({"pd_session": token})
            response = await keeper.post(
                "/api/people/role", json={"id": ops.id, "role": "partner"}
            )
            assert response.status == 400
            assert "Only a partner" in (await response.json())["error"]
        finally:
            await keeper.close()

    run(scenario())


def test_the_last_partner_cannot_be_demoted(settings):
    """The refusal names the consequence, not the rule: nobody would be left
    who may sign. Once a second partner exists, the same demotion is allowed."""
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)  # Adrian, sole partner
            store = client.server.app[desk_app.DESK_KEY].store
            adrian = store.person_by_email("adrian@firm.test")

            first = await client.post(
                "/api/people/role", json={"id": adrian.id, "role": "manager"}
            )
            assert first.status == 400
            said = (await first.json())["error"]
            assert "last partner who can sign" in said
            assert "sign" in said

            _sideline(client, name="Second Partner", email="two@firm.test",
                      role="partner")
            second = await client.post(
                "/api/people/role", json={"id": adrian.id, "role": "manager"}
            )
            assert second.status == 200, await second.json()
            assert (await second.json())["person"]["role"] == "manager"
        finally:
            await client.close()

    run(scenario())


def test_a_role_change_is_recorded_with_both_roles(settings):
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)
            store = client.server.app[desk_app.DESK_KEY].store
            junior = store.admit_person(name="Junior", email="junior@firm.test",
                                        role="associate")
            response = await client.post(
                "/api/people/role", json={"id": junior.id, "role": "manager"}
            )
            assert response.status == 200, await response.json()

            entries = [
                r for r in store.audit_log()
                if r["action"] == "person_role_changed"
            ]
            assert len(entries) == 1
            assert "associate" in entries[0]["detail"]
            assert "manager" in entries[0]["detail"]
            # The person who made the change is on the record.
            adrian = store.person_by_email("adrian@firm.test")
            assert entries[0]["person_id"] == adrian.id
        finally:
            await client.close()

    run(scenario())


def test_an_unknown_role_is_refused_and_nothing_changes(settings):
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)
            store = client.server.app[desk_app.DESK_KEY].store
            junior = store.admit_person(name="Junior", email="junior@firm.test",
                                        role="associate")
            response = await client.post(
                "/api/people/role", json={"id": junior.id, "role": "owner"}
            )
            assert response.status == 400
            assert store.get_person(junior.id).role == "associate"
        finally:
            await client.close()

    run(scenario())


# ── the record ──────────────────────────────────────────────────────────────


def test_the_record_shows_names_not_ids_and_names_the_departed(settings):
    """A partner reads a list of people, not a list of tokens. Someone who has
    left keeps their name on their rows instead of the entry going blank."""
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)  # Adrian, partner
            store = client.server.app[desk_app.DESK_KEY].store
            gone = store.admit_person(name="Former Clerk", email="gone@firm.test",
                                      role="associate")
            # A row the departed person did themselves, still on the record.
            store.record(gone.id, "draft_prepared", detail="their last draft")
            store.set_status(gone.id, "departed")
            # A row with no person at all — the machine's own work.
            store.record(None, "machine_started")

            data = await (await client.get("/api/audit?limit=50")).json()
            assert data["ok"] is True
            whos = {e["who"] for e in data["entries"]}
            assert "Adrian Barkus" in whos
            assert "Former Clerk" in whos          # departed, still named
            assert "the machine" in whos           # nobody, still honest
            # An id that does not resolve is named as such, never blanked.
            store.record("not-a-real-id", "draft_prepared")
            again = await (await client.get("/api/audit?limit=50")).json()
            assert any(e["who"] == "departed seat" for e in again["entries"])
        finally:
            await client.close()

    run(scenario())


def test_an_associate_cannot_read_the_record(settings):
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)
            token = _sideline(client, name="Junior", email="junior@firm.test",
                              role="associate")
        finally:
            await client.close()

        junior = await _client(settings)
        try:
            junior.session.cookie_jar.update_cookies({"pd_session": token})
            response = await junior.get("/api/audit")
            assert response.status == 400
            assert "associate" in (await response.json())["error"]
        finally:
            await junior.close()

    run(scenario())


def test_the_record_limit_cannot_be_used_to_dump_the_whole_register(settings):
    async def scenario():
        client = await _client(settings)
        try:
            await _enrol(client, settings)
            response = await client.get("/api/audit?limit=100000")
            assert response.status == 200
            data = await response.json()
            assert len(data["entries"]) <= 200
            bogus = await client.get("/api/audit?limit=not-a-number")
            assert bogus.status == 200  # falls back to the default, never a 500
        finally:
            await client.close()

    run(scenario())
