"""Memory Horizon continuity — being persistence across sessions.

Builds on the existing three Horizon layers (Hot Cache / Session Recall /
Vault) without inventing a parallel store outside Memory Horizon:

* First-turn prefetch: ephemeral Session Recall digest of recent sessions
  plus the last Hot Cache ``CONTINUITY.md`` note (API-only fence; never
  mutates the system prompt or stored messages).
* Session-end digest: Vault ``experiential`` propose when Vault is enabled
  and unlocked; otherwise write ``memories/CONTINUITY.md`` so the next
  first turn still has a continuity trail.

See website/docs/user-guide/features/memory-layers.md.
"""

from __future__ import annotations

import json
import logging
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

logger = logging.getLogger(__name__)

_DEFAULT_DIGEST_MAX_CHARS = 1200
_DEFAULT_LOOKBACK_HOURS = 36
_DEFAULT_MAX_SESSIONS = 5
_MIN_MESSAGES_FOR_DIGEST = 2
_MAX_CONTINUITY_ENTRIES = 8


def _centurion_home() -> Path:
    from centurion_constants import get_centurion_home

    return get_centurion_home()


def continuity_state_path() -> Path:
    return _centurion_home() / "state" / "memory_continuity.json"


def load_horizon_continuity_config(config: Optional[dict[str, Any]] = None) -> dict[str, Any]:
    """Return ``memory.horizon`` settings with defaults."""
    defaults = {
        "continuity_prefetch": True,
        "session_end_digest": True,
        "digest_max_chars": _DEFAULT_DIGEST_MAX_CHARS,
        "lookback_hours": _DEFAULT_LOOKBACK_HOURS,
    }
    try:
        if config is None:
            from centurion_cli.config import load_config

            config = load_config()
        mem = (config or {}).get("memory") if isinstance(config, dict) else None
        horizon = mem.get("horizon") if isinstance(mem, dict) else None
        if not isinstance(horizon, dict):
            return dict(defaults)
        out = dict(defaults)
        if "continuity_prefetch" in horizon:
            out["continuity_prefetch"] = bool(horizon["continuity_prefetch"])
        if "session_end_digest" in horizon:
            out["session_end_digest"] = bool(horizon["session_end_digest"])
        try:
            out["digest_max_chars"] = max(
                200, int(horizon.get("digest_max_chars") or defaults["digest_max_chars"])
            )
        except (TypeError, ValueError):
            pass
        try:
            out["lookback_hours"] = max(
                1, int(horizon.get("lookback_hours") or defaults["lookback_hours"])
            )
        except (TypeError, ValueError):
            pass
        return out
    except Exception:
        logger.debug("memory_continuity: config load failed", exc_info=True)
        return dict(defaults)


def _read_continuity_state() -> dict[str, Any]:
    path = continuity_state_path()
    try:
        if path.is_file():
            data = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return data
    except Exception:
        logger.debug("memory_continuity: state read failed", exc_info=True)
    return {}


def _write_continuity_state(updates: dict[str, Any]) -> None:
    path = continuity_state_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        state = _read_continuity_state()
        state.update(updates)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        tmp.replace(path)
    except Exception:
        logger.debug("memory_continuity: state write failed", exc_info=True)


