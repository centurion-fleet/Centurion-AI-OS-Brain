"""Tests for centurion-api-server toolset and API server tool availability."""
import os
import json
from unittest.mock import patch, MagicMock

import pytest

from toolsets import resolve_toolset, get_toolset, validate_toolset


class TestCenturionApiServerToolset:
    """Tests for the centurion-api-server toolset definition."""

    def test_toolset_exists(self):
        ts = get_toolset("centurion-api-server")
        assert ts is not None

    def test_toolset_validates(self):
        assert validate_toolset("centurion-api-server")

    def test_toolset_includes_web_tools(self):
        tools = resolve_toolset("centurion-api-server")
        assert "web_search" in tools
        assert "web_extract" in tools

    def test_toolset_includes_core_tools(self):
        tools = resolve_toolset("centurion-api-server")
        expected = [
            "terminal", "process",
            "read_file", "write_file", "patch", "search_files",
            "vision_analyze", "image_generate",
            "execute_code", "delegate_task",
            "todo", "memory", "session_search", "cronjob",
        ]
        for tool in expected:
            assert tool in tools, f"Missing expected tool: {tool}"

    def test_toolset_includes_browser_tools(self):
        tools = resolve_toolset("centurion-api-server")
        for tool in ["browser_navigate", "browser_snapshot", "browser_click",
                      "browser_type", "browser_scroll", "browser_back",
                      "browser_press"]:
            assert tool in tools, f"Missing browser tool: {tool}"

    def test_toolset_includes_homeassistant_tools(self):
        tools = resolve_toolset("centurion-api-server")
        for tool in ["ha_list_entities", "ha_get_state", "ha_list_services", "ha_call_service"]:
            assert tool in tools, f"Missing HA tool: {tool}"

    def test_toolset_excludes_clarify(self):
        tools = resolve_toolset("centurion-api-server")
        assert "clarify" not in tools

    def test_toolset_excludes_send_message(self):
        tools = resolve_toolset("centurion-api-server")
        assert "send_message" not in tools

    def test_toolset_excludes_text_to_speech(self):
        tools = resolve_toolset("centurion-api-server")
        assert "text_to_speech" not in tools


class TestApiServerPlatformConfig:
    def test_platforms_dict_includes_api_server(self):
        from centurion_cli.tools_config import PLATFORMS
        assert "api_server" in PLATFORMS
        assert PLATFORMS["api_server"]["default_toolset"] == "centurion-api-server"


class TestApiServerAdapterToolset:
    @patch("gateway.platforms.api_server.AIOHTTP_AVAILABLE", True)
    def test_create_agent_reads_config_toolsets(self):
        """API server resolves toolsets from config like all other platforms."""
        from gateway.platforms.api_server import APIServerAdapter
        from gateway.config import PlatformConfig

        adapter = APIServerAdapter(PlatformConfig())

        with patch("gateway.run._resolve_runtime_agent_kwargs") as mock_kwargs, \
             patch("gateway.run._resolve_gateway_model") as mock_model, \
             patch("gateway.run._load_gateway_config") as mock_config, \
             patch("run_agent.AIAgent") as mock_agent_cls:

            mock_kwargs.return_value = {"api_key": "test-key", "base_url": None,
                                        "provider": None, "api_mode": None,
                                        "command": None, "args": []}
            mock_model.return_value = "test/model"
            # No platform_toolsets override — should fall back to centurion-api-server default
            mock_config.return_value = {}
            mock_agent_cls.return_value = MagicMock()

            adapter._create_agent()

            mock_agent_cls.assert_called_once()
            call_kwargs = mock_agent_cls.call_args
            toolsets = call_kwargs.kwargs.get("enabled_toolsets")
            assert isinstance(toolsets, list)
            assert len(toolsets) > 0
            assert call_kwargs.kwargs.get("platform") == "api_server"

    @patch("gateway.platforms.api_server.AIOHTTP_AVAILABLE", True)
    def test_create_agent_respects_config_override(self):
        """User can override API server toolsets via platform_toolsets in config.yaml."""
        from gateway.platforms.api_server import APIServerAdapter
        from gateway.config import PlatformConfig

        adapter = APIServerAdapter(PlatformConfig())

        with patch("gateway.run._resolve_runtime_agent_kwargs") as mock_kwargs, \
             patch("gateway.run._resolve_gateway_model") as mock_model, \
             patch("gateway.run._load_gateway_config") as mock_config, \
             patch("run_agent.AIAgent") as mock_agent_cls:

            mock_kwargs.return_value = {"api_key": "test-key", "base_url": None,
                                        "provider": None, "api_mode": None,
                                        "command": None, "args": []}
            mock_model.return_value = "test/model"
            # User overrides with just web and terminal
            mock_config.return_value = {
                "platform_toolsets": {"api_server": ["web", "terminal"]}
            }
            mock_agent_cls.return_value = MagicMock()

            adapter._create_agent()

            mock_agent_cls.assert_called_once()
            call_kwargs = mock_agent_cls.call_args
            toolsets = call_kwargs.kwargs.get("enabled_toolsets")
            # ``vault`` is added by ``_get_platform_tools`` regardless of the
            # configured list (verified: a default config returns it too), so the
            # override's intent — replace the default set, not extend it — is
            # tested by the two configured names being the only configured ones.
            assert sorted(toolsets) == ["terminal", "vault", "web"]


