"""Unit tests for RelayTransport envelope + chunking (no network)."""

from __future__ import annotations

import pytest

from centurion_cli.relay_transport import (
    ChunkAssembler,
    PendingById,
    build_envelopes,
    decode_body,
    new_conn_id,
    new_message_id,
    split_chunks,
)


def test_split_and_reassemble_round_trip():
    raw = b"x" * 500_000
    chunks = split_chunks(raw, chunk_bytes=180_000)
    assert len(chunks) >= 3
    assert b"".join(chunks) == raw


def test_build_envelopes_single_frame():
    conn = new_conn_id()
    msg = new_message_id()
    body = b"hello-secretbox"
    envs = build_envelopes(conn=conn, msg_id=msg, kind="frame", body=body, chunk_bytes=1024)
    assert len(envs) == 1
    assert envs[0].kind == "frame"
    assert envs[0].chunk_n == 1
    assert decode_body(envs[0].body_b64) == body


def test_chunk_assembler_multi():
    conn = new_conn_id()
    msg = new_message_id()
    body = b"ABCDEFGHIJKLMNOP" * 2000
    envs = build_envelopes(
        conn=conn, msg_id=msg, kind="frame", body=body, chunk_bytes=500
    )
    assert len(envs) > 1
    asm = ChunkAssembler()
    out = None
    for env in envs[:-1]:
        assert asm.push(env) is None
    out = asm.push(envs[-1])
    assert out == body


def test_chunk_assembler_rejects_oversize():
    conn = new_conn_id()
    msg = new_message_id()
    with pytest.raises(ValueError, match="exceeds"):
        build_envelopes(
            conn=conn,
            msg_id=msg,
            kind="frame",
            body=b"z" * 2_000_000,
            max_reassembled=1_000_000,
        )


def test_pending_by_id_demux():
    pending = PendingById()
    msg = new_message_id()
    pending.expect(msg)
    env = build_envelopes(
        conn=new_conn_id(), msg_id=msg, kind="frame", body=b"ok"
    )[0]
    assert pending.ingest(env) is not None
    stranger = build_envelopes(
        conn=new_conn_id(), msg_id=new_message_id(), kind="frame", body=b"push"
    )[0]
    assert pending.ingest(stranger) is None


def test_new_conn_forces_distinct_epochs():
    assert new_conn_id() != new_conn_id()


def test_relay_session_stale_conn_rejected():
    from centurion_cli.relay_transport import RelaySession

    session = RelaySession()
    session.mark_kx_complete()
    events = session.outbound_frame(b"abc")
    # Simulate peer still on old epoch after we reset
    old_event = dict(events[0])
    session.reset_connection()
    try:
        session.ingest_event(old_event)
        assert False, "expected stale conn error"
    except ValueError as exc:
        assert "stale" in str(exc).lower()
