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


def test_format_remote_tool_activity_line_basic(monkeypatch):
    from centurion_cli import remote_bridge as rb

    monkeypatch.setattr(
        "agent.display.get_tool_emoji",
        lambda name, default="⚡": "🔍" if name == "web_search" else default,
    )
    monkeypatch.setattr("agent.display.get_tool_preview_max_len", lambda: 40)
    line = rb._format_remote_tool_activity_line(
        "web_search", preview="sovereign ai brain", mode="all"
    )
    assert line.startswith("🔍 web_search:")
    assert "sovereign ai brain" in line


def test_make_remote_activity_callbacks_emit_tool_and_thinking(monkeypatch):
    from centurion_cli import remote_bridge as rb

    emitted = []

    monkeypatch.setenv("CENTURION_REMOTE_EVENTS", "1")
    monkeypatch.setattr(rb, "_emit_remote_event", lambda event: emitted.append(event))
    monkeypatch.setattr(
        "agent.display.get_tool_emoji",
        lambda name, default="⚡": "📖",
    )
    monkeypatch.setattr("agent.display.get_tool_preview_max_len", lambda: 40)

    tool_cb, status_cb = rb._make_remote_activity_callbacks(mode="all")
    tool_cb("tool.started", "read_file", "AGENTS.md", {"path": "AGENTS.md"})
    tool_cb("reasoning.available", "_thinking", "Considering the next step", None)
    status_cb("lifecycle", "Compressing context")
    tool_cb("tool.completed", "read_file", "done", None)  # ignored in all mode

    kinds = [e.get("kind") for e in emitted]
    assert kinds == ["tool", "thinking", "status"]
    assert emitted[0]["centurion_event"] == "activity"
    assert emitted[0]["tool"] == "read_file"
    assert "AGENTS.md" in emitted[0]["line"]
    assert emitted[1]["text"].startswith("Considering")
    assert emitted[2]["message"] == "Compressing context"


def test_make_remote_activity_callbacks_off_is_silent(monkeypatch):
    from centurion_cli import remote_bridge as rb

    emitted = []
    monkeypatch.setenv("CENTURION_REMOTE_EVENTS", "1")
    monkeypatch.setattr(rb, "_emit_remote_event", lambda event: emitted.append(event))
    tool_cb, status_cb = rb._make_remote_activity_callbacks(mode="off")
    tool_cb("tool.started", "web_search", "q", {})
    status_cb("warn", "something")
    assert emitted == []


def test_resolve_remote_tool_progress_mode_defaults_all():
    from centurion_cli import remote_bridge as rb

    assert rb._resolve_remote_tool_progress_mode({}) == "all"
    assert (
        rb._resolve_remote_tool_progress_mode(
            {"display": {"tool_progress": "new"}}
        )
        == "new"
    )
    assert (
        rb._resolve_remote_tool_progress_mode(
            {
                "display": {
                    "tool_progress": "all",
                    "platforms": {"remote": {"tool_progress": "off"}},
                }
            }
        )
        == "off"
    )


def test_bridge_serve_health_check_round_trip(tmp_path, monkeypatch):
    """Persistent --serve daemon answers health_check over a Unix socket."""
    import json
    import socket
    import subprocess
    import sys
    import time

    sock_path = tmp_path / "bridge.sock"
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path))
    monkeypatch.setenv("CENTURION_BRIDGE_SOCKET", str(sock_path))

    proc = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "centurion_cli.remote_bridge",
            "--serve",
            "--socket",
            str(sock_path),
            "--workers",
            "2",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        deadline = time.time() + 15
        while time.time() < deadline:
            if sock_path.exists():
                try:
                    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                        client.settimeout(2.0)
                        client.connect(str(sock_path))
                        client.sendall(
                            b'{"id":"t1","action":"health_check"}\n'
                        )
                        data = b""
                        while b"\n" not in data:
                            chunk = client.recv(4096)
                            if not chunk:
                                break
                            data += chunk
                        payload = json.loads(data.decode("utf-8").split("\n", 1)[0])
                        assert payload.get("id") == "t1"
                        assert payload.get("ok") is True
                        assert payload.get("action") == "health_check"
                        return
                except (ConnectionRefusedError, FileNotFoundError, OSError):
                    pass
            time.sleep(0.05)
        raise AssertionError("bridge daemon did not become ready")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


def test_handle_chat_life_inject_inserts_context(monkeypatch):
    from centurion_cli import remote_bridge as rb

    def fake_inject(message, current_view=None):
        return {"formatted_for_ai": "MISSION_CTX"}

    monkeypatch.setattr(
        "centurion_cli.life_missions.inject_context",
        fake_inject,
        raising=False,
    )

    # Patch import path used inside _handle_chat
    import types
    import sys

    fake_mod = types.ModuleType("centurion_cli.life_missions")
    fake_mod.inject_context = fake_inject
    monkeypatch.setitem(sys.modules, "centurion_cli.life_missions", fake_mod)

    seen = {}

    def run_agent(text, **kwargs):
        seen["text"] = text
        return "ok"

    framed = (
        "[Sovereign AI Brain — Mission discuss]\n"
        "Help them.\n\n"
        "User message:\n"
        "hello"
    )
    result = rb.handle_request(
        {
            "id": "inj-1",
            "action": "chat",
            "text": framed,
            "life_inject": {
                "message": "hello",
                "current_view": {"mission_id": "m1"},
            },
        },
        run_agent=run_agent,
    )
    assert result["ok"] is True
    assert "MISSION_CTX" in seen["text"]
    assert "User message:" in seen["text"]


