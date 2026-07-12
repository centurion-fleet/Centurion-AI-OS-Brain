"""Brain-owned Family Beneficiary Program state for Remote clients.

Business owners refer colleagues (non-family) who purchase Centurion.
Every four successful colleague referrals earns one complimentary Centurion
for a nominated family beneficiary. Cycles reset without limit.
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from centurion_constants import get_centurion_home

REFERRALS_REQUIRED = 4
_STATE_VERSION = 1


def _now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _state_path() -> Path:
    root = get_centurion_home() / "beneficiary"
    root.mkdir(parents=True, exist_ok=True)
    return root / "state.json"


def _empty_cycle() -> dict[str, Any]:
    return {
        "family_beneficiary_first_name": "",
        "colleague_referrals": [],
    }


def _empty_state() -> dict[str, Any]:
    return {
        "version": _STATE_VERSION,
        "current_cycle": _empty_cycle(),
        "lifetime_family_centurions_earned": 0,
        "history": [],
        "updated_at": _now_iso(),
    }


def _load_state() -> dict[str, Any]:
    path = _state_path()
    if not path.exists():
        return _empty_state()
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return _empty_state()
    if not isinstance(raw, dict):
        return _empty_state()
    raw.setdefault("version", _STATE_VERSION)
    raw.setdefault("current_cycle", _empty_cycle())
    raw.setdefault("lifetime_family_centurions_earned", 0)
    raw.setdefault("history", [])
    cycle = raw["current_cycle"]
    if not isinstance(cycle, dict):
        cycle = _empty_cycle()
        raw["current_cycle"] = cycle
    cycle.setdefault("family_beneficiary_first_name", "")
    cycle.setdefault("colleague_referrals", [])
    return raw


def _save_state(state: dict[str, Any]) -> None:
    state["updated_at"] = _now_iso()
    path = _state_path()
    path.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def _successful_count(cycle: dict[str, Any]) -> int:
    referrals = cycle.get("colleague_referrals") or []
    return sum(1 for item in referrals if str(item.get("status")) == "successful")


def _snapshot_from_state(state: dict[str, Any]) -> dict[str, Any]:
    cycle = state.get("current_cycle") or _empty_cycle()
    successful = _successful_count(cycle)
    beneficiary = str(cycle.get("family_beneficiary_first_name") or "").strip()
    return {
        "ok": True,
        "referrals_required": REFERRALS_REQUIRED,
        "current_cycle": {
            "family_beneficiary_first_name": beneficiary,
            "colleague_referrals": list(cycle.get("colleague_referrals") or []),
            "successful_colleague_count": successful,
            "progress_remaining": max(0, REFERRALS_REQUIRED - successful),
            "reward_ready": successful >= REFERRALS_REQUIRED and bool(beneficiary),
        },
        "lifetime_family_centurions_earned": int(state.get("lifetime_family_centurions_earned") or 0),
        "history": list(state.get("history") or []),
        "updated_at": state.get("updated_at") or _now_iso(),
    }


def _maybe_complete_reward(state: dict[str, Any]) -> bool:
    cycle = state["current_cycle"]
    successful = _successful_count(cycle)
    beneficiary = str(cycle.get("family_beneficiary_first_name") or "").strip()
    if successful < REFERRALS_REQUIRED or not beneficiary:
        return False

    state["history"].append(
        {
            "id": str(uuid.uuid4()),
            "family_beneficiary_first_name": beneficiary,
            "colleague_referrals": list(cycle.get("colleague_referrals") or []),
            "completed_at": _now_iso(),
        }
    )
    state["lifetime_family_centurions_earned"] = int(state.get("lifetime_family_centurions_earned") or 0) + 1
    state["current_cycle"] = _empty_cycle()
    return True


def get_beneficiary_snapshot() -> dict[str, Any]:
    """Return the Brain-owned beneficiary program snapshot."""
    state = _load_state()
    _maybe_complete_reward(state)
    _save_state(state)
    return _snapshot_from_state(state)


def set_family_beneficiary(first_name: str) -> dict[str, Any]:
    name = str(first_name or "").strip()
    if not name:
        raise ValueError("Family beneficiary first name is required.")
    if len(name) > 40:
        raise ValueError("Please use a shorter first name.")

    state = _load_state()
    cycle = state["current_cycle"]
    referrals = cycle.get("colleague_referrals") or []
    if referrals and _successful_count(cycle) > 0:
        raise ValueError("Start a new cycle after earning the current reward.")

    cycle["family_beneficiary_first_name"] = name
    _save_state(state)
    return _snapshot_from_state(state)


def submit_colleague_referral(
    *,
    name: str,
    email: str,
    phone: str,
    non_family_attested: bool,
) -> dict[str, Any]:
    if not non_family_attested:
        raise ValueError("Colleague referrals must be non-family members.")

    clean_name = str(name or "").strip()
    clean_email = str(email or "").strip()
    clean_phone = str(phone or "").strip()
    if not clean_name:
        raise ValueError("Colleague name is required.")
    if not clean_email and not clean_phone:
        raise ValueError("Email or phone is required.")

    state = _load_state()
    cycle = state["current_cycle"]
    beneficiary = str(cycle.get("family_beneficiary_first_name") or "").strip()
    if not beneficiary:
        raise ValueError("Nominate a family beneficiary before referring colleagues.")

    if _successful_count(cycle) >= REFERRALS_REQUIRED:
        _maybe_complete_reward(state)
        _save_state(state)
        raise ValueError("This cycle is complete. Nominate your next family beneficiary.")

    referral = {
        "id": str(uuid.uuid4()),
        "name": clean_name,
        "email": clean_email,
        "phone": clean_phone,
        "kind": "colleague",
        "non_family_attested": True,
        "status": "pending",
        "created_at": _now_iso(),
    }
    cycle.setdefault("colleague_referrals", []).append(referral)
    _maybe_complete_reward(state)
    _save_state(state)
    return _snapshot_from_state(state)


def mark_colleague_referral_successful(referral_id: str) -> dict[str, Any]:
    """Ops/admin hook — marks a colleague purchase as successful."""
    rid = str(referral_id or "").strip()
    if not rid:
        raise ValueError("Referral id is required.")

    state = _load_state()
    cycle = state["current_cycle"]
    referrals = cycle.get("colleague_referrals") or []
    found = False
    for item in referrals:
        if str(item.get("id")) == rid:
            item["status"] = "successful"
            item["successful_at"] = _now_iso()
            found = True
            break
    if not found:
        raise ValueError("Referral not found.")

    completed = _maybe_complete_reward(state)
    _save_state(state)
    snapshot = _snapshot_from_state(state)
    snapshot["reward_completed"] = completed
    return snapshot
