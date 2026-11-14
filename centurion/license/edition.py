"""The machine's edition, resolved once at boot.

business/EDITIONS.md §8: four editions, fixed at provisioning and bound to the
machine fingerprint. **The licence server stays authoritative** — an edition
edited on a machine is a lie until the next check-in.

This module is the one place that turns the entitlement into the answers the rest
of the product needs:

    edition.tier                 which of the four this machine is
    edition.seat_limit           how many named users it may carry
    edition.instrument_unlocked  greyed out, or live
    edition.label                the published word for it

`resolve_edition()` runs at boot and writes a boot record. On the next boot that
record is the evidence: if the tier in the entitlement file no longer matches what
this fingerprint booted last time, and no verified check-in happened in between,
the machine keeps the MORE RESTRICTIVE of the two and records a tamper event. A
local edit can therefore never grant a capability; only the licence server can.

There is no self-upgrade path here, and no admin override. An upgrade is a new
machine with a new entitlement — that is the decision the whole product rests on.
"""

from __future__ import annotations

import json
import logging
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional

from centurion.license.audit import append_audit
from centurion.license.store import (
    EDITION_TIERS,
    Entitlement,
    load_entitlement,
    normalise_tier,
)

logger = logging.getLogger(__name__)

BOOT_RECORD_FILENAME = "edition_boot.json"

# The published words (EDITIONS.md §11, ruling 6).
EDITION_LABELS = {
    "brain": "Centurion Brain",
    "accountant": "Centurion Accountant Brain",
    "association": "Centurion Association Brain",
    "practice": "Centurion Accountant Practice",
}

# Capability order. Used only to decide which side of a disagreement is the safe
# one: when in doubt the machine takes the lower rank.
_EDITION_RANK = {"brain": 0, "accountant": 1, "association": 1, "practice": 2}


def edition_rank(tier: Optional[str]) -> int:
    return _EDITION_RANK.get(normalise_tier(tier), 0)


def more_restrictive(a: Optional[str], b: Optional[str]) -> str:
    """The edition that grants less. The default answer to any doubt."""
    return normalise_tier(a) if edition_rank(a) <= edition_rank(b) else normalise_tier(b)


def edition_label(tier: Optional[str]) -> str:
    return EDITION_LABELS.get(normalise_tier(tier), EDITION_LABELS["brain"])


# ── The boot record ──────────────────────────────────────────────────────────


def boot_record_path() -> Path:
    from centurion_constants import get_centurion_home

    path = get_centurion_home() / "license"
    path.mkdir(parents=True, exist_ok=True)
    return path / BOOT_RECORD_FILENAME


def read_boot_record() -> Optional[Dict[str, Any]]:
    """The last boot's answers, or None. Never raises — a missing or corrupt
    record means 'no prior boot', which is the safe reading."""
    try:
        path = boot_record_path()
        if not path.exists():
            return None
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            return None
        return data
    except Exception:
        return None


def _write_boot_record(edition: "Edition") -> None:
    path = boot_record_path()
    payload = {
        "tier": edition.tier,
        "seats": edition.seats,
        "seat_limit": edition.seat_limit,
        "fingerprint": edition.fingerprint,
        "state": edition.state,
        "verified_at": edition.verified_at,
        "booted_at": edition.resolved_at,
    }
    try:
        # Nobody wants a file write on every command. The record only changes
        # when the answers change.
        prior = read_boot_record()
        if prior:
            unchanged = all(prior.get(k) == v for k, v in payload.items() if k != "booted_at")
            if unchanged:
                return
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    except Exception as exc:  # a boot record that cannot be written is not fatal
        logger.debug("Could not write edition boot record: %s", exc)


# ── The resolved edition ─────────────────────────────────────────────────────


@dataclass(frozen=True)
class Edition:
    """What this machine is entitled to run, after the boot resolution."""

    tier: str
    seats: int
    seat_limit: int
    instrument_unlocked: bool
    state: str
    fingerprint: Optional[str] = None
    fingerprint_matches: bool = True
    verified: bool = False
    verified_at: Optional[float] = None
    # True when the entitlement claimed more than the last boot and no verified
    # check-in has intervened: the machine held itself back.
    tampered: bool = False
    note: str = ""
    resolved_at: float = 0.0

    @property
    def label(self) -> str:
        return edition_label(self.tier)

    @property
    def is_practice(self) -> bool:
        return self.tier == "practice"

    def admits(self, named_users: int) -> bool:
        """May this machine carry that many named users?"""
        try:
            count = int(named_users)
        except (TypeError, ValueError):
            return False
        return 0 <= count <= self.seat_limit

    def refusal(self, named_users: int) -> Optional[str]:
        """The sentence to show when a user would exceed the entitlement.

        The eleventh-user refusal for Practice, the second for a vertical Brain.
        """
        if self.admits(named_users):
            return None
        next_user = self.seat_limit + 1
        return (
            f"{self.label} carries {self.seat_limit} named "
            f"{'user' if self.seat_limit == 1 else 'users'}, and that is the whole "
            f"machine. The {_ordinal(next_user)} "
            f"user is a second machine, not a setting."
        )


