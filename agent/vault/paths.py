"""Profile-safe Vault paths under get_centurion_home()/vault/."""

from __future__ import annotations

import os
from pathlib import Path

from centurion_constants import get_centurion_home, secure_parent_dir

WRAPPED_KEY_NAME = "vault.key.wrapped"
DB_NAME = "vault.db"
AUDIT_NAME = "audit.log"
MODELS_DIR_NAME = "models"
DEFAULT_MODEL_FILENAME = "nomic-embed-text-v1.5.Q4_K_M.gguf"


def get_vault_dir() -> Path:
    """Return the profile-scoped Vault directory."""
    return get_centurion_home() / "vault"


def ensure_vault_dir() -> Path:
    """Create vault/ with 0o700 and return it."""
    vault_dir = get_vault_dir()
    vault_dir.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(vault_dir, 0o700)
    except OSError:
        pass
    secure_parent_dir(vault_dir / "dummy")
    return vault_dir


def db_path() -> Path:
    return get_vault_dir() / DB_NAME


def wrapped_key_path() -> Path:
    return get_vault_dir() / WRAPPED_KEY_NAME


def audit_path() -> Path:
    return get_vault_dir() / AUDIT_NAME


def models_dir() -> Path:
    return get_vault_dir() / MODELS_DIR_NAME


def model_path(filename: str = DEFAULT_MODEL_FILENAME) -> Path:
    return models_dir() / filename


def secure_file(path: Path) -> None:
    """Best-effort chmod 0o600 on a file."""
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
