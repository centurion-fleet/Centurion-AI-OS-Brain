"""The practice register: seats, invitations, sessions, and the audit trail.

The load-bearing tests are the capacity ones. `admit_person` must ask the licence
for permission and print the licence's own sentence, because that sentence is
published in the agreement — a second copy of "this machine carries ten named
users" living in the register is how the two drift apart and a customer is told
two different things on two different days.
"""

from __future__ import annotations

import sqlite3
from types import SimpleNamespace

import pytest

from centurion_cli.practice_desk import store as st


class FakeEdition:
    """Stands in for the boot-resolved edition."""

    def __init__(self, seat_limit: int, label: str = "Centurion Accountant Practice"):
        self.seat_limit = seat_limit
        self.label = label

    def admits(self, named_users):
        try:
            count = int(named_users)
        except (TypeError, ValueError):
            return False
        return 0 <= count <= self.seat_limit

    def refusal(self, named_users):
        if self.admits(named_users):
            return None
        return (
            f"{self.label} carries {self.seat_limit} named "
            f"{'user' if self.seat_limit == 1 else 'users'}, and that is the whole "
            "machine. To add another person you need a bigger edition."
        )


@pytest.fixture()
def store(tmp_path, monkeypatch):
    monkeypatch.setattr(st, "_current_edition", lambda: FakeEdition(10), raising=False)
    # store.py imports the edition lazily inside capacity_refusal, so patch there.
    import centurion.license.edition as edition_mod

    monkeypatch.setattr(edition_mod, "current_edition", lambda: FakeEdition(10))
    return st.PracticeStore(tmp_path / "practice.db")


def _add(store, name, email, role="associate"):
    return store.admit_person(name=name, email=email, role=role)


# ── capacity ────────────────────────────────────────────────────────────────


def test_ten_people_are_admitted_and_the_eleventh_is_refused_in_the_licences_words(
    store, monkeypatch
):
    for i in range(10):
        _add(store, f"Person {i}", f"p{i}@firm.test")

    with pytest.raises(st.DeskError) as caught:
        _add(store, "Eleventh", "eleven@firm.test")

    message = str(caught.value)
    assert "10 named users" in message
    assert "bigger edition" in message
    # And nothing was written — a refusal must not leave a half-person behind.
    assert store.seat_usage()["held"] == 10


def test_a_single_seat_edition_refuses_the_second_person(store, monkeypatch):
    import centurion.license.edition as edition_mod

    monkeypatch.setattr(edition_mod, "current_edition", lambda: FakeEdition(1, "Centurion Brain"))
    _add(store, "Adrian", "adrian@firm.test", role="partner")

    with pytest.raises(st.DeskError, match="second|1 named user"):
        _add(store, "Someone", "someone@firm.test")


def test_an_invited_seat_counts_against_the_limit(store, monkeypatch):
    """An invitation holds a seat. Otherwise a partner invites twelve and the
    twelfth finds out at enrolment, having already been told they are in."""
    for i in range(9):
        _add(store, f"Existing {i}", f"e{i}@firm.test")
    _add(store, "Pending", "pending@firm.test")  # still 'invited'

    assert store.seat_usage()["held"] == 10
    with pytest.raises(st.DeskError, match="named users"):
        _add(store, "One more", "more@firm.test")


def test_a_departed_person_frees_the_seat(store):
    person = _add(store, "Leaver", "leaver@firm.test")
    store.set_status(person.id, "departed")
    assert store.seat_usage()["held"] == 0


# ── invitations ─────────────────────────────────────────────────────────────


def test_an_invitation_is_single_use(store):
    person = _add(store, "New", "new@firm.test")
    token = store.issue_invitation(person.id)

    assert store.redeem_invitation(token).id == person.id
    with pytest.raises(st.DeskError, match="already been used"):
        store.redeem_invitation(token)


def test_an_expired_invitation_is_refused(store, monkeypatch):
    person = _add(store, "Slow", "slow@firm.test")
    token = store.issue_invitation(person.id)

    later = st._now() + st.INVITE_TTL_SECONDS + 5
    monkeypatch.setattr(st, "_now", lambda: later)

    with pytest.raises(st.DeskError, match="expired"):
        store.redeem_invitation(token)


def test_the_token_is_stored_hashed_not_readable(store):
    person = _add(store, "New", "new@firm.test")
    token = store.issue_invitation(person.id)

    with store.connect() as conn:
        rows = conn.execute("SELECT token_hash FROM invitations").fetchall()
    assert token not in {r["token_hash"] for r in rows}
    assert st._hash_token(token) in {r["token_hash"] for r in rows}


def test_an_unknown_token_is_a_sentence_not_a_crash(store):
    with pytest.raises(st.DeskError, match="not recognised"):
        store.redeem_invitation("nonsense")


# ── enrolment and sessions ──────────────────────────────────────────────────


