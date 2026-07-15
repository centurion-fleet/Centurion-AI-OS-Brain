"""Extract a single Centurion Telegram bot DM for Centurion Remote import."""

from __future__ import annotations

import json
import logging
import re
import shutil
import time
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

from centurion_constants import get_centurion_home
from centurion_state import SessionDB

logger = logging.getLogger(__name__)

_DM_KEY_RE = re.compile(r"^agent:main:telegram:dm(?::|$)")


def _sessions_index_path() -> Path:
    return get_centurion_home() / "sessions" / "sessions.json"


def _imports_root() -> Path:
    return get_centurion_home() / "imports"


def _load_sessions_index() -> dict[str, Any]:
    path = _sessions_index_path()
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def _dm_session_keys(index: dict[str, Any]) -> list[str]:
    keys = [key for key in index if _DM_KEY_RE.match(str(key))]
    return sorted(keys)


def _resolve_telegram_ids() -> tuple[str, str]:
    """Best-effort (chat_id, user_id) from config and session index."""
    chat_id = ""
    user_id = ""
    try:
        from centurion_cli.config import load_config

        cfg = load_config()
        telegram_cfg = cfg.get("telegram") if isinstance(cfg.get("telegram"), dict) else {}
        if isinstance(telegram_cfg, dict):
            chat_id = str(telegram_cfg.get("chat_id") or telegram_cfg.get("default_chat_id") or "")
            user_id = str(telegram_cfg.get("user_id") or "")
    except Exception:
        pass

    if not chat_id:
        for key in _dm_session_keys(_load_sessions_index()):
            parts = key.split(":")
            if len(parts) >= 5 and parts[3] == "dm":
                chat_id = parts[4]
                break
    return chat_id, user_id


def find_telegram_dm_candidates(*, limit: int = 10) -> list[dict[str, Any]]:
    """Return candidate Telegram DM sessions ordered by recent activity."""
    db = SessionDB()
    chat_id, user_id = _resolve_telegram_ids()
    candidates: list[dict[str, Any]] = []

    if user_id:
        candidates = db.list_unlinked_telegram_sessions_for_user(
            chat_id=chat_id,
            user_id=user_id,
            limit=limit,
        )
    if not candidates:
        candidates = db.search_sessions(source="telegram", limit=limit)

    dm_only: list[dict[str, Any]] = []
    index = _load_sessions_index()
    dm_keys = set(_dm_session_keys(index))
    session_key_by_id = {
        str(entry.get("session_id") or entry.get("id") or ""): key
        for key, entry in index.items()
        if isinstance(entry, dict)
    }

    for session in candidates:
        session_id = str(session.get("id") or "")
        bound_key = session_key_by_id.get(session_id, "")
        if bound_key and bound_key not in dm_keys:
            continue
        if bound_key and ":group:" in bound_key:
            continue
        if chat_id and bound_key and f":dm:{chat_id}" not in bound_key and bound_key.count(":") >= 5:
            continue
        dm_only.append(
            {
                **session,
                "session_key": bound_key,
                "message_count": int(session.get("message_count") or 0),
                "last_active": float(session.get("last_active") or session.get("started_at") or 0),
            }
        )

    dm_only.sort(
        key=lambda row: (row.get("last_active", 0), row.get("message_count", 0)),
        reverse=True,
    )
    return dm_only


def pick_primary_session(candidates: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not candidates:
        return None
    return candidates[0]


def _flatten_content(content: Any) -> tuple[str, list[str]]:
    """Return display text and referenced file paths from message content."""
    paths: list[str] = []
    if content is None:
        return "", paths
    if isinstance(content, str):
        paths.extend(_extract_paths_from_text(content))
        return content, paths
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, dict):
                if item.get("type") == "text":
                    text = str(item.get("text") or "")
                    parts.append(text)
                    paths.extend(_extract_paths_from_text(text))
                elif item.get("type") == "image_url":
                    url = ""
                    image_url = item.get("image_url")
                    if isinstance(image_url, dict):
                        url = str(image_url.get("url") or "")
                    elif isinstance(image_url, str):
                        url = image_url
                    if url:
                        paths.extend(_extract_paths_from_text(url))
                        parts.append(f"[image: {Path(url).name or 'attachment'}]")
                else:
                    parts.append(str(item))
            else:
                parts.append(str(item))
        return "\n".join(part for part in parts if part).strip(), paths
    if isinstance(content, dict):
        text = str(content.get("text") or json.dumps(content))
        paths.extend(_extract_paths_from_text(text))
        return text, paths
    text = str(content)
    paths.extend(_extract_paths_from_text(text))
    return text, paths


def _extract_paths_from_text(text: str) -> list[str]:
    found: list[str] = []
    if not text:
        return found
    for match in re.finditer(r"file://[^\s\]>]+", text):
        found.append(unquote(match.group(0)))
    home = str(get_centurion_home())
    cache_root = str(get_centurion_home() / "cache")
    for sub in ("documents", "images", "audio", "video"):
        pattern = re.compile(rf"{re.escape(cache_root)}/{sub}/[^\s\]>\"']+")
        found.extend(pattern.findall(text))
    if home in text:
        for token in re.split(r"[\s\"'>]+", text):
            if token.startswith(home) and "/cache/" in token:
                found.append(token)
    return found


