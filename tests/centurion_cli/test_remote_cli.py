"""Tests for remote pairing connection-string helpers."""

from centurion_cli.remote_cli import format_connection_string, parse_connection_string


def test_format_connection_string():
    assert (
        format_connection_string("abc", "brain.example.com", 9119)
        == "token:abc@brain.example.com:9119"
    )


def test_parse_connection_string_with_port():
    assert parse_connection_string("token:secret@host.example:9119") == (
        "secret",
        "host.example",
        9119,
    )


def test_parse_connection_string_default_port():
    assert parse_connection_string("  token:xyz@10.0.0.5  ") == (
        "xyz",
        "10.0.0.5",
        9119,
    )


def test_parse_connection_string_rejects_garbage():
    assert parse_connection_string("not-a-token") is None
    assert parse_connection_string("token:") is None
    assert parse_connection_string("token:onlysecret") is None
