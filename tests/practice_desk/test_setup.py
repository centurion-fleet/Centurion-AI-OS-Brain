"""First run: the practice is created by clicking, on a machine nobody has set up.

The rule these tests exist to hold is the owner's, not a preference:

    **No customer of Centurion should ever touch a terminal.**

Before this, the first partner could only be made with
`centurion practice-desk invite …` on the machine, because every other route to
creating a person requires a signed-in partner. That command was the single place
a customer had to open a terminal, and these tests close it.
"""

from __future__ import annotations

import asyncio
import datetime as _dt
from pathlib import Path

import pytest
from aiohttp.test_utils import TestClient, TestServer

from centurion_cli.practice_desk import app as desk_app
from centurion_cli.practice_desk import setup as desk_setup
from centurion_cli.practice_desk import store as st

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
        return f"{self.label} carries {self.seat_limit} named users."


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


# ── the gate ────────────────────────────────────────────────────────────────


def test_an_empty_machine_opens_the_wizard_not_a_sign_in_page(settings):
    """A sign-in page with nobody on the machine is a dead end, not a front door."""

    async def scenario():
        client = await _client(settings)
        try:
            response = await client.get("/", allow_redirects=False)
            assert response.status == 302
            assert response.headers["Location"] == "/setup"

            page = await (await client.get("/setup")).text()
            assert "This is your practice" in page
            assert "fingerprint" in page  # what signing in will mean, said plainly
            assert "password" in page
        finally:
            await client.close()

    run(scenario())


def test_clicking_through_setup_creates_the_first_partner(settings):
    """The whole point: a partner exists without a terminal being opened."""

    async def scenario():
        client = await _client(settings)
        try:
            response = await client.post(
                "/api/setup/practice",
                json={
                    "practice": "Courtwright & Co",
                    "name": "Margaret Courtwright",
                    "email": "margaret@courtwright.co.uk",
                },
            )
            assert response.status == 200, await response.text()
            payload = await response.json()

            assert payload["ok"] is True
            assert payload["practice"] == "Courtwright & Co"
            # A one-time claim link — the account is claimed by a passkey, not a
            # password, so there is nothing here to write down or to leak.
            assert "#invite=" in payload["link"]

            store: st.PracticeStore = client.server.app[desk_app.DESK_KEY].store
            people = store.list_people()
            assert len(people) == 1
            assert people[0].role == "partner"
            assert people[0].email == "margaret@courtwright.co.uk"
            assert desk_setup.practice_name(store) == "Courtwright & Co"
        finally:
            await client.close()

    run(scenario())


def test_after_setup_the_front_door_is_the_desk_again(settings):
    async def scenario():
        client = await _client(settings)
        try:
            await client.post(
                "/api/setup/practice",
                json={"practice": "Courtwright & Co", "name": "M", "email": "m@c.co.uk"},
            )
            response = await client.get("/", allow_redirects=False)
            assert response.status == 200
            assert "signin" in (await response.text()).lower()
        finally:
            await client.close()

    run(scenario())


def test_setup_cannot_be_run_twice_to_make_a_second_unauthorised_partner(settings):
    """Otherwise the wizard is a hole straight through people_invite."""

    async def scenario():
        client = await _client(settings)
        try:
            first = await client.post(
                "/api/setup/practice",
                json={"practice": "Courtwright & Co", "name": "M", "email": "m@c.co.uk"},
            )
            assert first.status == 200

            second = await client.post(
                "/api/setup/practice",
                json={"practice": "Someone Else", "name": "X", "email": "x@y.co.uk"},
            )
            assert second.status == 400
            assert "already set up" in (await second.text()).lower()

            store: st.PracticeStore = client.server.app[desk_app.DESK_KEY].store
            assert len(store.list_people()) == 1
        finally:
            await client.close()

    run(scenario())


def test_a_wizard_with_no_practice_name_writes_nothing_at_all(settings):
    async def scenario():
        client = await _client(settings)
        try:
            response = await client.post(
                "/api/setup/practice",
                json={"practice": "  ", "name": "Margaret", "email": "m@c.co.uk"},
            )
            assert response.status == 400
            store: st.PracticeStore = client.server.app[desk_app.DESK_KEY].store
            assert store.list_people() == []
        finally:
            await client.close()

    run(scenario())


