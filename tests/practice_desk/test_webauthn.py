"""WebAuthn verified against a software authenticator.

There is no browser in this loop, so the ceremony is built by hand exactly as a
platform authenticator builds it: same COSE key layout, same authData ordering,
same DER signature over `authData || SHA-256(clientDataJSON)`. If this passes,
the verifier is checking real cryptography rather than parsing strings happily.

Every refusal is tested by breaking exactly one thing, so a check that quietly
stopped firing is caught by the one test that expects it to fire.
"""

from __future__ import annotations

import hashlib
import json
import secrets

import cbor2
import pytest
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec

from centurion_cli.practice_desk import webauthn as w

RP_ID = "desk.practice.test"
ORIGIN = f"https://{RP_ID}"


class SoftwareAuthenticator:
    """A P-256 platform authenticator, enough of one to be honest."""

    def __init__(self, *, algs: int = w.ALG_ES256) -> None:
        self.key = ec.generate_private_key(ec.SECP256R1())
        self.credential_id = secrets.token_bytes(24)
        self.sign_count = 0

    def cose_key(self) -> bytes:
        numbers = self.key.public_key().public_numbers()
        return cbor2.dumps(
            {
                1: 2,  # kty: EC2
                3: w.ALG_ES256,
                -1: 1,  # crv: P-256
                -2: numbers.x.to_bytes(32, "big"),
                -3: numbers.y.to_bytes(32, "big"),
            }
        )

    def auth_data(self, *, attested: bool, rp_id: str = RP_ID, uv: bool = True,
                  sign_count: int | None = None) -> bytes:
        count = self.sign_count if sign_count is None else sign_count
        flags = w.FLAG_USER_PRESENT | (w.FLAG_ATTESTED if attested else 0)
        if uv:
            flags |= w.FLAG_USER_VERIFIED
        out = hashlib.sha256(rp_id.encode()).digest() + bytes([flags])
        out += count.to_bytes(4, "big")
        if attested:
            out += b"\x00" * 16
            out += len(self.credential_id).to_bytes(2, "big")
            out += self.credential_id
            out += self.cose_key()
        return out

    # ── registration ────────────────────────────────────────────────────────

    def registration(self, challenge: bytes, *, origin: str = ORIGIN,
                     rp_id: str = RP_ID, uv: bool = True) -> dict:
        auth_data = self.auth_data(attested=True, rp_id=rp_id, uv=uv)
        attestation = cbor2.dumps(
            {"fmt": "none", "attStmt": {}, "authData": auth_data}
        )
        client_data = json.dumps(
            {
                "type": "webauthn.create",
                "challenge": w.b64url_encode(challenge),
                "origin": origin,
            }
        ).encode()
        return {
            "client_data_json": client_data,
            "attestation_object": attestation,
        }

    # ── assertion ───────────────────────────────────────────────────────────

    def assertion(self, challenge: bytes, *, origin: str = ORIGIN,
                  rp_id: str = RP_ID, uv: bool = True,
                  bump: int = 1) -> dict:
        self.sign_count += bump
        auth_data = self.auth_data(attested=False, rp_id=rp_id, uv=uv,
                                   sign_count=self.sign_count)
        client_data = json.dumps(
            {
                "type": "webauthn.get",
                "challenge": w.b64url_encode(challenge),
                "origin": origin,
            }
        ).encode()
        client_hash = hashlib.sha256(client_data).digest()
        signature = self.key.sign(auth_data + client_hash, ec.ECDSA(hashes.SHA256()))
        return {
            "client_data_json": client_data,
            "authenticator_data": auth_data,
            "signature": signature,
        }


@pytest.fixture()
def authenticator() -> SoftwareAuthenticator:
    return SoftwareAuthenticator()


def _register(auth: SoftwareAuthenticator, challenge: bytes) -> w.RegisteredCredential:
    reg = auth.registration(challenge)
    return w.verify_registration(
        client_data_json=reg["client_data_json"],
        attestation_object=reg["attestation_object"],
        expected_challenge=challenge,
        expected_origin=ORIGIN,
        rp_id=RP_ID,
    )


