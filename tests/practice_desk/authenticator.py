"""A P-256 platform authenticator, in software, for tests.

Shared by the WebAuthn unit tests and the service tests so the ceremony the app
verifies is built exactly once, the same way in both places.
"""

from __future__ import annotations

import hashlib
import json
import secrets

import cbor2
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec

from centurion_cli.practice_desk import webauthn as w


class SoftwareAuthenticator:
    def __init__(self, rp_id: str = "localhost") -> None:
        self.key = ec.generate_private_key(ec.SECP256R1())
        self.credential_id = secrets.token_bytes(24)
        self.sign_count = 0
        self.rp_id = rp_id

    def cose_key(self) -> bytes:
        numbers = self.key.public_key().public_numbers()
        return cbor2.dumps(
            {
                1: 2,
                3: w.ALG_ES256,
                -1: 1,
                -2: numbers.x.to_bytes(32, "big"),
                -3: numbers.y.to_bytes(32, "big"),
            }
        )

    def auth_data(
        self, *, attested: bool, rp_id: str | None = None, uv: bool = True,
        sign_count: int | None = None,
    ) -> bytes:
        rp_id = rp_id or self.rp_id
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

    def registration(
        self, challenge: bytes, *, origin: str, rp_id: str | None = None, uv: bool = True
    ) -> dict:
        auth_data = self.auth_data(attested=True, rp_id=rp_id, uv=uv)
        return {
            "client_data_json": json.dumps(
                {
                    "type": "webauthn.create",
                    "challenge": w.b64url_encode(challenge),
                    "origin": origin,
                }
            ).encode(),
            "attestation_object": cbor2.dumps(
                {"fmt": "none", "attStmt": {}, "authData": auth_data}
            ),
        }

    def assertion(
        self, challenge: bytes, *, origin: str, rp_id: str | None = None,
        uv: bool = True, bump: int = 1,
    ) -> dict:
        self.sign_count += bump
        auth_data = self.auth_data(
            attested=False, rp_id=rp_id, uv=uv, sign_count=self.sign_count
        )
        client_data = json.dumps(
            {
                "type": "webauthn.get",
                "challenge": w.b64url_encode(challenge),
                "origin": origin,
            }
        ).encode()
        signature = self.key.sign(
            auth_data + hashlib.sha256(client_data).digest(), ec.ECDSA(hashes.SHA256())
        )
        return {
            "id": w.b64url_encode(self.credential_id),
            "clientDataJSON": w.b64url_encode(client_data),
            "authenticatorData": w.b64url_encode(auth_data),
            "signature": w.b64url_encode(signature),
        }