def _normalize_cache_path(path_str: str) -> Path | None:
    if not path_str:
        return None
    if path_str.startswith("file://"):
        parsed = urlparse(path_str)
        candidate = Path(unquote(parsed.path))
    else:
        candidate = Path(path_str)
    if not candidate.is_absolute():
        candidate = get_centurion_home() / candidate
    try:
        candidate = candidate.resolve()
    except OSError:
        return None
    cache_root = (get_centurion_home() / "cache").resolve()
    if cache_root not in candidate.parents and candidate != cache_root:
        return None
    return candidate


def build_import_bundle(
    *,
    session_id: str | None = None,
    dry_run: bool = False,
) -> dict[str, Any]:
    """Build (and optionally materialize) a Telegram bot DM import bundle."""
    candidates = find_telegram_dm_candidates()
    if session_id:
        chosen = next((row for row in candidates if str(row.get("id")) == session_id), None)
        if chosen is None:
            db = SessionDB()
            session = db.get_session(session_id)
            if session and session.get("source") == "telegram":
                chosen = session
    else:
        chosen = pick_primary_session(candidates)

    if not chosen:
        return {
            "ok": False,
            "message": "No Telegram bot DM session was found on this Centurion.",
            "candidates": [],
        }

    session_id = str(chosen.get("id") or "")
    db = SessionDB()
    exported = db.export_session(session_id)
    if not exported:
        return {
            "ok": False,
            "message": "Could not export the Telegram session.",
            "candidates": candidates,
        }

    timestamp = time.strftime("%Y%m%d-%H%M%S")
    bundle_dir = _imports_root() / f"telegram-bot-{timestamp}"
    files_dir = bundle_dir / "files"
    if not dry_run:
        files_dir.mkdir(parents=True, exist_ok=True)

    copied_files: dict[str, dict[str, Any]] = {}
    messages_out: list[dict[str, Any]] = []
    missing_files: list[str] = []

    for raw in exported.get("messages") or []:
        role = str(raw.get("role") or "")
        if role not in {"user", "assistant"}:
            continue
        if raw.get("observed"):
            continue
        content = raw.get("content")
        text, referenced = _flatten_content(content)
        attachments: list[dict[str, Any]] = []
        for ref in referenced:
            source = _normalize_cache_path(ref)
            if source is None:
                continue
            file_id = source.name
            if file_id in copied_files:
                attachments.append(copied_files[file_id])
                continue
            rel_path = f"files/{file_id}"
            entry = {
                "id": file_id,
                "filename": source.name,
                "path": rel_path,
                "missing": not source.is_file(),
            }
            if source.is_file() and not dry_run:
                try:
                    shutil.copy2(source, files_dir / file_id)
                    entry["missing"] = False
                except OSError as exc:
                    logger.debug("Could not copy %s: %s", source, exc)
                    entry["missing"] = True
            if entry["missing"]:
                missing_files.append(source.name)
                text = f"{text}\n[attachment unavailable: {source.name}]".strip()
            copied_files[file_id] = entry
            attachments.append(entry)

        messages_out.append(
            {
                "role": "user" if role == "user" else "centurion",
                "content": text,
                "timestamp": raw.get("timestamp"),
                "attachments": attachments,
            }
        )

    bundle = {
        "ok": True,
        "conversation": {
            "title": "Telegram with Centurion",
            "context": "standalone",
        },
        "session_id": session_id,
        "session_key": chosen.get("session_key", ""),
        "message_count": len(messages_out),
        "file_count": len(copied_files),
        "missing_file_count": len(missing_files),
        "date_range": _date_range(messages_out),
        "messages": messages_out,
        "files": list(copied_files.values()),
        "candidates": [
            {
                "session_id": str(row.get("id") or ""),
                "preview": row.get("preview", ""),
                "message_count": int(row.get("message_count") or 0),
                "last_active": row.get("last_active"),
                "session_key": row.get("session_key", ""),
            }
            for row in candidates
        ],
        "bundle_path": str(bundle_dir) if not dry_run else "",
    }

    if not dry_run:
        bundle_dir.mkdir(parents=True, exist_ok=True)
        manifest_path = bundle_dir / "bundle.json"
        manifest_path.write_text(json.dumps(bundle, indent=2) + "\n", encoding="utf-8")
        bundle["manifest_path"] = str(manifest_path)

    return bundle


def _date_range(messages: list[dict[str, Any]]) -> dict[str, Any]:
    stamps = [float(msg["timestamp"]) for msg in messages if msg.get("timestamp") is not None]
    if not stamps:
        return {"start": None, "end": None}
    return {"start": min(stamps), "end": max(stamps)}


def load_latest_bundle_manifest() -> dict[str, Any] | None:
    root = _imports_root()
    if not root.is_dir():
        return None
    manifests = sorted(root.glob("telegram-bot-*/bundle.json"), reverse=True)
    if not manifests:
        return None
    try:
        data = json.loads(manifests[0].read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None