# ── the happy path ──────────────────────────────────────────────────────────


def test_registration_yields_a_usable_credential(authenticator):
    challenge = secrets.token_bytes(32)
    cred = _register(authenticator, challenge)

    assert cred.algorithm == w.ALG_ES256
    assert cred.user_verified is True
    # The credential id is base64url of exactly what the authenticator chose.
    assert w.b64url_decode(cred.credential_id) == authenticator.credential_id
    # And the stored key really is the authenticator's key.
    key, alg = w.public_key_from_cose(cred.public_key)
    assert alg == w.ALG_ES256
    assert key.public_numbers() == authenticator.key.public_key().public_numbers()


def test_assertion_verifies_and_returns_the_new_counter(authenticator):
    challenge = secrets.token_bytes(32)
    cred = _register(authenticator, challenge)

    login_challenge = secrets.token_bytes(32)
    assertion = authenticator.assertion(login_challenge, bump=3)

    result = w.verify_assertion(
        client_data_json=assertion["client_data_json"],
        authenticator_data=assertion["authenticator_data"],
        signature=assertion["signature"],
        stored_public_key=cred.public_key,
        stored_sign_count=cred.sign_count,
        expected_challenge=login_challenge,
        expected_origin=ORIGIN,
        rp_id=RP_ID,
    )
    assert result.sign_count == 3
    assert result.user_verified is True


def test_synced_passkey_that_always_reports_zero_can_still_log_in(authenticator):
    """Most iCloud and Google passkeys never increment. A strict '>' locks them out."""
    challenge = secrets.token_bytes(32)
    cred = _register(authenticator, challenge)

    login_challenge = secrets.token_bytes(32)
    assertion = authenticator.assertion(login_challenge, bump=0)

    result = w.verify_assertion(
        client_data_json=assertion["client_data_json"],
        authenticator_data=assertion["authenticator_data"],
        signature=assertion["signature"],
        stored_public_key=cred.public_key,
        stored_sign_count=0,
        expected_challenge=login_challenge,
        expected_origin=ORIGIN,
        rp_id=RP_ID,
    )
    assert result.sign_count == 0


# ── every step refuses when broken ──────────────────────────────────────────


def test_wrong_challenge_is_refused(authenticator):
    reg = authenticator.registration(secrets.token_bytes(32))
    with pytest.raises(w.WebAuthnError, match="expired"):
        w.verify_registration(
            client_data_json=reg["client_data_json"],
            attestation_object=reg["attestation_object"],
            expected_challenge=secrets.token_bytes(32),
            expected_origin=ORIGIN,
            rp_id=RP_ID,
        )


def test_wrong_origin_is_refused(authenticator):
    """A lookalike domain must not pass. The origin check is exact, not prefix."""
    challenge = secrets.token_bytes(32)
    reg = authenticator.registration(challenge, origin="https://desk.practice.test.evil.com")
    with pytest.raises(w.WebAuthnError, match="not from this desk"):
        w.verify_registration(
            client_data_json=reg["client_data_json"],
            attestation_object=reg["attestation_object"],
            expected_challenge=challenge,
            expected_origin=ORIGIN,
            rp_id=RP_ID,
        )


def test_wrong_relying_party_is_refused(authenticator):
    challenge = secrets.token_bytes(32)
    reg = authenticator.registration(challenge, rp_id="other.practice.test")
    with pytest.raises(w.WebAuthnError, match="different address"):
        w.verify_registration(
            client_data_json=reg["client_data_json"],
            attestation_object=reg["attestation_object"],
            expected_challenge=challenge,
            expected_origin=ORIGIN,
            rp_id=RP_ID,
        )