def test_handle_chat_skills_prepends_skill_bodies(monkeypatch):
    from centurion_cli import remote_bridge as rb

    def fake_build(cmd_key, user_instruction=""):
        return f"[SKILL {cmd_key}]"

    monkeypatch.setattr(
        "agent.skill_commands.build_skill_invocation_message",
        fake_build,
        raising=False,
    )
    import types
    import sys

    fake_mod = types.ModuleType("agent.skill_commands")
    fake_mod.build_skill_invocation_message = fake_build
    monkeypatch.setitem(sys.modules, "agent.skill_commands", fake_mod)

    seen = {}

    def run_agent(text, **kwargs):
        seen["text"] = text
        return "ok"

    result = rb.handle_request(
        {
            "id": "skills-1",
            "action": "chat",
            "text": "What does the arXiv paper say?",
            "skills": ["arxiv", "missing-skill"],
        },
        run_agent=run_agent,
    )
    assert result["ok"] is True
    assert seen["text"].startswith("[SKILL /arxiv]")
    assert "What does the arXiv paper say?" in seen["text"]
    # Missing skills that return None are skipped (fake always returns).
    assert "[SKILL /missing-skill]" in seen["text"]


def test_settings_snapshot_aggregates_sections(monkeypatch):
    from centurion_cli import remote_bridge as rb

    monkeypatch.setattr(
        rb,
        "get_status",
        lambda *, probe=True: type(
            "S",
            (),
            {
                "to_dict": lambda self: {
                    "provider": "openrouter",
                    "model": "test-model",
                    "health": "ok",
                    "health_message": "fine",
                    "last_good": {"provider": "x"},
                    "last_good_available": False,
                }
            },
        )(),
    )
    monkeypatch.setattr(
        rb.support_control,
        "list_backup_thinking_services",
        lambda: [{"label": "backup via openrouter", "provider": "openrouter", "model": "b"}],
    )
    monkeypatch.setattr(
        rb,
        "_handle_soul_get",
        lambda request_id: {
            "id": request_id,
            "ok": True,
            "soul": {"name": "Ada", "displayName": "Ada"},
        },
    )
    monkeypatch.setattr(
        rb,
        "_handle_oversight_get",
        lambda request_id: {
            "id": request_id,
            "ok": True,
            "oversight": {"autonomy_level": "collaborative"},
        },
    )
    monkeypatch.setattr(
        rb,
        "_handle_memory_horizon_snapshot",
        lambda request_id: {
            "id": request_id,
            "ok": True,
            "snapshot": {"provider": "none", "summary": "empty"},
        },
    )
    monkeypatch.setattr(
        rb,
        "_handle_license_status",
        lambda request_id: {
            "id": request_id,
            "ok": True,
            "license": {"state": "trial", "tier": "trial"},
        },
    )
    monkeypatch.setattr(
        rb,
        "_handle_beneficiary_snapshot",
        lambda request_id: {
            "id": request_id,
            "ok": True,
            "snapshot": {
                "current_cycle": {"family_beneficiary_first_name": "Sam"},
            },
        },
    )
    monkeypatch.setattr(
        "centurion.license.enforcement.enforcement_enabled",
        lambda config=None: False,
    )
    monkeypatch.setattr(
        "centurion_cli.life_missions.get_data_version",
        lambda: 7,
    )

    result = handle_request(
        {"id": "settings-1", "action": "settings_snapshot", "skip_probe": True}
    )
    assert result["ok"] is True
    assert result["action"] == "settings_snapshot"
    assert result["thinking"]["provider"] == "openrouter"
    assert "last_good" not in result["thinking"]
    assert result["backups"][0]["provider"] == "openrouter"
    assert result["soul"]["name"] == "Ada"
    assert result["oversight"]["autonomy_level"] == "collaborative"
    assert result["horizon"]["provider"] == "none"
    assert result["license"]["state"] == "trial"
    assert "enabled" in result["license"]
    assert result["beneficiary"]["family_beneficiary_first_name"] == "Sam"
    assert result["beneficiary"]["enabled"] is True
    assert result["data_version"] == 7
    assert "firecrawl" in result
    assert result["firecrawl"]["key"] == "FIRECRAWL_API_KEY"
    assert "url" in result["firecrawl"]
    assert "firecrawl.dev" in (result["firecrawl"].get("url") or "")


def test_tool_env_get_set_firecrawl(monkeypatch):
    from centurion_cli import remote_bridge as rb
    from centurion_cli.remote_bridge import handle_request

    saved: dict[str, str] = {}

    def _fake_save(key: str, value: str):
        saved[key] = value
        import os

        os.environ[key] = value

    monkeypatch.setattr("centurion_cli.config.save_env_value", _fake_save)
    monkeypatch.setattr(
        "centurion_cli.config.get_env_value",
        lambda key: saved.get(key) or None,
    )

    denied = handle_request(
        {"id": "te1", "action": "tool_env_set", "key": "OPENAI_API_KEY", "value": "x"}
    )
    assert denied["ok"] is False

    empty = handle_request(
        {
            "id": "te2",
            "action": "tool_env_set",
            "key": "FIRECRAWL_API_KEY",
            "value": "  ",
        }
    )
    assert empty["ok"] is False

    ok = handle_request(
        {
            "id": "te3",
            "action": "tool_env_set",
            "key": "FIRECRAWL_API_KEY",
            "value": "fc-test-key-123",
        }
    )
    assert ok["ok"] is True
    assert ok["configured"] is True
    assert saved["FIRECRAWL_API_KEY"] == "fc-test-key-123"
    assert "firecrawl.dev" in (ok.get("url") or "")

    got = handle_request(
        {"id": "te4", "action": "tool_env_get", "key": "FIRECRAWL_API_KEY"}
    )
    assert got["ok"] is True
    assert got["configured"] is True
    assert "value" not in got  # never echo secret
    assert rb._TOOL_ENV_ALLOWLIST == frozenset({"FIRECRAWL_API_KEY"})
