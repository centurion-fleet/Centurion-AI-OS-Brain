import json

from centurion_cli.remote_bridge import handle_request


def test_remote_bridge_rejects_empty_message():
    result = handle_request({"id": "request-1", "text": "   "}, run_agent=lambda _: "")

    # The multiplexed action protocol (added alongside provider/support/remote
    # model catalog actions) stamps every response with its "action" plus a
    # structured error code/message/retryable triple — not just a bare error.
    assert result == {
        "id": "request-1",
        "ok": False,
        "action": "chat",
        "code": "INVALID_REQUEST",
        "error": "Message text is required.",
        "message": "Message text is required.",
        "retryable": False,
    }


def test_remote_bridge_returns_agent_response():
    result = handle_request(
        {"id": "request-2", "text": " Hello "},
        run_agent=lambda prompt: f"Reply to: {prompt}",
    )

    assert result == {
        "id": "request-2",
        "ok": True,
        "action": "chat",
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


def test_remote_bridge_save_key_does_not_echo_secret(monkeypatch):
    secret = "sk-bridge-secret-echo-check"

    monkeypatch.setattr(
        "centurion_cli.remote_bridge.save_remote_api_key",
        lambda connector_id, key: {
            "ok": True,
            "connector_id": connector_id,
            "configured": True,
            "message": "Saved access code for Claude Sonnet 4.6 on your Centurion.",
            # Deliberately include a bad field to ensure the handler strips it.
            "key": key,
        },
    )
    result = handle_request(
        {
            "id": "save-1",
            "action": "remote_model_save_key",
            "connector_id": "anthropic-sonnet-5",
            "key": secret,
        }
    )
    assert result["ok"] is True
    blob = json.dumps(result)
    assert secret not in blob
    assert "key" not in result.get("result", {})


def test_remote_bridge_gateway_status_action(monkeypatch):
    from types import SimpleNamespace

    monkeypatch.setattr(
        "centurion_cli.gateway.get_gateway_runtime_snapshot",
        lambda: SimpleNamespace(
            running=True,
            service_running=True,
            service_installed=True,
            manager="systemd (user)",
            gateway_pids=(1234,),
        ),
    )
    monkeypatch.setattr(
        "gateway.status.read_runtime_status",
        lambda: {"gateway_state": "running", "platforms": {"telegram": {"connected": True}}},
    )
    monkeypatch.setattr(
        "gateway.config.load_gateway_config",
        lambda: SimpleNamespace(
            platforms={
                SimpleNamespace(value="telegram"): SimpleNamespace(enabled=True),
            }
        ),
    )

    result = handle_request({"id": "gw-1", "action": "gateway_status"})
    assert result["ok"] is True
    assert result["status"]["running"] is True
    assert result["status"]["platforms"]


def test_remote_bridge_session_new_and_list(tmp_path, monkeypatch):
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path))
    created = handle_request({"id": "s-1", "action": "session_new", "title": "Phone"})
    assert created["ok"] is True
    assert created["session_id"].startswith("remote_")

    listed = handle_request({"id": "s-2", "action": "session_list", "source": "remote"})
    assert listed["ok"] is True
    assert any(row["id"] == created["session_id"] for row in listed["sessions"])


def test_remote_bridge_session_rename_and_delete(tmp_path, monkeypatch):
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path))
    created = handle_request({"id": "r-1", "action": "session_new", "title": "Draft"})
    assert created["ok"] is True
    sid = created["session_id"]

    renamed = handle_request(
        {"id": "r-2", "action": "session_rename", "session_id": sid, "title": "Titus notes"}
    )
    assert renamed["ok"] is True
    assert renamed["title"] == "Titus notes"

    listed = handle_request({"id": "r-3", "action": "session_list", "source": "remote"})
    assert any(
        row["id"] == sid and row.get("title") == "Titus notes" for row in listed["sessions"]
    )

    deleted = handle_request({"id": "r-4", "action": "session_delete", "session_id": sid})
    assert deleted["ok"] is True
    assert deleted["deleted"] is True

    listed_after = handle_request({"id": "r-5", "action": "session_list", "source": "remote"})
    assert all(row["id"] != sid for row in listed_after["sessions"])


def test_remote_bridge_approval_respond_action(monkeypatch):
    calls = []

    def fake_resolve(session_key, choice, resolve_all=False):
        calls.append((session_key, choice, resolve_all))
        return 1

    monkeypatch.setattr("tools.approval.resolve_gateway_approval", fake_resolve)
    result = handle_request(
        {
            "id": "a-1",
            "action": "approval_respond",
            "session_key": "remote:req",
            "choice": "once",
        }
    )
    assert result["ok"] is True
    assert result["resolved"] == 1
    assert calls == [("remote:req", "once", False)]
