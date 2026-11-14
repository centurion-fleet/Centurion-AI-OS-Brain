"""Statutory deadlines, computed from the practice's own client records.

The design rule this implements: **deadlines are computed, never typed.** A date
somebody entered by hand is a date that goes stale silently; a date derived from
a year end is right next year as well, and wrong only when the client record is
wrong — which is a different, findable fault.

Every rule below is a published UK obligation with the arithmetic stated beside
it, because the whole value of the pane is that a partner can check the machine's
reasoning rather than trust it:

| obligation | rule | source shape |
|---|---|---|
| Self assessment filing | 31 January following the tax year end (5 April) | fixed date |
| Second payment on account | 31 July following the tax year end | fixed date |
| Corporation tax | 9 months + 1 day after the accounting period end | derived |
| VAT return and payment | 1 month + 7 days after the quarter end | derived |
| PAYE / NIC | 19th of the following month (22nd electronic) | fixed day |
| P11D | 6 July after the tax year end | fixed date |
| Confirmation statement | 14 days after the review period ends | derived |

What this deliberately does **not** do: model a client's individual extensions,
a VAT stagger group's non-standard quarters, or a change of year end mid-period.
Those exist, and when one applies the record says so and the machine reports the
obligation as *unsettled* rather than picking a date — which is the same rule the
review queue runs on.
"""

from __future__ import annotations

import calendar
import datetime as dt
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, List, Optional

import yaml

DEFAULT_HORIZON_DAYS = 45


@dataclass
class Obligation:
    client: str
    kind: str
    due: dt.date
    rule: str
    unsettled: Optional[str] = None

    @property
    def days_remaining(self) -> int:
        return (self.due - dt.date.today()).days


@dataclass
class ClientRecord:
    slug: str
    name: str
    entity: str = ""
    year_end: Optional[dt.date] = None
    vat_quarter_ends: List[dt.date] = field(default_factory=list)
    payroll: bool = False
    confirmation_statement_review: Optional[dt.date] = None
    notes: str = ""
    unsettled: List[str] = field(default_factory=list)


# ── date arithmetic ─────────────────────────────────────────────────────────


def _safe_date(value) -> Optional[dt.date]:
    if isinstance(value, dt.date) and not isinstance(value, dt.datetime):
        return value
    if isinstance(value, dt.datetime):
        return value.date()
    if isinstance(value, str):
        for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%d %B %Y", "%d %b %Y"):
            try:
                return dt.datetime.strptime(value.strip(), fmt).date()
            except ValueError:
                continue
    return None


def add_months(day: dt.date, months: int) -> dt.date:
    month = day.month - 1 + months
    year = day.year + month // 12
    month = month % 12 + 1
    last = calendar.monthrange(year, month)[1]
    return dt.date(year, month, min(day.day, last))


def next_occurrence(day: dt.date, today: dt.date) -> dt.date:
    """The same month-day this year if it has not passed, otherwise next year."""
    for year in (today.year, today.year + 1):
        try:
            candidate = dt.date(year, day.month, day.day)
        except ValueError:
            # 29 February in a non-leap year resolves to the 28th.
            candidate = dt.date(year, day.month, 28)
        if candidate >= today:
            return candidate
    return dt.date(today.year + 2, day.month, min(day.day, 28))


# ── the rules ───────────────────────────────────────────────────────────────


