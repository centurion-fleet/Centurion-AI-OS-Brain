"""Autonomy level and reporting/oversight preferences.

Remote apps (iOS / Desktop) and ``remote_bridge`` read/write these via
``oversight_get`` / ``oversight_put``. Values live in ``config.yaml`` under
``agent.autonomy_level`` and ``oversight.*``. Changing a level applies a
documented approvals + oversight preset; Oversight toggles remain editable
afterward.
"""

from __future__ import annotations

from copy import deepcopy
from typing import Any

AUTONOMY_LEVELS = ("strict", "balanced", "proactive", "high")
REPORT_CADENCES = ("off", "when_needed", "daily", "after_significant_actions")

# Level → (approvals.mode, ask_before_initiative, confirm_dangerous, confirm_external)
_AUTONOMY_PRESETS: dict[str, dict[str, Any]] = {
    "strict": {
        "approvals_mode": "manual",
        "ask_before_initiative": True,
        "confirm_dangerous_commands": True,
        "confirm_external_actions": True,
    },
    "balanced": {
        "approvals_mode": "manual",
        "ask_before_initiative": True,
        "confirm_dangerous_commands": True,
        "confirm_external_actions": True,
    },
    "proactive": {
        "approvals_mode": "smart",
        "ask_before_initiative": False,
        "confirm_dangerous_commands": True,
        "confirm_external_actions": True,
    },
    "high": {
        "approvals_mode": "off",
        "ask_before_initiative": False,
        "confirm_dangerous_commands": False,
        "confirm_external_actions": False,
    },
}

_LEVEL_GUIDANCE = {
    "strict": (
        "Autonomy: Strict. Follow the user's instructions exactly. "
        "Do not take initiative, suggest unsolicited improvements, or start "
        "side tasks unless the user explicitly asks."
    ),
    "balanced": (
        "Autonomy: Balanced. Follow the user's instructions, with light "
        "interpretation when intent is clear. Ask before taking initiative "
        "on new work."
    ),
    "proactive": (
        "Autonomy: Proactive. You may suggest improvements and take small, "
        "low-risk actions that clearly advance the user's goal. Confirm "
        "before anything consequential or hard to undo."
    ),
    "high": (
        "Autonomy: High. Maximum freedom within the user's stated boundaries "
        "and never-do rules. Prefer decisive action; still respect explicit "
        "constraints and safety limits."
    ),
}

_CADENCE_GUIDANCE = {
    "off": "Reporting: Do not proactively report progress unless asked.",
    "when_needed": (
        "Reporting: Report back when a choice is needed, something fails, "
        "or a significant milestone completes."
    ),
    "daily": (
        "Reporting: Prefer a concise daily-style status when meaningful "
        "progress accumulates; otherwise stay quiet."
    ),
    "after_significant_actions": (
        "Reporting: After each significant action, briefly report what you "
        "did and the outcome."
    ),
}


def normalize_autonomy_level(value: Any) -> str:
    level = str(value or "balanced").strip().lower()
    return level if level in AUTONOMY_LEVELS else "balanced"


def normalize_report_cadence(value: Any) -> str:
    cadence = str(value or "when_needed").strip().lower()
    return cadence if cadence in REPORT_CADENCES else "when_needed"


def _bool(value: Any, default: bool) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    if isinstance(value, (int, float)):
        return bool(value)
    text = str(value).strip().lower()
    if text in {"1", "true", "yes", "on"}:
        return True
    if text in {"0", "false", "no", "off"}:
        return False
    return default


def get_oversight_snapshot(config: dict[str, Any] | None = None) -> dict[str, Any]:
    """Return the current autonomy + oversight preferences."""
    if config is None:
        from centurion_cli.config import load_config

        config = load_config()

    agent = config.get("agent") if isinstance(config.get("agent"), dict) else {}
    oversight = config.get("oversight") if isinstance(config.get("oversight"), dict) else {}
    approvals = config.get("approvals") if isinstance(config.get("approvals"), dict) else {}

    level = normalize_autonomy_level(agent.get("autonomy_level"))
    return {
        "autonomy_level": level,
        "report_cadence": normalize_report_cadence(oversight.get("report_cadence")),
        "ask_before_initiative": _bool(oversight.get("ask_before_initiative"), True),
        "confirm_dangerous_commands": _bool(
            oversight.get("confirm_dangerous_commands"), True
        ),
        "confirm_external_actions": _bool(
            oversight.get("confirm_external_actions"), True
        ),
        "approvals_mode": str(approvals.get("mode") or "manual").strip().lower(),
        "yolo_for_remote": level == "high"
        or str(approvals.get("mode") or "").strip().lower() == "off",
    }