def test_attestation_without_user_verification_is_refused(authenticator):
    """Presence alone is not a named user's credential."""
    challenge = secrets.token_bytes(32)
    reg = authenticator.registration(challenge, uv=False)
    with pytest.raises(w.WebAuthnError, match="did not confirm it was you"):
        w.verify_registration(
            client_data_json=reg["client_data_json"],
            attestation_object=reg["attestation_object"],
            expected_challenge=challenge,
            expected_origin=ORIGIN,
            rp_id=RP_ID,
        )


def test_tampered_signature_is_refused(authenticator):
    challenge = secrets.token_bytes(32)
    cred = _register(authenticator, challenge)
    login_challenge = secrets.token_bytes(32)
    assertion = authenticator.assertion(login_challenge)

    signature = bytearray(assertion["signature"])
    signature[-1] ^= 0xFF

    with pytest.raises(w.WebAuthnError, match="did not sign correctly"):
        w.verify_assertion(
            client_data_json=assertion["client_data_json"],
            authenticator_data=assertion["authenticator_data"],
            signature=bytes(signature),
            stored_public_key=cred.public_key,
            stored_sign_count=cred.sign_count,
            expected_challenge=login_challenge,
            expected_origin=ORIGIN,
            rp_id=RP_ID,
        )


def test_a_different_authenticators_signature_is_refused(authenticator):
    """A stolen credential id is useless without the private key."""
    challenge = secrets.token_bytes(32)
    cred = _register(authenticator, challenge)

    impostor = SoftwareAuthenticator()
    login_challenge = secrets.token_bytes(32)
    assertion = impostor.assertion(login_challenge)

    with pytest.raises(w.WebAuthnError):
        w.verify_assertion(
            client_data_json=assertion["client_data_json"],
            authenticator_data=assertion["authenticator_data"],
            signature=assertion["signature"],
            stored_public_key=cred.public_key,
            stored_sign_count=0,
            expected_challenge=login_challenge,
            expected_origin=ORIGIN,
            rp_id=RP_ID,
        )


def test_counter_going_backwards_is_refused_as_a_cloned_key(authenticator):
    challenge = secrets.token_bytes(32)
    cred = _register(authenticator, challenge)
    login_challenge = secrets.token_bytes(32)
    assertion = authenticator.assertion(login_challenge, bump=1)

    with pytest.raises(w.WebAuthnError, match="should not have been"):
        w.verify_assertion(
            client_data_json=assertion["client_data_json"],
            authenticator_data=assertion["authenticator_data"],
            signature=assertion["signature"],
            stored_public_key=cred.public_key,
            stored_sign_count=5,          # we have seen it at five already
            expected_challenge=login_challenge,
            expected_origin=ORIGIN,
            rp_id=RP_ID,
        )


def test_an_unsupported_key_type_is_refused_rather_than_assumed_safe():
    cose = cbor2.dumps({1: 1, 3: -8})   # kty OKP, EdDSA — not supported here
    with pytest.raises(w.WebAuthnError, match="not supported"):
        w.public_key_from_cose(cose)


def test_garbage_in_the_attestation_object_is_a_sentence_not_a_traceback():
    with pytest.raises(w.WebAuthnError):
        w.verify_registration(
            client_data_json=json.dumps(
                {
                    "type": "webauthn.create",
                    "challenge": w.b64url_encode(b"x"),
                    "origin": ORIGIN,
                }
            ).encode(),
            attestation_object=b"\xff\xff\xff",
            expected_challenge=b"x",
            expected_origin=ORIGIN,
            rp_id=RP_ID,
        )


def test_options_offered_to_the_browser_ask_for_a_device_passkey():
    """residentKey required is what makes it a passkey rather than a second factor."""
    opts = w.registration_options(
        rp_id=RP_ID,
        rp_name="Practice Desk",
        challenge=b"c" * 32,
        user_id=b"u" * 16,
        user_name="a@b.test",
        display_name="A B",
    )
    assert opts["authenticatorSelection"]["residentKey"] == "required"
    assert opts["authenticatorSelection"]["userVerification"] == "required"
    assert opts["attestation"] == "none"
    assert [p["alg"] for p in opts["pubKeyCredParams"]] == [w.ALG_ES256, w.ALG_RS256]
