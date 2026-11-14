"""What the practice's own work has actually read.

The Documents pane does not list a library index — there isn't one on this
machine yet, and inventing a folder scan would answer a different question.
It lists the files that the practice's drafts have **cited**: provenance, made
aggregate. That is the honest derivation available today, and it has the useful
property that it only ever shows files the machine genuinely used.

Two rules carried from the desk's invariant:

* an unreadable register reports a failure, never an empty list;
* a register that exists but is empty reports ``unmeasured`` with a reason,
  because a confident "0 files" over work that has not started reads as
  "nothing here" when it means "nobody has filed anything yet".
"""

from __future__ import annotations

import re
from typing import Any, Dict, Iterable, List, Optional

# "…/client-file.md:112", "…/file.md, line 112", "…/file.md (line 112)"
_LINE_SUFFIX = re.compile(r"(?:[:,]\s*(?:line\s*)?|\(line\s*)(\d+)\)?\s*$", re.IGNORECASE)


def normalise_citation(cite: str) -> Dict[str, Any]:
    """Split a citation into the file and the line it points at.

    Citations reach the register in several shapes because they are written by
    an agent, not a form. Keep the file path byte-for-byte and lift the line
    number out — the path is what the pane groups on.
    """
    raw = str(cite or "").strip()
    if not raw:
        return {"path": "", "line": None}
    match = _LINE_SUFFIX.search(raw)
    if not match:
        return {"path": raw, "line": None}
    path = raw[: match.start()].strip()
    try:
        line = int(match.group(1))
    except (TypeError, ValueError):
        line = None
    return {"path": path or raw, "line": line}


def _iter_drafts(drafts: Optional[List[Dict[str, Any]]]) -> Iterable[Dict[str, Any]]:
    for draft in drafts or []:
        if isinstance(draft, dict):
            yield draft


def library_use(drafts: Optional[List[Dict[str, Any]]]) -> Dict[str, Any]:
    """Aggregate the citations carried by a set of drafts.

    ``drafts`` is the whole register the asker may see (any status) — passing a
    status-filtered slice would understate what the machine has read.
    """
    seen: Dict[str, Dict[str, Any]] = {}
    drafts_total = 0
    citation_total = 0
    with_cites = 0
    unsettled_total = 0

    for draft in _iter_drafts(drafts):
        drafts_total += 1
        cites = draft.get("cites") or []
        # A malformed row can carry a bare string here. Iterating it would walk
        # its characters and invent a dozen one-letter "files", so coerce first.
        if isinstance(cites, str):
            cites = [cites]
        elif not isinstance(cites, (list, tuple)):
            cites = []
        unsettled = draft.get("unsettled") or []
        if isinstance(unsettled, str):
            unsettled = [unsettled]
        elif not isinstance(unsettled, (list, tuple)):
            unsettled = []
        if unsettled:
            unsettled_total += 1
        if cites:
            with_cites += 1
        for cite in cites:
            parsed = normalise_citation(cite)
            path = parsed["path"]
            if not path:
                continue
            citation_total += 1
            row = seen.get(path)
            if row is None:
                seen[path] = {
                    "path": path,
                    "citations": 1,
                    "lines": [parsed["line"]] if parsed["line"] else [],
                    "clients": sorted(
                        {draft["client_slug"]} if draft.get("client_slug") else set()
                    ),
                    "last_cited": draft.get("created_at"),
                    "draft_ids": [draft.get("id")],
                }
                continue
            row["citations"] += 1
            if parsed["line"] and parsed["line"] not in row["lines"]:
                row["lines"].append(parsed["line"])
            if draft.get("client_slug"):
                row["clients"] = sorted(set(row["clients"]) | {draft["client_slug"]})
            if draft.get("id") and draft["id"] not in row["draft_ids"]:
                row["draft_ids"].append(draft["id"])
            created = draft.get("created_at")
            if created and (row["last_cited"] is None or created > row["last_cited"]):
                row["last_cited"] = created

    documents = sorted(seen.values(), key=lambda r: (-r["citations"], r["path"]))
    for row in documents:
        row["lines"] = sorted(row["lines"])
        row["lines_shown"] = row["lines"][:6]

    unmeasured: Optional[str] = None
    if drafts_total == 0:
        unmeasured = (
            "not measured — no draft has been filed on this machine yet, so there "
            "is no record of what the machine has read"
        )
    elif document_count(documents) == 0:
        unmeasured = (
            "no draft on this machine has cited a file yet — the register exists, "
            "the citations do not"
        )

    return {
        "documents": documents,
        "files": document_count(documents),
        "drafts": drafts_total,
        "drafts_with_citations": with_cites,
        "citations": citation_total,
        "drafts_with_unsettled": unsettled_total,
        "unmeasured": unmeasured,
    }


def document_count(documents: List[Dict[str, Any]]) -> int:
    return len(documents)
