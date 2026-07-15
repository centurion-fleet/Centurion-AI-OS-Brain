from centurion_cli.phoenix_router import resolve


def test_phoenix_routes_email_copy_to_sonnet():
    assert resolve("Please draft email copy for the newsletter") == "anthropic-sonnet-5"


def test_phoenix_routes_code_to_terra():
    assert resolve("refactor this module and debug the failing test") == "openai-terra"


def test_phoenix_routes_video_to_runway():
    assert resolve("generate video for a 30-second ad") == "runway-gen-4"


def test_phoenix_returns_none_for_unmatched():
    assert resolve("hello there") is None
