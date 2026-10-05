"""Tests for WhatsApp quoted-reply context (quotedBody).

Covers the bridge -> adapter flow where a reply to a specific WhatsApp
message carries the quoted message's text, so the agent can see what the
reply refers to.

- quotedBody is prefixed to the event text as "[Replying to: ...]"
- empty own-body replies still carry the quoted context
- slash commands are NOT prefixed (command dispatch needs raw text first)
- over-long quoted text is truncated
"""

import asyncio
from unittest.mock import MagicMock, patch

import pytest

from gateway.config import Platform


def _make_adapter():
    """Create a WhatsAppAdapter with test attributes (bypass __init__)."""
    from gateway.platforms.whatsapp import WhatsAppAdapter

    adapter = WhatsAppAdapter.__new__(WhatsAppAdapter)
    adapter.platform = Platform.WHATSAPP
    adapter.config = MagicMock()
    adapter.config.extra = {}
    adapter._bridge_port = 3000
    adapter._bridge_script = "/tmp/test-bridge.js"
    adapter._session_path = MagicMock()
    adapter._bridge_log_fh = None
    adapter._bridge_log = None
    adapter._bridge_process = None
    adapter._reply_prefix = None
    adapter._running = True
    adapter._message_handler = None
    adapter._fatal_error_code = None
    adapter._fatal_error_message = None
    adapter._fatal_error_retryable = True
    adapter._fatal_error_handler = None
    adapter._active_sessions = {}
    adapter._pending_messages = {}
    adapter._background_tasks = set()
    adapter._auto_tts_disabled_chats = set()
    adapter._message_queue = asyncio.Queue()
    adapter._http_session = MagicMock()
    adapter._mention_patterns = []
    adapter._dm_policy = "open"
    adapter._allow_from = set()
    adapter._group_policy = "open"
    adapter._group_allow_from = set()
    return adapter


def _sample_data(**overrides):
    """A minimal bridge event dict for a text DM from the user."""
    data = {
        "messageId": "msg1",
        "chatId": "447970729736@s.whatsapp.net",
        "senderId": "447970729736@s.whatsapp.net",
        "senderName": "Mike",
        "chatName": "Mike",
        "isGroup": False,
        "body": "yes, do that",
        "hasMedia": False,
        "mediaType": "",
        "mediaUrls": [],
        "mentionedIds": [],
        "quotedMessageId": None,
        "quotedParticipant": None,
        "quotedRemoteJid": None,
        "hasQuotedMessage": False,
        "quotedBody": "",
        "botIds": [],
        "timestamp": 1234567890,
    }
    data.update(overrides)
    return data


class TestQuotedReplyContext:
    """quotedBody is surfaced to the agent."""

    @pytest.mark.asyncio
    async def test_quoted_body_prefixed_to_text(self):
        adapter = _make_adapter()
        event = await adapter._build_message_event(
            _sample_data(
                hasQuotedMessage=True,
                quotedBody="the Microsoft 365 plan",
            )
        )
        assert event is not None
        assert event.text == "[Replying to: the Microsoft 365 plan]\n\nyes, do that"

    @pytest.mark.asyncio
    async def test_quoted_body_with_empty_own_body(self):
        adapter = _make_adapter()
        event = await adapter._build_message_event(
            _sample_data(body="", hasQuotedMessage=True, quotedBody="the Outlook plan")
        )
        assert event is not None
        assert event.text == "[Replying to: the Outlook plan]"

    @pytest.mark.asyncio
    async def test_no_quoted_body_leaves_text_unchanged(self):
        adapter = _make_adapter()
        event = await adapter._build_message_event(_sample_data())
        assert event is not None
        assert event.text == "yes, do that"

    @pytest.mark.asyncio
    async def test_whitespace_quoted_body_ignored(self):
        adapter = _make_adapter()
        event = await adapter._build_message_event(
            _sample_data(hasQuotedMessage=True, quotedBody="   ")
        )
        assert event is not None
        assert event.text == "yes, do that"

    @pytest.mark.asyncio
    async def test_long_quoted_body_truncated(self):
        adapter = _make_adapter()
        long_quote = "x" * 5000
        event = await adapter._build_message_event(
            _sample_data(hasQuotedMessage=True, quotedBody=long_quote)
        )
        assert event is not None
        assert event.text.startswith("[Replying to: ")
        assert event.text.endswith("\n\nyes, do that")
        # 800-char cap + ellipsis
        assert "x" * 800 in event.text
        assert "x" * 801 not in event.text

    @pytest.mark.asyncio
    async def test_slash_command_not_prefixed(self):
        adapter = _make_adapter()
        event = await adapter._build_message_event(
            _sample_data(body="/new", hasQuotedMessage=True, quotedBody="old message")
        )
        assert event is not None
        assert event.text == "/new"

    @pytest.mark.asyncio
    async def test_quoted_body_survives_document_injection(self):
        """Quoted prefix comes first, then injected doc content, then body."""
        adapter = _make_adapter()

        mock_path = MagicMock()
        mock_path.name = "doc_abc_report.txt"
        mock_path.suffix = ".txt"
        mock_path.stat().st_size = 100
        mock_path.read_text.return_value = "file contents here"

        with patch("gateway.platforms.whatsapp.Path", return_value=mock_path):
            event = await adapter._build_message_event(
                _sample_data(
                    body="check this",
                    hasMedia=True,
                    mediaType="document",
                    mediaUrls=["/tmp/doc_abc_report.txt"],
                    hasQuotedMessage=True,
                    quotedBody="the report",
                )
            )
        assert event is not None
        assert event.text.startswith("[Replying to: the report]")
        assert "[Content of report.txt]" in event.text
        assert event.text.endswith("check this")