def _ordinal(n: int) -> str:
    words = {
        2: "second",
        3: "third",
        4: "fourth",
        5: "fifth",
        6: "sixth",
        7: "seventh",
        8: "eighth",
        9: "ninth",
        10: "tenth",
        11: "eleventh",
    }
    return words.get(n, f"{n}th")


def _fingerprint() -> Optional[str]:
    try:
        from centurion.license.fingerprint import compute_fingerprint

        return compute_fingerprint(include_remote=False)
    except Exception:
        return None


def resolve_edition(
    entitlement: Optional[Entitlement] = None,
    *,
    now: Optional[float] = None,
    persist: bool = True,
) -> Edition:
    """Resolve the edition from the entitlement, holding back a local edit.

    Called at boot. Idempotent, offline, and never raises.
    """
    ts = now if now is not None else time.time()
    try:
        ent = entitlement if entitlement is not None else load_entitlement()
    except Exception as exc:  # fail closed, never open
        logger.debug("Edition resolution could not read the entitlement: %s", exc)
        ent = Entitlement()

    tier = ent.edition()
    note = ""
    tampered = False

    fp = _fingerprint()
    bound = bool(ent.machine_fingerprint) and (fp is None or ent.machine_fingerprint == fp)

    prior = read_boot_record()
    if prior and prior.get("tier") and (not fp or prior.get("fingerprint") == fp):
        prior_tier = normalise_tier(prior.get("tier"))
        if prior_tier != tier:
            # Did the licence server authorise the change since the last boot?
            prior_verified = prior.get("verified_at")
            server_confirmed = (
                ent.last_verified_at is not None
                and prior_verified is not None
                and float(ent.last_verified_at) > float(prior_verified)
            )
            if server_confirmed:
                note = f"edition confirmed at check-in ({prior_tier} → {tier})"
            else:
                held = more_restrictive(tier, prior_tier)
                tampered = True
                note = (
                    f"entitlement claims {tier!r}, last boot was {prior_tier!r} with no "
                    f"verified check-in since — holding at {held!r}"
                )
                append_audit(
                    "edition_tamper_detected",
                    file_tier=tier,
                    booted_tier=prior_tier,
                    applied_tier=held,
                )
                tier = held

    edition = Edition(
        tier=tier,
        seats=int(getattr(ent, "seats", 1) or 1) if ent.edition() == "practice" else 1,
        seat_limit=_seat_limit_for(tier, getattr(ent, "seats", 1)),
        instrument_unlocked=tier != "brain",
        state=str(getattr(ent, "state", "unactivated")),
        fingerprint=ent.machine_fingerprint,
        fingerprint_matches=bound,
        verified=ent.last_verified_at is not None,
        verified_at=ent.last_verified_at,
        tampered=tampered,
        note=note,
        resolved_at=ts,
    )

    if persist:
        _write_boot_record(edition)
        if prior is None:
            append_audit("edition_resolved", tier=edition.tier, seats=edition.seat_limit)
    return edition


def _seat_limit_for(tier: str, seats: Any) -> int:
    """The seat limit, clamped by the edition. Mirrors Entitlement.seat_limit()
    but for a tier that may have been held back at boot."""
    from centurion.license.store import PRACTICE_MAX_SEATS, PRACTICE_MIN_SEATS

    if tier != "practice":
        return 1
    try:
        requested = int(seats)
    except (TypeError, ValueError):
        return PRACTICE_MIN_SEATS
    return max(PRACTICE_MIN_SEATS, min(PRACTICE_MAX_SEATS, requested))


# ── Process-wide snapshot ────────────────────────────────────────────────────

_current: Optional[Edition] = None


def current_edition() -> Edition:
    """The boot-resolved edition for this process, resolving on first use."""
    global _current
    if _current is None:
        _current = resolve_edition()
    return _current


def reset_cache() -> None:
    """Drop the cached snapshot (tests, and after a check-in that changed things)."""
    global _current
    _current = None


# ── Re-bind across editions ──────────────────────────────────────────────────


def rebind_refusal(current_tier: Optional[str], requested_tier: Optional[str]) -> Optional[str]:
    """A reissue is a repair, never an upgrade.

    Returns the refusal sentence when a re-bind would land on a different
    edition, else None. Both the OS client and the licence server apply this
    rule; the client applies it first so the request is never even sent.
    """
    if not requested_tier:
        return None
    current = normalise_tier(current_tier)
    requested = normalise_tier(requested_tier)
    if current == requested:
        return None
    return (
        "A re-bind is a repair, never an upgrade: this entitlement is "
        f"{edition_label(current)} and the request is for {edition_label(requested)}. "
        "A different edition is a new machine with a new entitlement — a purchase, "
        "not a reissue. See business/EDITIONS.md §1."
    )


def known_tier(tier: Optional[str]) -> bool:
    return (tier or "").strip().lower() in EDITION_TIERS