def continuity_status() -> dict[str, Any]:
    """Fields for Memory Horizon snapshot gauges."""
    state = _read_continuity_state()
    cfg = load_horizon_continuity_config()
    sessions_last_24h = 0
    last_session_at = None
    try:
        from centurion_state import SessionDB

        db = SessionDB(db_path=_centurion_home() / "state.db")
        try:
            cutoff = time.time() - 86400
            for row in db.search_sessions(limit=50):
                ts = _session_ts(row)
                if ts is None:
                    continue
                if last_session_at is None or ts > last_session_at:
                    last_session_at = ts
                if ts >= cutoff:
                    sessions_last_24h += 1
        finally:
            try:
                db.close()
            except Exception:
                pass
    except Exception:
        logger.debug("memory_continuity: status session scan failed", exc_info=True)

    return {
        "continuity_prefetch": bool(cfg.get("continuity_prefetch")),
        "session_end_digest": bool(cfg.get("session_end_digest")),
        "last_digest_at": state.get("last_digest_at"),
        "last_digest_target": state.get("last_digest_target"),
        "last_digest_skip_reason": state.get("last_digest_skip_reason"),
        "last_digest_preview": state.get("last_digest_preview"),
        "last_session_at": (
            datetime.fromtimestamp(last_session_at, tz=timezone.utc)
            .replace(microsecond=0)
            .isoformat()
            .replace("+00:00", "Z")
            if last_session_at
            else None
        ),
        "sessions_last_24h": sessions_last_24h,
    }


def _session_ts(row: dict[str, Any]) -> Optional[float]:
    for key in ("last_active", "started_at", "updated_at"):
        val = row.get(key)
        if val is None:
            continue
        if isinstance(val, (int, float)):
            return float(val)
        if isinstance(val, str) and val.strip():
            try:
                return float(val)
            except ValueError:
                try:
                    dt = datetime.fromisoformat(val.replace("Z", "+00:00"))
                    return dt.timestamp()
                except ValueError:
                    continue
    return None


def _format_when(ts: Optional[float]) -> str:
    if ts is None:
        return "unknown time"
    try:
        return (
            datetime.fromtimestamp(ts, tz=timezone.utc)
            .strftime("%Y-%m-%d %H:%M UTC")
        )
    except (OSError, OverflowError, ValueError):
        return "unknown time"


def _message_preview(content: Any, limit: int = 180) -> str:
    if content is None:
        return ""
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(str(block.get("text") or ""))
            elif isinstance(block, str):
                parts.append(block)
        text = " ".join(parts)
    else:
        text = str(content)
    text = " ".join(text.split())
    if len(text) > limit:
        return text[: limit - 1] + "…"
    return text


def build_session_recall_digest(
    *,
    current_session_id: Optional[str] = None,
    lookback_hours: int = _DEFAULT_LOOKBACK_HOURS,
    max_sessions: int = _DEFAULT_MAX_SESSIONS,
    max_chars: int = _DEFAULT_DIGEST_MAX_CHARS,
) -> str:
    """Build a compact Session Recall digest of recent other sessions."""
    try:
        from centurion_state import SessionDB

        db = SessionDB(db_path=_centurion_home() / "state.db")
    except Exception:
        logger.debug("memory_continuity: SessionDB unavailable", exc_info=True)
        return ""

    try:
        cutoff = time.time() - (lookback_hours * 3600)
        rows = db.search_sessions(limit=40)
        lines: list[str] = []
        for row in rows:
            sid = row.get("id") or row.get("session_id")
            if not sid or sid == current_session_id:
                continue
            ts = _session_ts(row)
            if ts is not None and ts < cutoff:
                continue
            title = (row.get("title") or "").strip() or "(untitled)"
            preview = ""
            try:
                msgs = db.get_messages(sid) if hasattr(db, "get_messages") else []
                # Prefer last user+assistant snippets (scan tail only).
                for msg in reversed((msgs or [])[-12:]):
                    role = msg.get("role")
                    if role in ("user", "assistant"):
                        snippet = _message_preview(msg.get("content"))
                        if snippet:
                            preview = f"{role}: {snippet}"
                            break
            except Exception:
                pass
            line = f"- [{_format_when(ts)}] {title}"
            if preview:
                line += f" — {preview}"
            lines.append(line)
            if len(lines) >= max_sessions:
                break

        if not lines:
            return ""

        header = (
            "Recent Session Recall (other sessions in the lookback window). "
            "Use session_search for full transcripts."
        )
        body = "\n".join(lines)
        text = f"{header}\n{body}"
        if len(text) > max_chars:
            text = text[: max_chars - 1] + "…"
        return text
    except Exception:
        logger.debug("memory_continuity: digest build failed", exc_info=True)
        return ""
    finally:
        try:
            db.close()
        except Exception:
            pass


