import json
import time

import pytest

from centurion_cli.telegram_import import build_import_bundle
from centurion_state import SessionDB


@pytest.fixture
def telegram_session_db(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    cache = home / "cache" / "documents"
    cache.mkdir(parents=True)
    doc = cache / "notes.txt"
    doc.write_text("hello from telegram", encoding="utf-8")

    sessions_dir = home / "sessions"
    sessions_dir.mkdir()
    session_id = "sess-telegram-1"
    (sessions_dir / "sessions.json").write_text(
        json.dumps(
            {
                f"agent:main:telegram:dm:12345": {
                    "session_id": session_id,
                    "platform": "telegram",
                    "chat_type": "dm",
                    "chat_id": "12345",
                }
            }
        ),
        encoding="utf-8",
    )

    monkeypatch.setenv("CENTURION_HOME", str(home))
    db = SessionDB(db_path=home / "state.db")
    db.create_session(session_id, source="telegram", user_id="999")
    db.append_message(session_id, role="user", content="See file://%s" % doc)
    db.append_message(session_id, role="assistant", content="Got your document.")
    return home, session_id, doc


def test_telegram_import_bundle_exports_messages_and_files(telegram_session_db, tmp_path):
    home, session_id, doc = telegram_session_db
    bundle = build_import_bundle(session_id=session_id, dry_run=False)

    assert bundle["ok"] is True
    assert bundle["message_count"] == 2
    assert bundle["file_count"] == 1
    assert bundle["messages"][0]["role"] == "user"
    assert bundle["messages"][1]["role"] == "centurion"
    files = bundle["files"]
    assert len(files) == 1
    assert files[0]["filename"] == "notes.txt"
    assert "content_base64" in files[0]
    assert files[0]["size_bytes"] == doc.stat().st_size
    copied = home / "imports"
    manifests = list(copied.glob("telegram-bot-*/files/notes.txt"))
    assert manifests
    # Disk manifest stays lean (no inlined bytes).
    manifest = next(copied.glob("telegram-bot-*/bundle.json"))
    disk = json.loads(manifest.read_text(encoding="utf-8"))
    assert "content_base64" not in disk["files"][0]


def test_telegram_import_failure_shape_is_decode_complete(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    SessionDB(db_path=home / "state.db")  # empty sessions DB

    bundle = build_import_bundle(dry_run=True)
    assert bundle["ok"] is False
    assert isinstance(bundle["message"], str)
    assert bundle["messages"] == []
    assert bundle["files"] == []
    assert bundle["candidates"] == []
    assert set(bundle["date_range"]) == {"start", "end"}
    assert bundle["message_count"] == 0
    assert bundle["conversation"] is None
    assert bundle["session_id"] is None


def test_telegram_import_dry_run_skips_inline_bytes(telegram_session_db):
    _, session_id, _ = telegram_session_db
    bundle = build_import_bundle(session_id=session_id, dry_run=True)
    assert bundle["ok"] is True
    assert bundle["file_count"] == 1
    assert "content_base64" not in bundle["files"][0]
    assert bundle["bundle_path"] == ""