def test_the_practice_name_is_carried_into_the_written_record(settings):
    async def scenario():
        client = await _client(settings)
        try:
            await client.post(
                "/api/setup/practice",
                json={"practice": "Courtwright  &  Co", "name": "M", "email": "m@c.co.uk"},
            )
            store: st.PracticeStore = client.server.app[desk_app.DESK_KEY].store
            # Whitespace collapsed, so the name cannot be used to fake a layout.
            assert desk_setup.practice_name(store) == "Courtwright & Co"

            with store.connect() as conn:
                row = conn.execute(
                    "SELECT action, detail FROM audit WHERE action = 'practice_set_up'"
                ).fetchone()
            assert row is not None and row["detail"] == "Courtwright & Co"
        finally:
            await client.close()

    run(scenario())


# ── the certificate the machine issues for itself ───────────────────────────


def test_the_machine_issues_its_own_certificate(tmp_path):
    """No `--tls-cert` anywhere in a customer's life."""
    tls = desk_setup.ensure_local_tls(
        tmp_path / "tls", names=["courtwright.local"], ips=["192.168.1.20"]
    )

    assert tls.created is True
    assert tls.cert.is_file() and tls.key.is_file() and tls.ca.is_file()
    # The private key is not world-readable.
    assert oct(tls.key.stat().st_mode)[-3:] == "600"

    from cryptography import x509

    leaf = x509.load_pem_x509_certificate(tls.cert.read_bytes())
    san = leaf.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
    assert "courtwright.local" in [n.lower() for n in san.get_values_for_type(x509.DNSName)]
    assert "192.168.1.20" in [str(i) for i in san.get_values_for_type(x509.IPAddress)]

    ca = x509.load_pem_x509_certificate(tls.ca.read_bytes())
    assert ca.extensions.get_extension_for_class(x509.BasicConstraints).value.ca is True
    # And it is actually signed by that CA, not merely shipped beside it.
    assert leaf.issuer == ca.subject


def test_the_certificate_is_reused_and_not_minted_on_every_boot(tmp_path):
    first = desk_setup.ensure_local_tls(tmp_path / "tls", names=["a.local"], ips=["10.0.0.5"])
    again = desk_setup.ensure_local_tls(tmp_path / "tls", names=["a.local"], ips=["10.0.0.5"])
    assert first.created is True
    assert again.created is False
    assert again.cert.read_bytes() == first.cert.read_bytes()


def test_a_certificate_is_reissued_when_the_practice_moves_address(tmp_path):
    desk_setup.ensure_local_tls(tmp_path / "tls", names=["a.local"], ips=["10.0.0.5"])
    moved = desk_setup.ensure_local_tls(tmp_path / "tls", names=["a.local"], ips=["10.0.0.99"])
    assert moved.created is True

    from cryptography import x509

    leaf = x509.load_pem_x509_certificate(moved.cert.read_bytes())
    san = leaf.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
    assert "10.0.0.99" in [str(i) for i in san.get_values_for_type(x509.IPAddress)]


def test_a_certificate_that_does_not_hold_the_name_is_replaced(tmp_path):
    """The reissue trigger, tested directly rather than by faking a clock.

    A leaf that does not name the address a colleague typed produces a browser
    warning, and the cover check is what makes that impossible to ship quietly.
    """
    tls = desk_setup.ensure_local_tls(tmp_path / "tls", names=["a.local"], ips=["10.0.0.5"])

    assert desk_setup._covers(tls.cert, ["a.local"], ["10.0.0.5"]) is True
    assert desk_setup._covers(tls.cert, ["b.other"], []) is False
    assert desk_setup._covers(tls.cert, [], ["10.0.0.6"]) is False
    # A file that is not a certificate is not a certificate.
    assert desk_setup._covers(tmp_path / "nothing.pem", ["a.local"], []) is False


def test_the_ca_is_downloadable_because_that_is_the_join_step(settings):
    """A colleague's machine trusts this one by installing this file."""

    async def scenario():
        client = await _client(settings)
        try:
            # No certificate yet on a loopback test install.
            missing = await client.get("/setup/ca.crt")
            assert missing.status == 404

            desk_setup.ensure_local_tls(
                Path(settings.db_path).parent / "tls",
                names=["localhost"],
                ips=["127.0.0.1"],
            )
            response = await client.get("/setup/ca.crt")
            assert response.status == 200
            assert b"BEGIN CERTIFICATE" in await response.read()
            assert "attachment" in response.headers["Content-Disposition"]
        finally:
            await client.close()

    run(scenario())


