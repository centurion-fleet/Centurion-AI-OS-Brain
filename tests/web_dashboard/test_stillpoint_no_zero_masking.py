"""Guard: the Stillpoint page must never present an unreadable record as an empty one.

Defect class, found live on 29 Sep 2026 (reported by Mike, via the owner):

    Mike had done a night's work with Picard. The Stillpoint page showed zeros
    all over, which reads as "you have nothing" — when the truth was that every
    bridge call had failed and the page simply could not read his record.

The mechanism was a silent fallback:

    try{plans=(await ask({action:"plans_list"})).plans||[];}catch(e){errors.push("plans");}

...so each failed source became an empty list, and every empty list sums to zero.
The page did record the failure, but only in a small `#provenance` footnote, while
the false zeros took the most prominent place on the page. That is precisely the
class the owner named: a control that hides its consequence is broken.

The rule this guard enforces:

    A source that FAILED is not a source that is EMPTY.
    A count we could not read renders "—", never 0.
    A section we could not read says so, and never claims "nothing here".

Prove this guard by making it fail: reinstate any pattern in FORBIDDEN below and
re-run. A guard never seen failing is not yet a guard.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
PAGE = REPO_ROOT / "brain" / "web-dashboard" / "public" / "stillpoint.html"
SERVED = REPO_ROOT / "brain" / "web-dashboard" / "dist" / "stillpoint.html"

# The exact shapes that produced the lie. Each one renders a count that may be
# unknown as if it were zero.
FORBIDDEN = [
    # raw register counters
    "textContent=S.struck",
    "textContent=S.inHand",
    "textContent=S.waiting",
    # raw in-instrument labels
    '"IN HAND · "+S.inHand',
    '"ON PURPOSE · "+A.onPurpose',
    # the bare `||0` that manufactured a zero board count
    "const nb=S.boards||0;",
    # a raw count inside the stamped line
    '"ALIGNED <b>"+A.onPurpose+',
]

# A null struck count must never be used as a loop bound unguarded. Checked
# precisely rather than by substring: the CORRECT form still contains the
# substring `Math.min(20,S.struck)`, it is merely preceded by the null guard.
LOOP_BOUNDS = ["Math.min(20,S.struck)", "Math.min(26,S.struck)"]

# Sections that must not claim emptiness unless their source actually answered.
EMPTY_CLAIMS = [
    "Nothing in hand — every lane is clear.",
    "Nothing queued in the sequence.",
    "Nothing open on this Brain at all.",
    "Nothing struck yet.",
    "Nothing is waiting on you.",
]


@pytest.fixture(scope="module")
def page() -> str:
    assert PAGE.exists(), f"Stillpoint page not found at {PAGE}"
    return PAGE.read_text(encoding="utf-8")


def test_page_exists(page: str) -> None:
    assert "ONE ring" in page, "this does not look like the Stillpoint page"


def test_no_zero_masking_patterns(page: str) -> None:
    """The defect shapes themselves must be absent."""
    present = [p for p in FORBIDDEN if p in page]
    assert not present, (
        "Stillpoint renders an unreadable count as a number again — the page will "
        f"lie to an owner whose Brain it cannot reach. Reinstate num()/cnt(): {present}"
    )
    # A null struck count must be guarded before it is used as a loop bound.
    for pat in LOOP_BOUNDS:
        for m in re.finditer(re.escape(pat), page):
            before = page[max(0, m.start() - 24): m.start()]
            assert "struck==null?0:" in before, (
                f"'{pat}' is used as a loop bound without a null guard, so an "
                f"unreadable record silently renders as zero beads/seals: ...{before}{pat}"
            )


def test_unknown_renders_as_dash(page: str) -> None:
    """num() must exist and must actually be used on the counters."""
    assert re.search(r"function num\(v\)\{", page), "the num() helper is missing"
    for elem in ("r-struck", "c-struck", "r-hand", "c-hand", "r-wait", "c-wait"):
        line = next((l for l in page.splitlines() if f'"{elem}"' in l and "textContent" in l), None)
        assert line is not None, f"no render site found for #{elem}"
        assert "num(" in line, (
            f"#{elem} renders a count without num() — an unreadable record would "
            f"show as a number instead of an em dash: {line.strip()}"
        )


def test_counts_are_qualified_by_their_sources(page: str) -> None:
    """Every derived count must be wrapped in cnt(...) with its source names."""
    assert "const cnt=(v,...srcs)=>srcs.some(bad)?null:v;" in page, (
        "the cnt() qualifier is missing — a count can no longer be marked unknown"
    )
    for field in ("struck", "inHand", "waiting", "more", "boards"):
        assert re.search(rf"\b{field}:cnt\(", page) or re.search(rf"\b{field}: cnt\(", page), (
            f"count '{field}' is not qualified by its sources"
        )
    for field in ("onPurpose", "unlinked", "pendingAll", "mustDo"):
        assert f"{field}:cnt(" in page, f"aligned count '{field}' is not qualified"


def test_empty_claims_are_conditional(page: str) -> None:
    """No section may declare itself empty without checking whether it could read."""
    lines = page.splitlines()
    for claim in EMPTY_CLAIMS:
        idx = next((i for i, l in enumerate(lines) if claim in l), None)
        assert idx is not None, f"expected empty-claim not found (was it reworded?): {claim}"
        # The guard may sit on the same statement, which the formatter can wrap
        # across lines — so examine the statement, not the single line.
        window = "\n".join(lines[max(0, idx - 3): idx + 2])
        assert "unread" in window, (
            f"this claim is unconditional, so a failed read looks like an empty "
            f"record:\n{window}"
        )


def test_failure_is_stated_loudly(page: str) -> None:
    """The failure must reach the caption, not just the small provenance footnote."""
    assert "setState(\"This page could not read part of this Brain's record" in page, (
        "the failure is no longer reported on the page's loudest status line — a "
        "footnote loses to a wall of numbers"
    )


def test_served_copy_matches_the_source(page: str) -> None:
    """dist/ is what the Brain serves. A stale dist ships the old, lying page."""
    if not SERVED.exists():
        pytest.skip("no built dashboard present — nothing is shipped from this checkout")
    assert SERVED.read_text(encoding="utf-8") == page, (
        "dist/stillpoint.html does not match public/stillpoint.html — the build has "
        "not been run, so the shipped page still carries the old behaviour"
    )
