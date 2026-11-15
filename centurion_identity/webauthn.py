"""WebAuthn, the subset a practice desk needs, with no third-party dependency.

Why written rather than imported: `fido2` and `py_webauthn` are not installed on
this machine, and adding a dependency to the appliance for two ceremonies is a
supply-chain decision on a box that holds a practice's client files. The whole
surface we use is four checks and one signature — small enough to own, and small
enough to test against a software authenticator.

What is verified, in this order, and every step refuses rather than warns:

1. `clientData.type` matches the ceremony.
2. `clientData.challenge` equals the challenge the server issued (compared after
   base64url decoding, so a padding difference cannot pass).
3. `clientData.origin` equals the configured origin — **exactly**, because an
   origin check that accepts a prefix accepts a lookalike domain.
4. `authData.rpIdHash` equals SHA-256 of the configured relying-party ID.
5. The user-presence bit is set, and (by default) the user-verification bit too:
   a presence-only credential is not a *named* user's credential.
6. Registration: the attested credential ID is present and the COSE key parses.
7. Assertion: the signature verifies over `authData || SHA-256(clientDataJSON)`,
   using the stored public key.
8. The signature counter has not gone backwards (with the spec's carve-out for
   authenticators that always report zero — most synced passkeys do, and a
   strict `>` would lock every one of those users out).

Algorithms supported: ES256 (-7) and RS256 (-257). Those are what platform
authenticators and security keys actually offer.
"""

from __future__ import annotations

import base64
import hashlib
import json
from dataclasses import dataclass
from typing import Any, Dict, Optional

import cbor2
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature

ALG_ES256 = -7
ALG_RS256 = -257

FLAG_USER_PRESENT = 0x01
FLAG_USER_VERIFIED = 0x04
FLAG_ATTESTED = 0x40
FLAG_EXTENSION_DATA = 0x80


class WebAuthnError(Exception):
    """A refusal with a sentence a human can act on. Never a bare exception."""


@dataclass
class RegisteredCredential:
    credential_id: str          # base64url, as the browser will send it
    public_key: bytes           # the COSE key, stored whole
    algorithm: int              # COSE alg, e.g. -7
    sign_count: int
    user_verified: bool


@dataclass
class AssertionResult:
    credential_id: str
    sign_count: int
    user_verified: bool


# ── encoding helpers ────────────────────────────────────────────────────────


def b64url_decode(value: str) -> bytes:
    """Forgiving about padding, strict about content."""
    if isinstance(value, bytes):
        value = value.decode("ascii")
    value = value.strip()
    pad = "=" * (-len(value) % 4)
    try:
        return base64.urlsafe_b64decode(value + pad)
    except Exception as exc:  # noqa: BLE001 — every failure is the same refusal
        raise WebAuthnError("That credential is not readable.") from exc


def b64url_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


# ── authData ────────────────────────────────────────────────────────────────


@dataclass
class AuthData:
    rp_id_hash: bytes
    flags: int
    sign_count: int
    aaguid: Optional[bytes]
    credential_id: Optional[bytes]
    credential_public_key: Optional[bytes]
    raw: bytes

    @property
    def user_present(self) -> bool:
        return bool(self.flags & FLAG_USER_PRESENT)

    @property
    def user_verified(self) -> bool:
        return bool(self.flags & FLAG_USER_VERIFIED)

    @property
    def has_attested_credential(self) -> bool:
        return bool(self.flags & FLAG_ATTESTED)


