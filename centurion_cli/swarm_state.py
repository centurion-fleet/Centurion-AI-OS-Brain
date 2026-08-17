"""Brain-owned collaboration snapshots for Remote and dashboard clients.

This module is intentionally UI-shaped but not UI-owned.  The Linux
Centurion Brain remains the source of truth: local collaborations are read
from kanban boards, cloud collaborations are projected from Mission Control,
and mobile clients receive only slim mission-progress DTOs.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any


def _now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _iso_from_epoch(value: int | None) -> str:
    if not value:
        return _now_iso()
    return (
        datetime.fromtimestamp(int(value), tz=timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def _coerce_iso(value: Any) -> str:
    text = str(value or "").strip()
    return text or _now_iso()


def _pulse_from_tasks(status: str, sprint_phase: str, tasks: list[Any]) -> str:
    if any(getattr(task, "status", "") == "blocked" for task in tasks):
        return "blocked"
    if status == "completed":
        return "complete"
    if any(getattr(task, "status", "") == "running" for task in tasks):
        return "active"
    if sprint_phase in {"execute", "plan"}:
        return "active"
    return "idle"


def _pulse_from_project(status: str, sprint_phase: str, blocked_tasks: int) -> str:
    if blocked_tasks > 0:
        return "blocked"
    if status == "completed":
        return "complete"
    if sprint_phase in {"execute", "plan"}:
        return "active"
    if status == "draft":
        return "idle"
    return "idle"


def _attention_score(pulse: str, pending_signal_count: int) -> int:
    base = {
        "waiting": 100,
        "attention": 90,
        "blocked": 70,
        "active": 50,
        "forming": 40,
        "idle": 20,
        "complete": 5,
    }.get(pulse, 20)
    return base + pending_signal_count * 5


def _task_signal_id(board_slug: str, task_id: str) -> str:
    return f"{board_slug}:{task_id}:signal"


def _task_outcome_id(board_slug: str, task_id: str) -> str:
    return f"{board_slug}:{task_id}:outcome"


def _result_preview(text: str | None, *, limit: int = 240) -> str:
    raw = str(text or "").strip()
    if len(raw) <= limit:
        return raw
    return raw[: limit - 1] + "…"


def _find_swarm_topology(
    conn: Any,
    tasks: list[Any],
) -> tuple[str | None, dict[str, Any], dict[str, Any]]:
    """Locate kanban_swarm_v1 root via blackboard topology (if any)."""
    try:
        from centurion_cli.kanban_swarm import latest_blackboard
    except Exception:
        return None, {}, {}

    by_id = {str(t.id): t for t in tasks}
    # Prefer done roots; fall back to any task with topology.
    ordered = sorted(
        tasks,
        key=lambda t: (0 if getattr(t, "status", "") == "done" else 1, -(getattr(t, "created_at", 0) or 0)),
    )
    for task in ordered:
        try:
            board = latest_blackboard(conn, task.id)
        except Exception:
            continue
        topo = board.get("topology")
        if isinstance(topo, dict) and topo.get("worker_ids") and topo.get("verifier_id"):
            return str(task.id), topo, board
    # Topology may exist even if root not in the list_tasks window.
    for task in tasks:
        tid = str(getattr(task, "id", "") or "")
        if tid in by_id and "Swarm:" in str(getattr(task, "title", "") or ""):
            try:
                board = latest_blackboard(conn, tid)
            except Exception:
                continue
            topo = board.get("topology")
            if isinstance(topo, dict):
                return tid, topo, board
    return None, {}, {}


def _swarm_workers_payload(
    tasks_by_id: dict[str, Any],
    topology: dict[str, Any],
) -> list[dict[str, Any]]:
    workers: list[dict[str, Any]] = []
    for wid in topology.get("worker_ids") or []:
        task = tasks_by_id.get(str(wid))
        if not task:
            workers.append(
                {
                    "task_id": str(wid),
                    "title": "Worker",
                    "assignee": "",
                    "role": "worker",
                    "status": "unknown",
                    "result": "",
                }
            )
            continue
        workers.append(
            {
                "task_id": task.id,
                "title": task.title,
                "assignee": task.assignee or "",
                "role": "worker",
                "status": task.status,
                "result": _result_preview(task.result),
            }
        )
    for role, key in (("verifier", "verifier_id"), ("synthesizer", "synthesizer_id")):
        rid = topology.get(key)
        if not rid:
            continue
        task = tasks_by_id.get(str(rid))
        if not task:
            workers.append(
                {
                    "task_id": str(rid),
                    "title": role.title(),
                    "assignee": "",
                    "role": role,
                    "status": "unknown",
                    "result": "",
                }
            )
            continue
        workers.append(
            {
                "task_id": task.id,
                "title": task.title,
                "assignee": task.assignee or "",
                "role": role,
                "status": task.status,
                "result": _result_preview(task.result),
            }
        )
    return workers


def _participants_from_workers(workers: list[dict[str, Any]]) -> list[dict[str, Any]]:
    participants: list[dict[str, Any]] = [
        {
            "id": "human-owner",
            "name": "You",
            "kind": "human",
            "role": "owner",
            "is_active": False,
        }
    ]
    seen: set[str] = set()
    for w in workers:
        assignee = str(w.get("assignee") or "").strip()
        if not assignee or assignee in seen:
            # Still show a slot even if duplicate profile shares assignee.
            key = f"{assignee}:{w.get('role')}:{w.get('task_id')}"
        else:
            key = assignee
            seen.add(assignee)
        participants.append(
            {
                "id": str(w.get("task_id") or key),
                "name": assignee or str(w.get("title") or "Centurion"),
                "kind": "centurion",
                "role": str(w.get("role") or "worker"),
                "is_active": str(w.get("status") or "") == "running",
                "status": str(w.get("status") or ""),
                "title": str(w.get("title") or ""),
            }
        )
    return participants


def _local_board_snapshot() -> dict[str, Any]:
    """Return collaboration summaries derived from local kanban boards."""
    try:
        from centurion_cli import kanban_db
    except Exception:
        return {"swarms": [], "signals": [], "outcomes": [], "activities": []}

    swarms: list[dict[str, Any]] = []
    signals: list[dict[str, Any]] = []
    outcomes: list[dict[str, Any]] = []
    activities: list[dict[str, Any]] = []

    try:
        boards = kanban_db.list_boards(include_archived=False)
    except Exception:
        return {"swarms": [], "signals": [], "outcomes": [], "activities": []}

    for board in boards:
        slug = str(board.get("slug") or board.get("id") or "").strip()
        if not slug:
            continue
        conn = None
        tasks: list[Any] = []
        root_id = None
        topology: dict[str, Any] = {}
        blackboard: dict[str, Any] = {}
        try:
            conn = kanban_db.connect(board=slug)
            # Wider window so swarm roots + children stay visible together.
            tasks = kanban_db.list_tasks(conn, include_archived=False, order_by="updated", limit=200)
            root_id, topology, blackboard = _find_swarm_topology(conn, tasks)
        except Exception:
            continue
        finally:
            try:
                if conn is not None:
                    conn.close()
            except Exception:
                pass

        # Hide a completely empty default board; it is not a collaboration yet.
        if slug == kanban_db.DEFAULT_BOARD and not tasks:
            continue

        blocked = [task for task in tasks if task.status == "blocked"]
        running = [task for task in tasks if task.status == "running"]
        done = [task for task in tasks if task.status == "done"]
        pulse = _pulse_from_tasks("active", "execute", tasks)
        if topology and not running and not blocked:
            worker_statuses = []
            tasks_by_id = {str(t.id): t for t in tasks}
            for wid in topology.get("worker_ids") or []:
                t = tasks_by_id.get(str(wid))
                if t:
                    worker_statuses.append(t.status)
            if worker_statuses and all(s == "todo" for s in worker_statuses):
                pulse = "forming"
            elif worker_statuses and all(s in {"done", "archived"} for s in worker_statuses):
                # Verifier/synthesizer may still be pending.
                pulse = pulse
        updated_at = max((task.started_at or task.created_at for task in tasks), default=None)
        title = str(board.get("name") or board.get("title") or slug.replace("-", " ").title())
        objective = str(
            (topology.get("goal") if isinstance(topology, dict) else None)
            or board.get("description")
            or "Your Centurions are working together on this collaboration."
        )

        tasks_by_id = {str(t.id): t for t in tasks}
        workers_payload = _swarm_workers_payload(tasks_by_id, topology) if topology else []
        if workers_payload:
            participants = _participants_from_workers(workers_payload)
        else:
            participants = [
                {
                    "id": "human-owner",
                    "name": "You",
                    "kind": "human",
                    "role": "owner",
                    "is_active": False,
                },
                {
                    "id": "centurion-worker",
                    "name": "Your Centurion",
                    "kind": "centurion",
                    "role": "operator",
                    "is_active": bool(running),
                },
            ]

        # Public blackboard view — drop internal topology / author bookkeeping noise.
        public_bb = {
            k: v
            for k, v in (blackboard or {}).items()
            if k not in {"topology", "_authors"}
        }

        swarms.append(
            {
                "id": slug,
                "mission_id": board.get("mission_id"),
                "display_name": title,
                "objective": objective,
                "status": "running" if pulse != "complete" else "complete",
                "pulse": "waiting" if blocked else pulse,
                "formation_source": "swarm" if topology else "manual",
                "participants": participants,
                "workers": workers_payload,
                "blackboard": public_bb,
                "root_id": root_id,
                "pending_signal_count": len(blocked),
                "updated_at": _iso_from_epoch(updated_at),
                "completed_at": _iso_from_epoch(max((task.completed_at or 0 for task in done), default=0))
                if done and len(done) == len(tasks)
                else None,
                "attention_score": _attention_score("waiting" if blocked else pulse, len(blocked)),
                "source": "kanban",
                "kanban_board_slug": slug,
            }
        )

        for task in blocked[:5]:
            signals.append(
                {
                    "id": _task_signal_id(slug, task.id),
                    "swarm_id": slug,
                    "type": "decision",
                    "message": task.last_failure_error
                    or task.body
                    or f"{task.title} needs your choice.",
                    "status": "open",
                    "created_at": _iso_from_epoch(task.started_at or task.created_at),
                }
            )

        # Prefer synthesizer result as the headline outcome when present.
        synth_id = str((topology or {}).get("synthesizer_id") or "")
        synth_task = tasks_by_id.get(synth_id) if synth_id else None
        if synth_task and synth_task.result and synth_task.status == "done":
            outcomes.append(
                {
                    "id": _task_outcome_id(slug, synth_task.id),
                    "swarm_id": slug,
                    "description": synth_task.result,
                    "status": "ready",
                    "owner_name": synth_task.assignee or "Synthesizer",
                    "role": "synthesizer",
                    "created_at": _iso_from_epoch(
                        synth_task.completed_at or synth_task.started_at or synth_task.created_at
                    ),
                }
            )
        else:
            for task in done[:5]:
                if not task.result:
                    continue
                outcomes.append(
                    {
                        "id": _task_outcome_id(slug, task.id),
                        "swarm_id": slug,
                        "description": task.result,
                        "status": "ready",
                        "owner_name": task.assignee or "Your Centurion",
                        "created_at": _iso_from_epoch(
                            task.completed_at or task.started_at or task.created_at
                        ),
                    }
                )

        for task in tasks[:8]:
            activities.append(
                {
                    "id": f"{slug}:{task.id}:activity",
                    "swarm_id": slug,
                    "kind": task.status,
                    "summary": task.title,
                    "at": _iso_from_epoch(task.started_at or task.created_at),
                }
            )

    return {
        "swarms": swarms,
        "signals": signals,
        "outcomes": outcomes,
        "activities": activities,
    }


def _portal_snapshot(since: str | None = None) -> dict[str, Any]:
    """Return Mission Control projection when a project token is configured."""
    try:
        from gateway.swarm_mc import SwarmMcClient, load_mc_config
    except Exception:
        return {
            "ok": False,
            "source": "local",
            "message": "Mission Control client unavailable",
            "swarms": [],
            "projects": [],
            "targets": [],
            "tasks": [],
        }

    cfg = load_mc_config()
    project_id = cfg.get("project_id", "")
    token = cfg.get("project_token", "")
    install_id = cfg.get("install_id", "")
    if not project_id or not token.startswith("ctk_proj_") or not install_id:
        return {
            "ok": False,
            "source": "local",
            "connected": False,
            "message": "",
            "swarms": [],
            "projects": [],
            "targets": [],
            "tasks": [],
        }

    try:
        client = SwarmMcClient(project_token=token, install_id=install_id, timeout=8)
        data = client.sync(project_id, since)
    except Exception as exc:
        return {
            "ok": False,
            "source": "local",
            "message": f"Mission Control sync failed: {exc}",
            "swarms": [],
            "projects": [],
            "targets": [],
            "tasks": [],
        }
    projects = data.get("projects") or []
    targets = data.get("targets") or []
    tasks = data.get("tasks") or []
    if not projects and project_id:
        projects = [
            {
                "id": project_id,
                "title": data.get("project_title") or "Mission Control Project",
                "purpose": data.get("project_purpose"),
                "slug": data.get("project_slug") or project_id,
                "status": data.get("project_status") or "active",
                "sprint_phase": data.get("sprint_phase") or "execute",
                "sort_order": 0,
                "created_at": data.get("created_at") or "",
                "updated_at": data.get("updated_at") or "",
            }
        ]

    swarms: list[dict[str, Any]] = []
    for project in projects:
        pid = str(project.get("id") or project_id)
        project_tasks = [t for t in tasks if str(t.get("project_id", "")) == pid]
        blocked = sum(1 for t in project_tasks if t.get("status") == "blocked")
        pulse = _pulse_from_project(
            str(project.get("status") or "active"),
            str(project.get("sprint_phase") or "execute"),
            blocked,
        )
        swarms.append(
            {
                "id": pid,
                "mission_id": project.get("program_id") or project.get("mission_id"),
                "display_name": project.get("title") or "Collaboration",
                "objective": project.get("purpose") or "",
                "status": "complete" if project.get("status") == "completed" else "running",
                "pulse": pulse,
                "formation_source": "manual",
                "participants": [],
                "pending_signal_count": blocked,
                "updated_at": _coerce_iso(project.get("updated_at")),
                "attention_score": _attention_score(pulse, blocked),
                "source": "portal",
                "portal_project_id": pid,
            }
        )

    return {
        "ok": True,
        "source": "portal",
        "project_id": project_id,
        "swarms": swarms,
        "projects": projects,
        "targets": targets,
        "tasks": tasks,
    }


def get_swarm_snapshot(*, since: str | None = None) -> dict[str, Any]:
    """Return the Brain-owned collaboration snapshot for Remote/dashboard.

    Local boards always. Portal Mission Control sync runs only when mc.json
    is configured, with a short timeout so a down portal cannot stall Focus.
    """
    local = _local_board_snapshot()
    portal = _portal_snapshot(since=since)
    swarms = list(local["swarms"])
    seen = {str(item.get("id") or "") for item in swarms}
    portal_ok = bool(portal.get("ok"))
    if portal_ok:
        for item in portal.get("swarms") or []:
            if not isinstance(item, dict):
                continue
            sid = str(item.get("id") or "")
            if sid and sid not in seen:
                swarms.append(item)
                seen.add(sid)
        projects = list(portal.get("projects") or [])
        targets = list(portal.get("targets") or [])
        tasks = list(portal.get("tasks") or [])
        message = None
    else:
        projects, targets, tasks = [], [], []
        message = str(portal.get("message") or "").strip() or None
    swarms.sort(key=lambda item: int(item.get("attention_score") or 0), reverse=True)
    return {
        "ok": True,
        "source": "brain",
        "portal": portal,
        "swarms": swarms,
        "signals": local["signals"],
        "outcomes": local["outcomes"],
        "activities": local["activities"],
        "projects": projects,
        "targets": targets,
        "tasks": tasks,
        "message": message,
    }


def resolve_signal(signal_id: str, *, choice_note: str = "") -> dict[str, Any]:
    """Resolve a human Signal on the Brain (unblock kanban task) + optional Vault receipt.

    Signal ids are ``{board_slug}:{task_id}:signal``.
    """
    raw = str(signal_id or "").strip()
    parts = raw.split(":")
    if len(parts) < 3 or parts[-1] != "signal":
        return {
            "ok": False,
            "error": "Unrecognized signal id.",
            "signal_id": raw,
        }
    board_slug = parts[0]
    task_id = ":".join(parts[1:-1])
    if not board_slug or not task_id:
        return {"ok": False, "error": "Malformed signal id.", "signal_id": raw}

    try:
        from centurion_cli import kanban_db
    except Exception as exc:
        return {"ok": False, "error": str(exc), "signal_id": raw}

    try:
        conn = kanban_db.connect(board=board_slug)
        try:
            ok = kanban_db.unblock_task(conn, task_id)
        finally:
            conn.close()
    except Exception as exc:
        return {"ok": False, "error": str(exc), "signal_id": raw, "swarm_id": board_slug}

    vault_entry_id = None
    try:
        vault_entry_id = _deposit_decision_receipt(
            board_slug=board_slug,
            task_id=task_id,
            choice_note=choice_note,
        )
    except Exception:
        vault_entry_id = None

    return {
        "ok": True,
        "signal_id": raw,
        "swarm_id": board_slug,
        "task_id": task_id,
        "unblocked": bool(ok),
        "vault_entry_id": vault_entry_id,
        "message": "Choice recorded. Your Sovereigns can continue.",
    }


def create_collaboration_board(
    *,
    name: str,
    objective: str = "",
    mission_id: str | None = None,
) -> dict[str, Any]:
    """Create a LAN/local collaboration board tethered to Life Mission when provided."""
    title = str(name or "").strip()
    if not title:
        return {"ok": False, "error": "Collaboration name is required."}

    try:
        from centurion_cli import kanban_db
    except Exception as exc:
        return {"ok": False, "error": str(exc)}

    # Slug from name — keep readable and unique-ish
    import re
    import time as _time

    base = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-") or "collaboration"
    slug = f"{base[:40]}-{int(_time.time()) % 100000}"
    try:
        meta = kanban_db.create_board(
            slug,
            name=title,
            description=str(objective or "").strip()
            or "Your Centurions are working together on this collaboration.",
            mission_id=str(mission_id).strip() if mission_id else None,
        )
    except Exception as exc:
        return {"ok": False, "error": str(exc)}

    snapshot = get_swarm_snapshot()
    swarm = next(
        (s for s in snapshot.get("swarms", []) if s.get("id") == meta.get("slug") or s.get("id") == slug),
        None,
    )
    return {
        "ok": True,
        "swarm_id": slug,
        "board": meta,
        "swarm": swarm,
        "snapshot": snapshot,
        "message": f"Collaboration “{title}” is ready on this Sovereign.",
    }


def create_local_swarm(
    *,
    goal: str,
    workers: list[dict[str, Any]] | None = None,
    verifier_assignee: str = "",
    synthesizer_assignee: str = "",
    name: str = "",
    board: str | None = None,
    mission_id: str | None = None,
    idempotency_key: str | None = None,
    dispatch: bool = True,
) -> dict[str, Any]:
    """Create a local board (if needed) and a Kanban Swarm v1 task graph.

    Portal Mission Control is never used. Assignees must be real Centurion
    profiles so the gateway dispatcher can spawn ``centurion -p <profile>``.
    """
    goal_text = str(goal or "").strip()
    if not goal_text:
        return {"ok": False, "error": "A collaboration goal is required."}

    try:
        from centurion_cli import kanban_db
        from centurion_cli.kanban_swarm import SwarmWorkerSpec, create_swarm
        from centurion_cli.profiles import profile_exists
    except Exception as exc:
        return {"ok": False, "error": str(exc)}

    raw_workers = workers if isinstance(workers, list) else []
    if len(raw_workers) < 1:
        return {"ok": False, "error": "At least one worker is required."}

    specs: list[SwarmWorkerSpec] = []
    for i, item in enumerate(raw_workers, start=1):
        if not isinstance(item, dict):
            return {"ok": False, "error": f"workers[{i}] must be an object."}
        profile = str(item.get("profile") or "").strip()
        title = str(item.get("title") or "").strip() or f"Worker {i}"
        body = str(item.get("body") or title).strip()
        skills_raw = item.get("skills") or []
        if isinstance(skills_raw, str):
            skills = [s.strip() for s in skills_raw.split(",") if s.strip()]
        elif isinstance(skills_raw, list):
            skills = [str(s).strip() for s in skills_raw if str(s).strip()]
        else:
            skills = []
        try:
            priority = int(item.get("priority") or 0)
        except (TypeError, ValueError):
            priority = 0
        if not profile:
            return {"ok": False, "error": f"workers[{i}].profile is required."}
        if profile != "default" and not profile_exists(profile):
            return {
                "ok": False,
                "error": f"Profile “{profile}” does not exist. Create it with centurion -p {profile} setup.",
                "code": "PROFILE_MISSING",
            }
        specs.append(
            SwarmWorkerSpec(
                profile=profile,
                title=title,
                body=body,
                skills=skills,
                priority=priority,
            )
        )

    verifier = str(verifier_assignee or "").strip() or specs[0].profile
    synthesizer = str(synthesizer_assignee or "").strip() or specs[0].profile
    for label, assignee in (("verifier", verifier), ("synthesizer", synthesizer)):
        if assignee != "default" and not profile_exists(assignee):
            return {
                "ok": False,
                "error": f"{label.title()} profile “{assignee}” does not exist.",
                "code": "PROFILE_MISSING",
            }

    slug = str(board or "").strip() or None
    board_meta: dict[str, Any] | None = None
    if slug:
        try:
            boards = {str(b.get("slug") or ""): b for b in kanban_db.list_boards(include_archived=False)}
        except Exception as exc:
            return {"ok": False, "error": str(exc)}
        if slug not in boards:
            return {"ok": False, "error": f"Board “{slug}” was not found.", "code": "BOARD_MISSING"}
        board_meta = boards[slug]
    else:
        board_name = str(name or "").strip() or goal_text.splitlines()[0][:60]
        created = create_collaboration_board(
            name=board_name,
            objective=goal_text,
            mission_id=mission_id,
        )
        if not created.get("ok"):
            return created
        slug = str(created.get("swarm_id") or "").strip()
        board_meta = created.get("board") if isinstance(created.get("board"), dict) else {"slug": slug}
        if not slug:
            return {"ok": False, "error": "Could not create a collaboration board."}

    conn = None
    created_swarm = None
    dispatched = False
    dispatch_error = None
    try:
        conn = kanban_db.connect(board=slug)
        created_swarm = create_swarm(
            conn,
            goal=goal_text,
            workers=specs,
            verifier_assignee=verifier,
            synthesizer_assignee=synthesizer,
            root_title=f"Swarm: {goal_text.splitlines()[0][:80]}",
            idempotency_key=str(idempotency_key).strip() if idempotency_key else None,
            created_by="desktop-swarm",
        )
        if dispatch:
            try:
                kanban_db.dispatch_once(conn, board=slug, dry_run=False)
                dispatched = True
            except Exception as exc:
                dispatch_error = str(exc)
    except Exception as exc:
        return {"ok": False, "error": str(exc)}
    finally:
        try:
            if conn is not None:
                conn.close()
        except Exception:
            pass

    if created_swarm is None:
        return {"ok": False, "error": "Swarm graph was not created."}

    snapshot = get_swarm_snapshot()
    swarm = next((s for s in snapshot.get("swarms", []) if s.get("id") == slug), None)
    return {
        "ok": True,
        "swarm_id": slug,
        "board": board_meta,
        "root_id": created_swarm.root_id,
        "worker_ids": list(created_swarm.worker_ids),
        "verifier_id": created_swarm.verifier_id,
        "synthesizer_id": created_swarm.synthesizer_id,
        "dispatched": dispatched,
        "dispatch_error": dispatch_error,
        "swarm": swarm,
        "snapshot": snapshot,
        "message": (
            f"Collaboration swarm formed on board “{slug}”. "
            + (
                "Workers nudged for dispatch."
                if dispatched
                else "Start the gateway so workers can run."
            )
        ),
    }


def _deposit_decision_receipt(
    *,
    board_slug: str,
    task_id: str,
    choice_note: str = "",
) -> str | None:
    """Best-effort experiential Vault note when Vault is unlocked."""
    try:
        from agent.vault import open_vault
    except Exception:
        return None
    vault = open_vault(writes_allowed=True)
    if not vault.is_unlocked:
        return None
    note = (choice_note or "").strip()
    text = (
        f"Collaboration decision on {board_slug}: resolved signal for task {task_id}."
        + (f" Note: {note}" if note else "")
    )
    prop = vault.propose(
        memory_type="experiential",
        text=text,
        rationale="Human resolved a Collaboration Signal on Remote.",
        tags=["collaboration", "decision", board_slug],
        importance=6,
    )
    entry = vault.commit(prop.id)
    return entry.id