def build_continuity_context_block(raw: str) -> str:
    """Fence for ephemeral first-turn continuity injection."""
    if not raw or not str(raw).strip():
        return ""
    return (
        "<memory-continuity>\n"
        "[System note: Memory Horizon continuity from Session Recall — "
        "not new user input. Use session_search for deeper recall; "
        "Vault experiential for sealed being notes.]\n\n"
        f"{str(raw).strip()}\n"
        "</memory-continuity>"
    )


def prefetch_continuity_for_session(
    agent: Any,
    *,
    user_message: str = "",
) -> str:
    """Return fenced continuity text for first turn, else empty.

    Idempotent per agent instance via ``_continuity_prefetch_done``.
    """
    if getattr(agent, "_skip_memory", False):
        return ""
    if getattr(agent, "_continuity_prefetch_done", False):
        return ""

    cfg = getattr(agent, "_horizon_continuity_cfg", None) or load_horizon_continuity_config()
    if not cfg.get("continuity_prefetch", True):
        agent._continuity_prefetch_done = True
        return ""

    # First user turn only (turn count is incremented before this call).
    turn = int(getattr(agent, "_user_turn_count", 1) or 1)
    if turn > 1:
        agent._continuity_prefetch_done = True
        return ""

    max_chars = int(cfg.get("digest_max_chars") or _DEFAULT_DIGEST_MAX_CHARS)
    parts: list[str] = []
    hot = read_hot_cache_continuity(max_chars=max_chars)
    if hot:
        parts.append("Last session continuity note (Hot Cache):\n" + hot)
    recall = build_session_recall_digest(
        current_session_id=getattr(agent, "session_id", None),
        lookback_hours=int(cfg.get("lookback_hours") or _DEFAULT_LOOKBACK_HOURS),
        max_chars=max_chars,
    )
    if recall:
        parts.append(recall)
    agent._continuity_prefetch_done = True
    if not parts:
        return ""
    combined = "\n\n".join(parts)
    if len(combined) > max_chars:
        combined = combined[: max_chars - 1] + "…"
    return build_continuity_context_block(combined)


def _extract_digest_text(messages: list, max_chars: int) -> str:
    """Build a compact transcript snippet for the auxiliary summarizer."""
    parts: list[str] = []
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        role = msg.get("role")
        if role not in ("user", "assistant"):
            continue
        preview = _message_preview(msg.get("content"), limit=400)
        if preview:
            parts.append(f"{role}: {preview}")
    text = "\n".join(parts)
    # Prefer the end of the conversation for "where we left off"
    if len(text) > max_chars * 3:
        text = text[-(max_chars * 3) :]
    return text


_DIGEST_PROMPT = (
    "Summarize this Centurion conversation into a short Memory Horizon "
    "experiential note (3–6 sentences, first person as the agent). Capture: "
    "what mattered, unfinished threads, relationship/fleet-relevant facts, "
    "and decisions. Do NOT include secrets, API keys, or full transcripts. "
    "Return ONLY the note text."
)


def summarize_session_for_continuity(
    messages: list,
    *,
    max_chars: int = _DEFAULT_DIGEST_MAX_CHARS,
    timeout: float = 45.0,
) -> Optional[str]:
    """Use auxiliary LLM to produce an experiential digest, or None."""
    if not messages or len(messages) < _MIN_MESSAGES_FOR_DIGEST:
        return None
    snippet = _extract_digest_text(messages, max_chars=max_chars)
    if len(snippet) < 40:
        return None
    try:
        from agent.auxiliary_client import call_llm

        response = call_llm(
            task="memory_continuity",
            messages=[
                {"role": "system", "content": _DIGEST_PROMPT},
                {"role": "user", "content": snippet},
            ],
            max_tokens=600,
            temperature=0.3,
            timeout=timeout,
        )
        text = (response.choices[0].message.content or "").strip()
        if not text:
            return None
        if len(text) > max_chars:
            text = text[: max_chars - 1] + "…"
        return text
    except Exception as exc:
        logger.warning("memory_continuity: digest summarization failed: %s", exc)
        return None