def parse_auth_data(raw: bytes) -> AuthData:
    if len(raw) < 37:
        raise WebAuthnError("The authenticator's response is too short to read.")
    rp_id_hash = raw[0:32]
    flags = raw[32]
    sign_count = int.from_bytes(raw[33:37], "big")
    aaguid = credential_id = public_key = None
    if flags & FLAG_ATTESTED:
        if len(raw) < 55:
            raise WebAuthnError("The authenticator's response is missing its key.")
        aaguid = raw[37:53]
        cred_len = int.from_bytes(raw[53:55], "big")
        start = 55
        end = start + cred_len
        if len(raw) < end:
            raise WebAuthnError("The authenticator's response is truncated.")
        credential_id = raw[start:end]
        rest = raw[end:]
        if rest:
            # The COSE key is the last structure; extension data, if present,
            # follows it, so decode only the first object.
            try:
                _, offset = _first_cbor(rest)
                public_key = rest[:offset]
            except Exception as exc:  # noqa: BLE001
                raise WebAuthnError("The authenticator's public key is not readable.") from exc
    return AuthData(
        rp_id_hash=rp_id_hash,
        flags=flags,
        sign_count=sign_count,
        aaguid=aaguid,
        credential_id=credential_id,
        credential_public_key=public_key,
        raw=raw,
    )


def _first_cbor(raw: bytes) -> tuple[Any, int]:
    """Decode the first CBOR item and report how many bytes it used."""
    from io import BytesIO

    stream = BytesIO(raw)
    obj = cbor2.load(stream)
    return obj, stream.tell()


# ── COSE key → cryptography public key ──────────────────────────────────────


COSE_KTY = 1
COSE_ALG = 3
COSE_CRV = -1
COSE_X = -2
COSE_Y = -3
COSE_N = -1
COSE_E = -2

KTY_EC2 = 2
KTY_RSA = 3
CRV_P256 = 1


def public_key_from_cose(cose_bytes: bytes):
    """Returns (cryptography_public_key, algorithm)."""
    try:
        cose = cbor2.loads(cose_bytes)
    except Exception as exc:  # noqa: BLE001
        raise WebAuthnError("The stored passkey is not readable.") from exc
    if not isinstance(cose, dict):
        raise WebAuthnError("The stored passkey is malformed.")

    alg = cose.get(COSE_ALG)
    kty = cose.get(COSE_KTY)

    if kty == KTY_EC2 and alg == ALG_ES256:
        if cose.get(COSE_CRV) != CRV_P256:
            raise WebAuthnError("Only P-256 passkeys are accepted on this machine.")
        x = cose.get(COSE_X)
        y = cose.get(COSE_Y)
        if not isinstance(x, (bytes, bytearray)) or not isinstance(y, (bytes, bytearray)):
            raise WebAuthnError("The stored passkey has no point.")
        numbers = ec.EllipticCurvePublicNumbers(
            int.from_bytes(bytes(x), "big"),
            int.from_bytes(bytes(y), "big"),
            ec.SECP256R1(),
        )
        try:
            return numbers.public_key(), ALG_ES256
        except Exception as exc:  # noqa: BLE001
            raise WebAuthnError("The stored passkey's point is not on the curve.") from exc

    if kty == KTY_RSA and alg == ALG_RS256:
        n = cose.get(COSE_N)
        e = cose.get(COSE_E)
        if not isinstance(n, (bytes, bytearray)) or not isinstance(e, (bytes, bytearray)):
            raise WebAuthnError("The stored passkey has no modulus.")
        numbers = rsa.RSAPublicNumbers(
            int.from_bytes(bytes(e), "big"), int.from_bytes(bytes(n), "big")
        )
        try:
            return numbers.public_key(), ALG_RS256
        except Exception as exc:  # noqa: BLE001
            raise WebAuthnError("The stored passkey's modulus is not usable.") from exc

    raise WebAuthnError(
        "That kind of passkey is not supported here. Use a device passkey or a "
        "security key, not a password manager's software key."
    )


# ── clientData ──────────────────────────────────────────────────────────────


