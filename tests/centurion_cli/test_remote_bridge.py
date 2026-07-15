from centurion_cli.remote_bridge import handle_request


def test_remote_bridge_rejects_empty_message():
    result = handle_request({"id": "request-1", "text": "   "}, run_agent=lambda _: "")

    assert result == {
        "id": "request-1",
        "ok": False,
        "error": "Message text is required.",
    }


def test_remote_bridge_returns_agent_response():
    result = handle_request(
        {"id": "request-2", "text": " Hello "},
        run_agent=lambda prompt: f"Reply to: {prompt}",
    )

    assert result == {
        "id": "request-2",
        "ok": True,
        "text": "Reply to: Hello",
    }


def test_remote_bridge_remote_model_catalog_action():
    result = handle_request({"id": "catalog-1", "action": "remote_model_catalog"})

    assert result["id"] == "catalog-1"
    assert result["ok"] is True
    assert "catalog" in result
    assert result["catalog"]["text_models"]


def test_remote_bridge_routing_mode_round_trip():
    result = handle_request(
        {"id": "route-1", "action": "remote_routing_mode", "mode": "phoenix"}
    )
    assert result["ok"] is True
    assert result["routing_mode"] == "phoenix"

    current = handle_request({"id": "route-2", "action": "remote_routing_mode"})
    assert current["routing_mode"] == "phoenix"


def test_remote_bridge_surfaces_agent_failure():
    def fail(_: str) -> str:
        raise RuntimeError("provider unavailable")

    result = handle_request({"id": "request-3", "text": "Hello"}, run_agent=fail)

    assert result["id"] == "request-3"
    assert result["ok"] is False


def test_remote_bridge_main_stdout_is_parseable_json():
    import json
    import subprocess
    import sys

    payload = json.dumps({"id": "request-4", "text": "Hello"})
    completed = subprocess.run(
        [sys.executable, "-m", "centurion_cli.remote_bridge"],
        input=payload,
        text=True,
        capture_output=True,
        check=False,
    )

    parsed = json.loads(completed.stdout.strip())
    assert parsed["id"] == "request-4"
    assert "ok" in parsed
