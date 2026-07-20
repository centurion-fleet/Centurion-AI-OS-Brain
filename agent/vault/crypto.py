"""Vault crypto — passphrase unlock, AES-256-GCM seal, Scrypt KDF.

Threat model (honest):
  Protects cold disk / backups / other local users while locked.
  Does NOT protect against root or malware while unlocked (DEK in RAM).
"""

from __future__ import annotations

import json
import os
import secrets
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

from agent.vault.paths import ensure_vault_dir, secure_file, wrapped_key_path

KEY_FILE_VERSION = 1
DEK_BYTES = 32
NONCE_BYTES = 12
SALT_BYTES = 16
# Moderate Scrypt params — intentional unlock cost without multi-second waits in tests.
SCRYPT_N = 2**14
SCRYPT_R = 8
SCRYPT_P = 1


class VaultCryptoError(Exception):
    """Base Vault crypto error."""


class VaultLockedError(VaultCryptoError):
    """Raised when an operation requires an unlocked Vault."""


class VaultAuthError(VaultCryptoError):
    """Wrong passphrase or corrupted key material."""


@dataclass
class LockState:
    """In-memory DEK. Never written to disk."""

    dek: bytes
    unlocked: bool = True

    def zeroize(self) -> None:
        if self.dek:
            # Overwrite then drop reference
            mutable = bytearray(self.dek)
            for i in range(len(mutable)):
                mutable[i] = 0
            self.dek = bytes(mutable)
        self.unlocked = False


def _derive_kek(passphrase: str, salt: bytes, n: int, r: int, p: int) -> bytes:
    kdf = Scrypt(salt=salt, length=DEK_BYTES, n=n, r=r, p=p)
    return kdf.derive(passphrase.encode("utf-8"))


def _wrap_dek(kek: bytes, dek: bytes) -> tuple[bytes, bytes]:
    nonce = secrets.token_bytes(NONCE_BYTES)
    aesgcm = AESGCM(kek)
    wrapped = aesgcm.encrypt(nonce, dek, b"vault-dek-v1")
    return nonce, wrapped


def _unwrap_dek(kek: bytes, nonce: bytes, wrapped: bytes) -> bytes:
    aesgcm = AESGCM(kek)
    try:
        return aesgcm.decrypt(nonce, wrapped, b"vault-dek-v1")
    except Exception as exc:
        raise VaultAuthError("Wrong passphrase or corrupted vault key") from exc


def init_key(passphrase: str, path: Optional[Path] = None) -> LockState:
    """Create a new wrapped DEK file. Fails if key already exists."""
    ensure_vault_dir()
    key_path = path or wrapped_key_path()
    if key_path.exists():
        raise VaultCryptoError(f"Vault key already exists at {key_path}")
    if not passphrase or len(passphrase) < 8:
        raise VaultCryptoError("Passphrase must be at least 8 characters")

    salt = secrets.token_bytes(SALT_BYTES)
    dek = secrets.token_bytes(DEK_BYTES)
    kek = _derive_kek(passphrase, salt, SCRYPT_N, SCRYPT_R, SCRYPT_P)
    wrap_nonce, wrapped = _wrap_dek(kek, dek)

    payload = {
        "version": KEY_FILE_VERSION,
        "kdf": "scrypt",
        "n": SCRYPT_N,
        "r": SCRYPT_R,
        "p": SCRYPT_P,
        "salt": salt.hex(),
        "wrap_nonce": wrap_nonce.hex(),
        "wrapped_dek": wrapped.hex(),
    }
    tmp = key_path.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, key_path)
    secure_file(key_path)
    return LockState(dek=dek, unlocked=True)


def unlock(passphrase: str, path: Optional[Path] = None) -> LockState:
    """Unlock Vault by unwrapping the DEK into memory."""
    key_path = path or wrapped_key_path()
    if not key_path.exists():
        raise VaultCryptoError(
            "Vault not initialized. Run: centurion vault init"
        )
    try:
        payload = json.loads(key_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise VaultCryptoError("Unreadable vault key file") from exc

    salt = bytes.fromhex(payload["salt"])
    wrap_nonce = bytes.fromhex(payload["wrap_nonce"])
    wrapped = bytes.fromhex(payload["wrapped_dek"])
    n = int(payload.get("n", SCRYPT_N))
    r = int(payload.get("r", SCRYPT_R))
    p = int(payload.get("p", SCRYPT_P))

    kek = _derive_kek(passphrase, salt, n, r, p)
    dek = _unwrap_dek(kek, wrap_nonce, wrapped)
    return LockState(dek=dek, unlocked=True)


def change_passphrase(
    old_passphrase: str,
    new_passphrase: str,
    path: Optional[Path] = None,
) -> None:
    """Rewrap the same DEK under a new passphrase (no row re-encrypt)."""
    if not new_passphrase or len(new_passphrase) < 8:
        raise VaultCryptoError("New passphrase must be at least 8 characters")
    key_path = path or wrapped_key_path()
    state = unlock(old_passphrase, path=key_path)
    salt = secrets.token_bytes(SALT_BYTES)
    kek = _derive_kek(new_passphrase, salt, SCRYPT_N, SCRYPT_R, SCRYPT_P)
    wrap_nonce, wrapped = _wrap_dek(kek, state.dek)
    payload = {
        "version": KEY_FILE_VERSION,
        "kdf": "scrypt",
        "n": SCRYPT_N,
        "r": SCRYPT_R,
        "p": SCRYPT_P,
        "salt": salt.hex(),
        "wrap_nonce": wrap_nonce.hex(),
        "wrapped_dek": wrapped.hex(),
    }
    tmp = key_path.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, key_path)
    secure_file(key_path)
    state.zeroize()


def seal(dek: bytes, plaintext: bytes, aad: bytes = b"") -> tuple[bytes, bytes]:
    """Encrypt plaintext with AES-256-GCM. Returns (nonce, ciphertext+tag)."""
    nonce = secrets.token_bytes(NONCE_BYTES)
    aesgcm = AESGCM(dek)
    ciphertext = aesgcm.encrypt(nonce, plaintext, aad)
    return nonce, ciphertext


def unseal(dek: bytes, nonce: bytes, ciphertext: bytes, aad: bytes = b"") -> bytes:
    """Decrypt AES-256-GCM ciphertext."""
    aesgcm = AESGCM(dek)
    try:
        return aesgcm.decrypt(nonce, ciphertext, aad)
    except Exception as exc:
        raise VaultCryptoError("Decryption failed — integrity check failed") from exc


def require_unlocked(state: Optional[LockState]) -> LockState:
    if state is None or not state.unlocked or not state.dek:
        raise VaultLockedError("Vault is locked. Unlock with: centurion vault unlock")
    return state