def verify_client_data(
    client_data_json: bytes,
    *,
    expected_type: str,
    expected_challenge: bytes,
    expected_origin: str,
    expected_rp_id: Optional[str] = None,
) -> bytes:
    """Returns SHA-256 of the raw clientDataJSON, which the signature covers."""
    if not client_data_json:
        raise WebAuthnError("The browser sent no client data.")
    try:
        data = json.loads(client_data_json.decode("utf-8"))
    except Exception as exc:  # noqa: BLE001
        raise WebAuthnError("The browser's client data is not readable.") from exc

    if data.get("type") != expected_type:
        raise WebAuthnError("That sign-in attempt was for the wrong ceremony.")

    try:
        challenge = b64url_decode(data.get("challenge", ""))
    except WebAuthnError:
        raise
    if not challenge or challenge != expected_challenge:
        # Constant-time comparison is unnecessary: this is a once-only random
        # value, not a secret being guessed against a stored one.
        raise WebAuthnError("That sign-in attempt has expired. Try again.")

    origin = data.get("origin", "")
    if origin != expected_origin:
        raise WebAuthnError(
            f"That sign-in came from {origin or 'an unknown page'}, not from this desk."
        )

    if expected_rp_id:
        # `crossOrigin` is only sent when true. A cross-origin ceremony is a
        # lookalike iframe and has no business on this machine.
        if data.get("crossOrigin") is True:
            raise WebAuthnError("That sign-in came from an embedded page, not this desk.")

    return hashlib.sha256(client_data_json).digest()


# ── the two ceremonies ──────────────────────────────────────────────────────


def verify_registration(
    *,
    client_data_json: bytes,
    attestation_object: bytes,
    expected_challenge: bytes,
    expected_origin: str,
    rp_id: str,
    require_user_verification: bool = True,
) -> RegisteredCredential:
    """Registration. Attestation is accepted but not evaluated.

    `fmt` is recorded and ignored beyond that: a practice desk is not running a
    supply-chain attestation policy across authenticator vendors, and pretending
    to check attestation while accepting `none` would be theatre.
    """
    verify_client_data(
        client_data_json,
        expected_type="webauthn.create",
        expected_challenge=expected_challenge,
        expected_origin=expected_origin,
        expected_rp_id=rp_id,
    )

    try:
        attestation = cbor2.loads(attestation_object)
    except Exception as exc:  # noqa: BLE001
        raise WebAuthnError("The authenticator's registration response is unreadable.") from exc
    if not isinstance(attestation, dict) or "authData" not in attestation:
        raise WebAuthnError("The authenticator's registration response is malformed.")

    auth = parse_auth_data(attestation["authData"])

    expected_rp_hash = hashlib.sha256(rp_id.encode("utf-8")).digest()
    if auth.rp_id_hash != expected_rp_hash:
        raise WebAuthnError("That passkey was created for a different address.")

    if not auth.user_present:
        raise WebAuthnError("The authenticator did not confirm a person was present.")
    if require_user_verification and not auth.user_verified:
        raise WebAuthnError(
            "That passkey did not confirm it was you — set a PIN or use device sign-in."
        )

    if not auth.has_attested_credential or not auth.credential_id or not auth.credential_public_key:
        raise WebAuthnError("The authenticator did not send a credential to register.")

    _, algorithm = public_key_from_cose(auth.credential_public_key)

    return RegisteredCredential(
        credential_id=b64url_encode(auth.credential_id),
        public_key=auth.credential_public_key,
        algorithm=algorithm,
        sign_count=auth.sign_count,
        user_verified=auth.user_verified,
    )


