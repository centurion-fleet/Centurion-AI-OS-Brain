"""Tests for centurion.fleet.transport."""

from __future__ import annotations

import json
from unittest.mock import MagicMock, patch

import pytest

from centurion.fleet.peers import FleetPeer, FleetPeers
from centurion.fleet.transport import FleetMessageEnvelope, FleetTransport


@pytest.fixture
def transport(tmp_path, monkeypatch):
    queue_dir = tmp_path / "queue"
    queue_dir.mkdir()
    monkeypatch.setattr(
        "centurion.fleet.transport.get_fleet_queue_dir",
        lambda: str(queue_dir),
    )
    peers = FleetPeers()
    peers.register(
        FleetPeer(
            centurion_id="peer-1",
            name="Peer One",
            address="http://127.0.0.1:9999",
        )
    )
    return FleetTransport(
        centurion_id="self",
        centurion_name="Self",
        auth_token="secret",
        peers=peers,
    )


def test_send_message_queues_when_peer_missing_address(transport):
    transport.peers.register(
        FleetPeer(centurion_id="peer-2", name="No Address", address="")
    )
    assert transport.send_message("peer-2", "Hi", "body") is False


@patch("urllib.request.urlopen")
def test_send_message_delivers_over_http(mock_urlopen, transport):
    """Delivery now requires the receiver to say it STORED the message.

    This test previously mocked only `status = 200` and asserted delivery, which
    encoded the contract that let a discarded message be reported as received.
    The receiver was changed to answer {"status": "stored"} only when it has
    written the message, so 200 alone is no longer success.
    """
    response = MagicMock()
    response.status = 200
    response.read.return_value = b'{"status": "stored", "message_id": "m1"}'
    response.__enter__.return_value = response
    mock_urlopen.return_value = response

    assert transport.send_message("peer-1", "Hello", "world") is True
    mock_urlopen.assert_called_once()


@patch("urllib.request.urlopen")
def test_received_receipt_is_not_delivery(mock_urlopen, transport):
    """The old lie: "received" for a message that was thrown away."""
    response = MagicMock()
    response.status = 200
    response.read.return_value = b'{"status": "received", "message_id": "m1"}'
    response.__enter__.return_value = response
    mock_urlopen.return_value = response

    assert transport.send_message("peer-1", "Hello", "world") is False


@patch("urllib.request.urlopen")
def test_non_json_receipt_is_not_delivery(mock_urlopen, transport):
    response = MagicMock()
    response.status = 200
    response.read.return_value = b"<html>proxy error</html>"
    response.__enter__.return_value = response
    mock_urlopen.return_value = response

    assert transport.send_message("peer-1", "Hello", "world") is False


def test_receive_message_invokes_callback(transport):
    received = []

    def on_message(envelope):
        received.append(envelope)

    transport.on_message = on_message
    envelope = FleetMessageEnvelope(
        message_id="m1",
        sender_id="peer-1",
        sender_name="Peer One",
        recipient_id="self",
        subject="Test",
        body="payload",
        priority="normal",
        timestamp=1.0,
    )
    result = transport.receive_message(envelope)
    assert result["status"] == "delivered"
    assert received and received[0].subject == "Test"


def test_process_outbox_retries_then_drops(tmp_path, transport, monkeypatch):
    import os
    from dataclasses import asdict

    outbox = transport._outbox_dir
    envelope = FleetMessageEnvelope(
        message_id="retry-1",
        sender_id="self",
        sender_name="Self",
        recipient_id="peer-1",
        subject="Queued",
        body="{}",
        priority="normal",
        timestamp=1.0,
    )
    path = f"{outbox}/retry-1.json"
    os.makedirs(outbox, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump({**asdict(envelope), "retry_count": 5, "last_attempt": 0}, f)

    pending = transport.process_outbox()
    assert pending == 0
    assert not os.path.exists(path)
