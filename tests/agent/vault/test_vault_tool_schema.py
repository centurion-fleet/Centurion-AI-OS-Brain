"""Vault toolset / schema smoke tests."""

from tools.vault_tool import VAULT_SCHEMA, check_vault_requirements


def test_vault_schema_actions():
    assert VAULT_SCHEMA["name"] == "vault"
    actions = VAULT_SCHEMA["parameters"]["properties"]["action"]["enum"]
    for needed in ("status", "propose", "commit", "reject", "search", "get"):
        assert needed in actions


def test_vault_requirements():
    assert check_vault_requirements() is True