def verify_assertion(
    *,
    client_data_json: bytes,
    authenticator_data: bytes,
    signature: bytes,
    stored_public_key: bytes,
    stored_sign_count: int,
    expected_challenge: bytes,
    expected_origin: str,
    rp_id: str,
    require_user_verification: bool = True,
) -> AssertionResult:
    """Sign-in. Returns the new counter to store."""
    client_hash = verify_client_data(
        client_data_json,
        expected_type="webauthn.get",
        expected_challenge=expected_challenge,
        expected_origin=expected_origin,
        expected_rp_id=rp_id,
    )

    auth = parse_auth_data(authenticator_data)

    expected_rp_hash = hashlib.sha256(rp_id.encode("utf-8")).digest()
    if auth.rp_id_hash != expected_rp_hash:
        raise WebAuthnError("That sign-in was for a different address.")

    if not auth.user_present:
        raise WebAuthnError("The authenticator did not confirm a person was present.")
    if require_user_verification and not auth.user_verified:
        raise WebAuthnError("That passkey did not confirm it was you.")

    try:
        key, algorithm = public_key_from_cose(stored_public_key)
    except WebAuthnError:
        raise

    signed = auth.raw + client_hash

    # ⚠️ Sign/verify symmetric: `ECDSA(hashes.SHA256())` hashes the input once.
    # Passing a digest to it hashes twice and every signature fails — which is
    # what a Prehashed() wrapper exists to avoid.
    try:
        if algorithm == ALG_ES256:
            key.verify(signature, signed, ec.ECDSA(hashes.SHA256()))
        else:
            key.verify(signature, signed, padding.PKCS1v15(), hashes.SHA256())
    except InvalidSignature as exc:
        raise WebAuthnError("That passkey did not sign correctly. Try again.") from exc
    except Exception as exc:  # noqa: BLE001 — malformed DER and wrong key size land here
        raise WebAuthnError("That passkey's signature could not be checked.") from exc

    # Counter. Synced passkeys report 0 forever; the spec's rule is to skip the
    # comparison when either side is 0. A strict '>' would lock out every
    # iCloud/Google passkey on the first sign-in.
    new_count = auth.sign_count
    if stored_sign_count and new_count:
        if new_count <= stored_sign_count:
            raise WebAuthnError(
                "That passkey has been used somewhere it should not have been. "
                "Ask a partner to revoke it and issue a new one."
            )

    return AssertionResult(
        credential_id=b64url_encode(auth.credential_id or b""),
        sign_count=new_count,
        user_verified=auth.user_verified,
    )


# ── options the browser needs ───────────────────────────────────────────────


def registration_options(
    *, rp_id: str, rp_name: str, challenge: bytes, user_id: bytes, user_name: str,
    display_name: str, user_verification: str = "required",
) -> Dict[str, Any]:
    return {
        "challenge": b64url_encode(challenge),
        "rp": {"id": rp_id, "name": rp_name},
        "user": {
            "id": b64url_encode(user_id),
            "name": user_name,
            "displayName": display_name,
        },
        "pubKeyCredParams": [
            {"type": "public-key", "alg": ALG_ES256},
            {"type": "public-key", "alg": ALG_RS256},
        ],
        "timeout": 120000,
        "attestation": "none",
        # residentKey=required is the passkey form: the credential lives on the
        # device so a user does not have to type an email to be recognised.
        # userVerification decides whether a fingerprint and a PIN on a phone are
        # demanded, or whether the presence of a hardware key is enough. A
        # blue Security Key cannot verify a user at all; a YubiKey 5 can, once a
        # FIDO2 PIN is set. The Brain decides, not this function.
        "authenticatorSelection": {
            "residentKey": "required",
            "requireResidentKey": True,
            "userVerification": user_verification,
        },
        "excludeCredentials": [],
    }


def assertion_options(
    *, rp_id: str, challenge: bytes, allow_ids: list[str], user_verification: str = "required"
) -> Dict[str, Any]:
    return {
        "challenge": b64url_encode(challenge),
        "rpId": rp_id,
        "timeout": 120000,
        "userVerification": user_verification,
        "allowCredentials": [
            {"type": "public-key", "id": cid} for cid in allow_ids if cid
        ],
    }


def encode_signature_for_test(r: int, s: int) -> bytes:
    """DER-encode an ECDSA (r, s) pair. Used by the software authenticator in tests."""
    return encode_dss_signature(r, s)
