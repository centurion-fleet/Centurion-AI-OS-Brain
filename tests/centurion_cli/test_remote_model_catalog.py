from centurion_cli.remote_model_catalog import get_connector, iter_catalog, is_openrouter_blocked
from centurion_cli.provider_control import list_remote_options, apply_remote_switch


def test_remote_catalog_excludes_openrouter():
    for entry in iter_catalog():
        assert not is_openrouter_blocked(entry.provider)


def test_remote_catalog_has_text_and_creative_sections():
    payload = list_remote_options(probe=False)
    assert payload["text_models"]
    assert payload["creative_models"]
    assert all(row["category"] == "text" for row in payload["text_models"])
    assert all(row["category"] == "creative" for row in payload["creative_models"])


def test_apply_remote_switch_rejects_unknown_connector():
    result = apply_remote_switch("not-a-real-connector", probe=False)
    assert not result.ok


def test_get_connector_returns_catalog_entry():
    entry = get_connector("deepseek-v4-pro")
    assert entry is not None
    assert entry.provider == "deepseek"
