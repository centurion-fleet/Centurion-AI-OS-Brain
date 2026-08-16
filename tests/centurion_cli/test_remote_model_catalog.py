from centurion_cli.remote_model_catalog import get_connector, iter_catalog, is_openrouter_blocked
from centurion_cli.provider_control import list_remote_options, apply_remote_switch
from centurion_cli.models import get_picker_providers


def test_remote_catalog_excludes_openrouter():
    for entry in iter_catalog():
        assert not is_openrouter_blocked(entry.provider)
        # Direct OpenAI must use openai-api, never the OpenRouter-aliased "openai"
        if entry.key_env == "OPENAI_API_KEY":
            assert entry.provider == "openai-api"


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


def test_picker_hides_openrouter_and_subscription():
    slugs = {p.slug for p in get_picker_providers(billing_enabled=True)}
    assert "openrouter" not in slugs
    assert "nous" not in slugs
    assert "openai-api" in slugs or "anthropic" in slugs


def test_text_providers_include_signup_url():
    expected = {
        "OPENAI_API_KEY": "https://platform.openai.com/api-keys",
        "ANTHROPIC_API_KEY": "https://console.anthropic.com/settings/keys",
        "GEMINI_API_KEY": "https://aistudio.google.com/apikey",
        "DEEPSEEK_API_KEY": "https://platform.deepseek.com/api_keys",
        "XAI_API_KEY": "https://console.x.ai/",
    }
    payload = list_remote_options(probe=False)
    by_env = {row["key_env"]: row for row in payload["text_models"]}
    for key_env, url in expected.items():
        assert key_env in by_env
        assert by_env[key_env]["signup_url"] == url