def hot_cache_continuity_path() -> Path:
    """Dedicated Hot Cache note when Vault is off/locked."""
    return _centurion_home() / "memories" / "CONTINUITY.md"


def read_hot_cache_continuity(max_chars: int = _DEFAULT_DIGEST_MAX_CHARS) -> str:
    """Return the last Hot Cache continuity note, if any."""
    path = hot_cache_continuity_path()
    try:
        if not path.is_file():
            return ""
        text = path.read_text(encoding="utf-8").strip()
        if not text:
            return ""
        if len(text) > max_chars:
            return text[: max_chars - 1] + "…"
        return text
    except Exception:
        logger.debug("memory_continuity: CONTINUITY.md read failed", exc_info=True)
        return ""


def _read_prior_continuity_entries(path: Path) -> list[str]:
    """Return prior digest entries from CONTINUITY.md, newest first.

    Entries keep their ``## `` prefix. Handles the legacy single-note format
    (``# Continuity note``) by normalizing its body into a ``## (legacy)`` entry
    so history is preserved (and ages out) rather than overwritten.
    """
    try:
        raw = path.read_text(encoding="utf-8")
    except Exception:
        return []
    raw = raw.strip()
    if not raw:
        return []
    parts = re.split(r"\n(?=## )", raw)
    entries: list[str] = []
    for idx, part in enumerate(parts):
        part = part.strip()
        if not part:
            continue
        if idx == 0:
            lines = part.splitlines()
            if lines and lines[0].lstrip().startswith("# Continuity"):
                rest = "\n".join(lines[1:]).strip()
                if rest:
                    entries.append(f"## (legacy)\n\n{rest}")
                continue
            entries.append(part)
            continue
        entries.append(part)
    return entries


def _write_hot_cache_continuity(
    text: str,
    *,
    session_id: Optional[str] = None,
) -> Optional[str]:
    """Persist a session-end digest to Hot Cache as a rolling history.

    Newest digest is prepended so the first-turn prefetch (which truncates from
    the top) sees the most recent sessions. History accumulates up to
    ``_MAX_CONTINUITY_ENTRIES`` so a Centurion whose Vault is off or locked does
    not lose its continuity trail every session.
    """
    path = hot_cache_continuity_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        when = (
            datetime.now(timezone.utc)
            .replace(microsecond=0)
            .isoformat()
            .replace("+00:00", "Z")
        )
        entry = f"## {when}"
        if session_id:
            entry += f" — {session_id}"
        entry += f"\n\n{text.strip()}"
        entries = [entry]
        entries.extend(_read_prior_continuity_entries(path)[: _MAX_CONTINUITY_ENTRIES - 1])
        body = "# Continuity notes (most recent first)\n\n" + "\n\n".join(entries) + "\n"
        tmp = path.with_suffix(".tmp")
        tmp.write_text(body, encoding="utf-8")
        tmp.replace(path)
        try:
            path.chmod(0o600)
        except OSError:
            pass
        return "hot_cache:continuity"
    except Exception:
        logger.debug("memory_continuity: CONTINUITY.md write failed", exc_info=True)
        return None