def test_the_wizard_shows_the_practice_name_it_was_given(settings):
    async def scenario():
        client = await _client(settings)
        try:
            await client.post(
                "/api/setup/practice",
                json={"practice": "Courtwright & Co", "name": "M", "email": "m@c.co.uk"},
            )
            store: st.PracticeStore = client.server.app[desk_app.DESK_KEY].store
            page = desk_setup.page(store)
            assert 'value="Courtwright &amp; Co"' in page
        finally:
            await client.close()

    run(scenario())


# ── the address the browser is on ───────────────────────────────────────────
# A passkey is bound to an RP ID and the browser only registers one when that
# ID is the address in the bar or a parent domain of it. A desk configured with
# a mismatched pair runs the whole wizard and then dies on the fingerprint
# prompt — the worst possible moment to fail. Refuse at startup instead.


def test_a_matching_pair_is_accepted():
    desk_app.Settings(rp_id="localhost", origin="http://localhost:8765", brain_url="")
    desk_app.Settings(
        rp_id="firm.co.uk", origin="https://desk.firm.co.uk", brain_url=""
    )


def test_a_passkey_bound_to_a_different_name_is_refused_before_it_serves():
    with pytest.raises(ValueError) as refused:
        # The live-run mistake: served on 127.0.0.1 but bound to "localhost".
        desk_app.Settings(
            rp_id="localhost", origin="http://127.0.0.1:9443", brain_url=""
        )
    message = str(refused.value)
    assert "--rp-id" in message and "--origin" in message
    assert "http://localhost:9443" in message  # tells you the fix, not just the fault


def test_a_bare_ip_cannot_be_pretended_into_a_domain_name():
    with pytest.raises(ValueError):
        desk_app.Settings(
            rp_id="192.168.10.109",
            origin="https://practice.firm.local:9443",
            brain_url="",
        )


# ── the address a colleague is given ────────────────────────────────────────
# A firm is never told "go to the desk" — it is given a string. On a network
# that string has to be a name: a browser will not bind a passkey to a bare IP,
# and 0.0.0.0 is not something a person types.


def _network_settings(tmp_path, monkeypatch, **over):
    import centurion.license.edition as edition_mod

    monkeypatch.setattr(edition_mod, "current_edition", lambda: FakeEdition(10))
    base = dict(
        rp_id="localhost",
        origin="http://localhost:8765",
        host="0.0.0.0",
        port=9445,
        brain_url="",
        db_path=tmp_path / "practice.db",
        tls_cert=None,
    )
    base.update(over)
    return desk_app.Settings(**base)


def test_serving_to_a_network_adopts_the_name_that_network_resolves(tmp_path, monkeypatch):
    import socket

    short = socket.gethostname().split(".")[0]
    made = _network_settings(tmp_path, monkeypatch)
    assert made.origin == f"http://{short}.local:9445"
    assert made.rp_id == f"{short}.local"


def test_the_port_in_the_address_is_the_port_it_serves_on(tmp_path, monkeypatch):
    import socket

    short = socket.gethostname().split(".")[0]
    made = _network_settings(tmp_path, monkeypatch, port=9446)
    assert made.origin.endswith(":9446")
    assert made.origin == f"http://{short}.local:9446"


def test_an_address_the_firm_typed_is_left_untouched(tmp_path, monkeypatch):
    made = _network_settings(
        tmp_path,
        monkeypatch,
        origin="https://desk.firm.co.uk:9443",
        rp_id="desk.firm.co.uk",
        port=9443,
    )
    assert made.origin == "https://desk.firm.co.uk:9443"
    assert made.rp_id == "desk.firm.co.uk"


def test_the_wizard_gives_a_colleague_the_string_to_type(tmp_path, monkeypatch):
    import socket

    short = socket.gethostname().split(".")[0]
    made = _network_settings(tmp_path, monkeypatch)
    made.origin = "https://" + made.origin[len("http://") :]

    async def scenario():
        client = await _client(made)
        try:
            page = await (await client.get("/setup")).text()
            assert f"{short}.local:9445" in page
            assert "%%ADDRESS%%" not in page
            assert "0.0.0.0" not in page
        finally:
            await client.close()

    run(scenario())


def test_a_loopback_desk_does_not_send_a_firm_to_127_0_0_1(settings):
    async def scenario():
        client = await _client(settings)
        try:
            page = await (await client.get("/setup")).text()
            assert "127.0.0.1" not in page
            assert "network name" in page
        finally:
            await client.close()

    run(scenario())