def test_enrolling_a_passkey_makes_the_person_active(store):
    person = _add(store, "New", "new@firm.test")
    assert person.status == "invited"

    store.add_credential(
        person.id, credential_id="cred-1", public_key=b"key", algorithm=-7
    )

    refreshed = store.get_person(person.id)
    assert refreshed is not None
    assert refreshed.status == "active"
    assert refreshed.enrolled_at is not None
    assert len(store.credentials_for(person.id)) == 1


def test_a_person_with_no_credential_has_no_way_in(store):
    person = _add(store, "New", "new@firm.test")
    assert store.credentials_for(person.id) == []


def test_a_session_resolves_to_its_person_and_expires(store, monkeypatch):
    person = _add(store, "New", "new@firm.test")
    store.add_credential(person.id, credential_id="c", public_key=b"k", algorithm=-7)
    token = store.open_session(person.id)

    assert store.resolve_session(token).id == person.id

    later = st._now() + st.SESSION_TTL_SECONDS + 1
    monkeypatch.setattr(st, "_now", lambda: later)
    assert store.resolve_session(token) is None


def test_activity_slides_the_expiry(store, monkeypatch):
    """A quarter of an hour of *idle* time locks the desk, not fifteen minutes of use."""
    person = _add(store, "New", "new@firm.test")
    store.add_credential(person.id, credential_id="c", public_key=b"k", algorithm=-7)
    token = store.open_session(person.id)

    clock = {"now": st._now()}
    monkeypatch.setattr(st, "_now", lambda: clock["now"])

    for _ in range(4):
        clock["now"] += st.SESSION_TTL_SECONDS - 30
        assert store.resolve_session(token) is not None

    clock["now"] += st.SESSION_TTL_SECONDS + 1
    assert store.resolve_session(token) is None


def test_an_unknown_session_token_is_nobody(store):
    assert store.resolve_session("") is None
    assert store.resolve_session("made-up") is None


def test_suspending_a_person_kills_their_live_sessions_at_once(store):
    """Suspension has to bite on the next request, not the next login."""
    person = _add(store, "New", "new@firm.test")
    store.add_credential(person.id, credential_id="c", public_key=b"k", algorithm=-7)
    token = store.open_session(person.id)
    assert store.resolve_session(token) is not None

    store.set_status(person.id, "suspended")

    assert store.resolve_session(token) is None
    assert store.session_count() == 0


def test_revoking_all_passkeys_kills_sessions_and_credentials(store):
    person = _add(store, "New", "new@firm.test")
    store.add_credential(person.id, credential_id="c", public_key=b"k", algorithm=-7)
    store.open_session(person.id)

    store.revoke_all_credentials(person.id, by=person.id)

    assert store.credentials_for(person.id) == []
    assert store.session_count() == 0


# ── the record ──────────────────────────────────────────────────────────────


def test_every_admission_and_sign_in_is_written_to_the_audit_trail(store):
    person = _add(store, "New", "new@firm.test")
    store.add_credential(person.id, credential_id="c", public_key=b"k", algorithm=-7)
    store.open_session(person.id)

    actions = [row["action"] for row in store.audit_log()]
    for expected in ("person_admitted", "passkey_enrolled", "signed_in"):
        assert expected in actions


def test_no_column_anywhere_can_hold_a_password(store):
    """An invariant, not a style preference: there is nothing here to steal."""
    with store.connect() as conn:
        tables = [
            r["name"]
            for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        ]
        for table in tables:
            columns = [
                r["name"].lower()
                for r in conn.execute(f"PRAGMA table_info({table})").fetchall()
            ]
            for column in columns:
                assert "password" not in column, f"{table}.{column}"
                assert column not in ("password_hash", "pwd", "secret")


# ── conversations ───────────────────────────────────────────────────────────


def test_a_private_thread_is_only_readable_by_its_owner(store):
    owner = _add(store, "Owner", "owner@firm.test", role="partner")
    other = _add(store, "Other", "other@firm.test")

    conv = store.ensure_conversation(person=owner)
    assert store.conversation(conv["id"], person=owner) is not None
    assert store.conversation(conv["id"], person=other) is None


def test_ensure_conversation_is_idempotent(store):
    person = _add(store, "Owner", "owner@firm.test", role="partner")
    first = store.ensure_conversation(person=person)
    second = store.ensure_conversation(person=person)
    assert first["id"] == second["id"]


def test_messages_round_trip_with_citations(store):
    person = _add(store, "Owner", "owner@firm.test", role="partner")
    conv = store.ensure_conversation(person=person)

    store.append_message(
        conv["id"], role="user", content="What is Hargreaves' year end?", person_id=person.id
    )
    store.append_message(
        conv["id"],
        role="assistant",
        content="31 March.",
        cites=["clients/hargreaves.md:4"],
        unsettled=["no confirmation of the 2026 change"],
    )

    rows = store.messages(conv["id"])
    assert [r["role"] for r in rows] == ["user", "assistant"]
    assert rows[1]["cites"] == ["clients/hargreaves.md:4"]
    assert rows[1]["unsettled"] == ["no confirmation of the 2026 change"]