def _propose_vault_experiential(
    text: str,
    *,
    session_id: Optional[str] = None,
    auto_commit: bool = False,
) -> Optional[str]:
    """Propose (and optionally commit) a Vault experiential entry.

    Returns target label for state tracking, or None on skip/failure.
    """
    try:
        from agent.vault import is_initialized, open_vault
        from centurion_cli.config import load_config

        cfg = load_config()
        vault_cfg = cfg.get("vault") if isinstance(cfg, dict) else {}
        if not isinstance(vault_cfg, dict) or not vault_cfg.get("enabled"):
            return None
        if not is_initialized():
            return None
        vault = open_vault(writes_allowed=True)
        if not vault.is_unlocked:
            return None
        proposal = vault.propose(
            memory_type="experiential",
            text=text,
            rationale="Memory Horizon session-end continuity digest",
            tags=["continuity", "session-end"],
            importance=6,
            source_session=session_id,
        )
        require_confirm = bool(vault_cfg.get("require_user_confirm", False))
        if auto_commit or not require_confirm:
            try:
                vault.commit(proposal.id)
                return "vault:experiential:committed"
            except Exception:
                logger.debug("memory_continuity: vault commit failed", exc_info=True)
                return "vault:experiential:proposed"
        return "vault:experiential:proposed"
    except ValueError as exc:
        # Duplicate / validation — not fatal
        logger.debug("memory_continuity: vault propose skipped: %s", exc)
        return None
    except Exception:
        logger.debug("memory_continuity: vault propose failed", exc_info=True)
        return None


def _vault_skip_reason() -> str:
    """Human-readable reason Vault digests were skipped (for Settings UI)."""
    try:
        from agent.vault import is_initialized, open_vault
        from centurion_cli.config import load_config

        cfg = load_config()
        vault_cfg = cfg.get("vault") if isinstance(cfg, dict) else {}
        if not isinstance(vault_cfg, dict) or not vault_cfg.get("enabled"):
            return "Vault off — wrote Hot Cache continuity instead"
        if not is_initialized():
            return "Vault not set up — wrote Hot Cache continuity instead"
        vault = open_vault(writes_allowed=False)
        if not vault.is_unlocked:
            return "Vault locked — wrote Hot Cache continuity instead"
    except Exception:
        pass
    return "Vault unavailable — wrote Hot Cache continuity instead"


def run_session_end_digest(
    agent: Any,
    messages: Optional[list] = None,
) -> None:
    """Session-boundary Continuity writer for Memory Horizon.

    Safe to call from ``shutdown_memory_provider`` / ``commit_memory_session``.
    Never raises.
    """
    try:
        if getattr(agent, "_skip_memory", False):
            return
        if getattr(agent, "_continuity_digest_done", False):
            return
        # Skip non-primary contexts (cron / subagent / flush)
        ctx = getattr(agent, "agent_context", None) or getattr(agent, "_agent_context", None)
        if ctx and ctx not in ("primary", "", None):
            return

        cfg = getattr(agent, "_horizon_continuity_cfg", None) or load_horizon_continuity_config()
        if not cfg.get("session_end_digest", True):
            return

        msgs = messages or []
        if len(msgs) < _MIN_MESSAGES_FOR_DIGEST:
            return

        max_chars = int(cfg.get("digest_max_chars") or _DEFAULT_DIGEST_MAX_CHARS)
        digest = summarize_session_for_continuity(msgs, max_chars=max_chars)
        if not digest:
            return

        session_id = getattr(agent, "session_id", None)
        target = _propose_vault_experiential(digest, session_id=session_id)
        skip_reason = None
        if not target:
            target = _write_hot_cache_continuity(digest, session_id=session_id)
            if target:
                skip_reason = _vault_skip_reason()
        now = (
            datetime.now(timezone.utc)
            .replace(microsecond=0)
            .isoformat()
            .replace("+00:00", "Z")
        )
        updates: dict[str, Any] = {
            "last_digest_at": now,
            "last_digest_target": target or "none",
            "last_digest_preview": digest[:240],
        }
        if skip_reason:
            updates["last_digest_skip_reason"] = skip_reason
        elif target and str(target).startswith("vault:"):
            updates["last_digest_skip_reason"] = None
        _write_continuity_state(updates)
        agent._continuity_digest_done = True
    except Exception:
        logger.debug("memory_continuity: session-end digest failed", exc_info=True)