def obligations_for(
    client: ClientRecord, today: Optional[dt.date] = None, horizon_days: int = DEFAULT_HORIZON_DAYS
) -> List[Obligation]:
    today = today or dt.date.today()
    horizon = today + dt.timedelta(days=horizon_days)
    out: List[Obligation] = []

    def add(kind: str, due: dt.date, rule: str) -> None:
        if today <= due <= horizon:
            out.append(Obligation(client=client.name, kind=kind, due=due, rule=rule))

    # Corporation tax is a *company* obligation. An LLP files accounts but pays
    # income tax through its members; a partnership and a sole trader do neither.
    # Getting this wrong puts a corporation tax date on a farm, which is the kind
    # of error a partner catches in two seconds and then stops trusting the pane.
    entity = (client.entity or "").strip().lower()
    is_company = entity in ("limited company", "ltd", "limited", "company", "plc")
    is_llp = entity in ("llp", "limited liability partnership")

    if client.year_end and (is_company or is_llp):
        for offset in (0, 1):
            period_end = dt.date(client.year_end.year + offset, client.year_end.month,
                                 client.year_end.day)
            due = add_months(period_end, 9) + dt.timedelta(days=1)
            if is_company:
                add("Corporation tax", due, "9 months + 1 day after the period end")
            add("Statutory accounts", due, "9 months after the period end")

    # VAT: 1 month + 7 days after each quarter end.
    for quarter_end in client.vat_quarter_ends:
        for offset in (0, 1):
            try:
                end = dt.date(quarter_end.year + offset, quarter_end.month, quarter_end.day)
            except ValueError:
                end = dt.date(quarter_end.year + offset, quarter_end.month, 28)
            # HMRC states "one month and seven days". Taken literally that is the
            # 6th for a quarter ending 30 September; the published deadline is the
            # 7th. The rule that reproduces HMRC's own calendar is the 7th of the
            # second month after the quarter end, so that is what is computed.
            base = add_months(end, 2)
            add(
                "VAT return and payment",
                dt.date(base.year, base.month, 7),
                "7th of the second month after the quarter end",
            )

    # PAYE: 19th of the month following (22nd if paid electronically).
    if client.payroll:
        month = today.replace(day=1)
        for step in (0, 1):
            base = add_months(month, step)
            add("PAYE and NIC", dt.date(base.year, base.month, 19),
                "19th of the following month (22nd electronic)")

    # Fixed dates in the tax year. Which of them apply depends on what the client
    # *is*: a company does not file a self assessment, and a sole trader does not
    # file corporation tax. An obligation in the wrong column is worse than a
    # missing one, because the pane is read as a worklist.
    is_individual_filer = entity in (
        "sole trader", "partnership", "llp", "limited liability partnership", "individual",
    )

    if is_individual_filer:
        for kind, month, day, rule in (
            ("Self assessment filing", 1, 31, "31 January following the tax year end"),
            ("Second payment on account", 7, 31, "31 July following the tax year end"),
        ):
            add(kind, next_occurrence(dt.date(today.year, month, day), today), rule)

    if entity == "partnership":
        add(
            "Partnership return",
            next_occurrence(dt.date(today.year, 1, 31), today),
            "31 January following the tax year end",
        )

    if client.payroll:
        add(
            "P11D",
            next_occurrence(dt.date(today.year, 7, 6), today),
            "6 July after the tax year end",
        )

    # Confirmation statement: 14 days after the review period ends.
    if client.confirmation_statement_review:
        for offset in (0, 1):
            try:
                review = dt.date(
                    client.confirmation_statement_review.year + offset,
                    client.confirmation_statement_review.month,
                    client.confirmation_statement_review.day,
                )
            except ValueError:
                review = dt.date(client.confirmation_statement_review.year + offset,
                                 client.confirmation_statement_review.month, 28)
            add("Confirmation statement", review + dt.timedelta(days=14),
                "14 days after the review period ends")

    # Anything the record itself flags as uncertain is reported, not guessed.
    for note in client.unsettled:
        out.append(
            Obligation(
                client=client.name,
                kind="Unsettled",
                due=today,
                rule="stated on the client record",
                unsettled=note,
            )
        )

    out.sort(key=lambda o: (o.due, o.client, o.kind))
    return out


# ── reading the practice library ────────────────────────────────────────────


def parse_client_file(path: Path) -> ClientRecord:
    text = path.read_text(encoding="utf-8")
    meta = {}
    if text.startswith("---"):
        _, _, rest = text.partition("---")
        block, _, body = rest.partition("\n---")
        try:
            meta = yaml.safe_load(block) or {}
        except yaml.YAMLError:
            meta = {}
    else:
        body = text

    if not isinstance(meta, dict):
        meta = {}

    vat = meta.get("vat_quarter_ends") or []
    if isinstance(vat, str):
        vat = [vat]

    return ClientRecord(
        slug=meta.get("slug") or path.stem,
        name=meta.get("name") or path.stem.replace("-", " ").title(),
        entity=meta.get("entity") or "",
        year_end=_safe_date(meta.get("year_end")),
        vat_quarter_ends=[d for d in (_safe_date(v) for v in vat) if d],
        payroll=bool(meta.get("payroll")),
        confirmation_statement_review=_safe_date(meta.get("confirmation_statement_review")),
        notes=(body or "").strip(),
        unsettled=[str(u) for u in (meta.get("unsettled") or [])],
    )


def load_library(library: Path) -> List[ClientRecord]:
    clients_dir = Path(library) / "clients"
    if not clients_dir.is_dir():
        return []
    return [parse_client_file(p) for p in sorted(clients_dir.glob("*.md"))]


def upcoming(
    library: Path, today: Optional[dt.date] = None, horizon_days: int = DEFAULT_HORIZON_DAYS
) -> List[Obligation]:
    records = load_library(library)
    out: List[Obligation] = []
    for record in records:
        out.extend(obligations_for(record, today=today, horizon_days=horizon_days))
    out.sort(key=lambda o: (o.due, o.client))
    return out


def summarise(obligations: Iterable[Obligation]) -> dict:
    """The count a pane can show, plus the parts a partner needs to see behind it.

    Every date leaves as an ISO string: a `date` object on its way to JSON raises
    at serialise time, and the failure surfaces as a 500 on the page rather than
    as anything a human can read.
    """
    items = list(obligations)
    settled = [o for o in items if not o.unsettled]
    return {
        "count": len(settled),
        "unsettled": [
            {
                "client": o.client,
                "kind": o.kind,
                "note": o.unsettled,
                "rule": o.rule,
            }
            for o in items
            if o.unsettled
        ],
        "next": (
            {
                "client": settled[0].client,
                "kind": settled[0].kind,
                "due": settled[0].due.isoformat(),
                "days": settled[0].days_remaining,
                "rule": settled[0].rule,
            }
            if settled
            else None
        ),
    }