def apply_autonomy_preset(config: dict[str, Any], level: str) -> dict[str, Any]:
    """Apply the documented preset for *level* onto a config copy."""
    level = normalize_autonomy_level(level)
    preset = _AUTONOMY_PRESETS[level]
    out = deepcopy(config)

    agent = out.setdefault("agent", {})
    if not isinstance(agent, dict):
        agent = {}
        out["agent"] = agent
    agent["autonomy_level"] = level

    approvals = out.setdefault("approvals", {})
    if not isinstance(approvals, dict):
        approvals = {}
        out["approvals"] = approvals
    approvals["mode"] = preset["approvals_mode"]

    oversight = out.setdefault("oversight", {})
    if not isinstance(oversight, dict):
        oversight = {}
        out["oversight"] = oversight
    oversight["ask_before_initiative"] = preset["ask_before_initiative"]
    oversight["confirm_dangerous_commands"] = preset["confirm_dangerous_commands"]
    oversight["confirm_external_actions"] = preset["confirm_external_actions"]
    if "report_cadence" not in oversight:
        oversight["report_cadence"] = "when_needed"
    else:
        oversight["report_cadence"] = normalize_report_cadence(
            oversight.get("report_cadence")
        )

    return out


def put_oversight_prefs(
    updates: dict[str, Any],
    *,
    apply_level_preset: bool = True,
) -> dict[str, Any]:
    """Merge oversight updates into config.yaml and return the new snapshot.

    When ``autonomy_level`` is present and ``apply_level_preset`` is true,
    the level preset is applied first, then any explicit oversight fields
    in *updates* override the preset (so the Oversight screen can refine).
    """
    from centurion_cli.config import load_config, save_config

    config = load_config()
    level_in = updates.get("autonomy_level")
    if level_in is not None and apply_level_preset:
        config = apply_autonomy_preset(config, str(level_in))
    elif level_in is not None:
        agent = config.setdefault("agent", {})
        if not isinstance(agent, dict):
            agent = {}
            config["agent"] = agent
        agent["autonomy_level"] = normalize_autonomy_level(level_in)

    oversight = config.setdefault("oversight", {})
    if not isinstance(oversight, dict):
        oversight = {}
        config["oversight"] = oversight

    if "report_cadence" in updates:
        oversight["report_cadence"] = normalize_report_cadence(
            updates.get("report_cadence")
        )
    if "ask_before_initiative" in updates:
        oversight["ask_before_initiative"] = _bool(
            updates.get("ask_before_initiative"), True
        )
    if "confirm_dangerous_commands" in updates:
        confirm = _bool(updates.get("confirm_dangerous_commands"), True)
        oversight["confirm_dangerous_commands"] = confirm
        # Keep approvals.mode coherent with the dangerous-command toggle
        # unless autonomy is high (off) or the caller set level this turn.
        approvals = config.setdefault("approvals", {})
        if not isinstance(approvals, dict):
            approvals = {}
            config["approvals"] = approvals
        level = normalize_autonomy_level(
            (config.get("agent") or {}).get("autonomy_level")
            if isinstance(config.get("agent"), dict)
            else "balanced"
        )
        if level != "high":
            if confirm:
                if str(approvals.get("mode") or "").lower() == "off":
                    approvals["mode"] = (
                        "smart" if level == "proactive" else "manual"
                    )
            else:
                approvals["mode"] = "off"

    if "confirm_external_actions" in updates:
        oversight["confirm_external_actions"] = _bool(
            updates.get("confirm_external_actions"), True
        )

    save_config(config)
    return get_oversight_snapshot(config)


def should_enable_remote_yolo(config: dict[str, Any] | None = None) -> bool:
    """Whether remote chat may set CENTURION_YOLO_MODE."""
    return bool(get_oversight_snapshot(config).get("yolo_for_remote"))


def build_oversight_guidance(config: dict[str, Any] | None = None) -> str:
    """Stable system-prompt guidance for autonomy + reporting preferences."""
    snap = get_oversight_snapshot(config)
    parts = [
        _LEVEL_GUIDANCE[snap["autonomy_level"]],
        _CADENCE_GUIDANCE[snap["report_cadence"]],
    ]
    if snap["ask_before_initiative"]:
        parts.append(
            "Ask the user before taking initiative on new tasks that were "
            "not requested."
        )
    else:
        parts.append(
            "You may take initiative on small actions that clearly advance "
            "the current goal."
        )
    if snap["confirm_dangerous_commands"]:
        parts.append(
            "Require confirmation before dangerous or hard-to-undo commands."
        )
    if snap["confirm_external_actions"]:
        parts.append(
            "Require confirmation before external actions such as sending "
            "messages, spending, or contacting people outside this session."
        )
    return " ".join(parts)