class TestPerRequestToolsetNarrowing:
    """A caller may narrow the platform's toolsets for one request, never widen them.

    This exists for the practice desk: a browser session opened by a junior
    accountant must not be able to ask the machine to run a shell command. The
    narrowing is an intersection with what the server already has enabled, so no
    request body can add a capability the platform does not carry.
    """

    def _adapter(self):
        from gateway.platforms.api_server import APIServerAdapter
        from gateway.config import PlatformConfig

        return APIServerAdapter(PlatformConfig())

    def _agent_toolsets(self, toolsets=None, platform_set=("web", "terminal", "file")):
        adapter = self._adapter()
        with patch("gateway.run._resolve_runtime_agent_kwargs") as mock_kwargs, \
             patch("gateway.run._resolve_gateway_model") as mock_model, \
             patch("gateway.run._load_gateway_config") as mock_config, \
             patch("run_agent.AIAgent") as mock_agent_cls:
            mock_kwargs.return_value = {
                "api_key": "***", "base_url": None, "provider": None,
                "api_mode": None, "command": None, "args": [],
            }
            mock_model.return_value = "test/model"
            mock_config.return_value = {
                "platform_toolsets": {"api_server": list(platform_set)}
            }
            adapter._create_agent(toolsets=toolsets)
            return mock_agent_cls.call_args.kwargs.get("enabled_toolsets")

    def test_a_request_may_narrow_to_a_subset(self):
        assert sorted(self._agent_toolsets(["web", "file"])) == ["file", "web"]

    def test_no_narrowing_leaves_the_platform_set_alone(self):
        assert sorted(self._agent_toolsets(None)) == ["file", "terminal", "vault", "web"]

    def test_a_request_cannot_widen_beyond_the_platform(self):
        """Asking for a toolset the server does not enable grants nothing.

        Partial overlap keeps the part the server does have; total overlap of
        nothing is an error rather than a silent empty toolset, because an agent
        with no tools that answers anyway is worse than a failed request.
        """
        got = self._agent_toolsets(["web", "discord"])
        assert sorted(got) == ["web"]

        with pytest.raises(ValueError):
            self._agent_toolsets(["discord", "spotify"])

    def test_a_practice_server_configured_without_control_toolsets_cannot_be_asked_for_them(self):
        """The specific ones a practice browser session must never obtain.

        On a desk machine the platform toolsets are configured to the narrow set;
        a request that then asks for terminal gets nothing back for it. This is
        the second line of defence — the first is that the desk never asks.
        """
        practice_set = ("web", "file", "skills", "memory")
        for forbidden in ("terminal", "code_execution", "cronjob", "delegation", "browser"):
            got = self._agent_toolsets(["web", forbidden], platform_set=practice_set)
            assert sorted(got) == ["web"], forbidden
