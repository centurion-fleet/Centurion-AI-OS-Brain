"""The sample practice: eight fictional clients, a house style, and a precedent.

Why this exists. A webinar where the machine is asked about an empty library
demonstrates nothing. A webinar where the audience watches it answer a real
question about a client book — naming the file it read — is the product. So the
corpus is a sales asset, not test data, and it is built once with care and
reused in every demonstration.

Everything here is invented. The names are chosen to be obviously fictional, the
figures are round, and no entry describes a real person, a real firm or a real
client. `demo-journal.md` says so on the page, because a demonstration that looks
like extracted client data is a liability the moment it is screen-shared.

Two clients deliberately carry an `unsettled` entry. They exist so the
demonstration can show the behaviour that sells the thing: the machine saying
what it could not settle, in the same size type as what it could.
"""

from __future__ import annotations

from pathlib import Path

HOUSE_STYLE = """---
title: House style
scope: practice
---

# House style

Applies to every letter, email and set of accounts that leaves this practice.

**Voice.** Plain English. No "please find attached", no "kindly", no "we trust
this meets with your approval". Say what the client needs to do and by when.

**Figures.** Sterling, thousands separated, no pence in narrative prose and pence
in a schedule. Negative figures in brackets, never a minus sign.

**Dates.** 31 March 2027 in prose. 31/03/2027 in a schedule. Never a mixture in
the same document.

**Names.** The client is "the Company", "the Partnership" or the client's name —
never "you" in a letter of engagement and always "you" in a covering email.

**Nothing is sent unsigned.** A draft leaves this practice with the preparer's
initials and the partner's signature. There is no exception for small clients.
"""

ENGAGEMENT_PRECEDENT = """---
title: Engagement letter precedent — limited company, standard
scope: practice
---

# Engagement letter precedent

Clause order that has survived three inspections:

1. What we will do — listed, finite, and no verbs that imply advice.
2. What we will not do — the list is longer than clients expect, and that is the
   point.
3. What you must give us, and by when.
4. Our fee, the basis, and when it is payable.
5. What happens if information arrives late. State that the deadline does not
   move because information is late.
6. Limitation of liability, in figures, agreed in advance.
7. Termination.
8. Data and records: what we keep, for how long, and that the client's records
   are the client's.

Do not renumber without checking every cross-reference in the schedule.
"""

CLIENTS = {
    "hargreaves-and-sons.md": """---
name: Hargreaves & Sons
slug: hargreaves-and-sons
entity: Partnership
year_end: 2026-04-05
vat_quarter_ends: [2026-03-31, 2026-06-30, 2026-09-30, 2026-12-31]
payroll: true
confirmation_statement_review: 2026-11-14
---

Two partners, agricultural machinery repair. Year end 5 April, chosen years ago
and never changed.

**Payroll:** four employees, one on a directors' style arrangement that has been
queried twice and never resolved in writing.

**Standing instruction:** the senior partner signs everything. The junior partner
may authorise payments under £2,000 and nothing else.

**Open:** the partnership's VAT quarters were moved to a stagger group in 2024 and
the practice has never had written confirmation of the new quarter ends.
""",
    "millfield-joinery.md": """---
name: Millfield Joinery Ltd
slug: millfield-joinery
entity: Limited company
year_end: 2026-12-31
vat_quarter_ends: [2026-09-30]
payroll: true
---

Joinery manufacturer, eleven staff, one site.

**Year end:** 31 December. Accounts and corporation tax fall due at the same
point, which is why this client is always the pinch in September.

**VAT:** quarterly, standard, filed by the bookkeeper. The practice checks it and
does not prepare it.

**Standing instruction:** the managing director answers in one line and expects
the same. Do not send him more than five lines of email.
""",
    "carter-and-vane.md": """---
name: Carter & Vane LLP
slug: carter-and-vane
entity: LLP
year_end: 2027-03-31
vat_quarter_ends: [2026-12-31, 2027-03-31]
payroll: false
unsettled:
  - "Year end changed from 30 September to 31 March in 2025; the transitional
    period return was filed but the practice has not been sent the acknowledgement."
---

Two-member LLP, architectural services.

**Year end:** 31 March, following the 2025 change. The first accounting period
after the change was short and the comparative figures in the 2026 accounts are
still marked provisional.

**Standing instruction:** both members sign. Neither signs alone, including on
routine correspondence.
""",
    "brook-house-dental.md": """---
name: Brook House Dental
slug: brook-house-dental
entity: Limited company
year_end: 2027-01-31
vat_quarter_ends: [2026-10-31, 2027-01-31]
payroll: true
confirmation_statement_review: 2027-01-10
---

Single-site dental practice, six clinical staff, two of them associates on a
self-employed basis that the practice has never documented.

**Year end:** 31 January.

**Standing instruction:** the principal is the only signatory. The practice
manager may correspond but may not commit to a fee or a timetable.
""",
    "sable-street-cafe.md": """---
name: Sable Street Café
slug: sable-street-cafe
entity: Sole trader
year_end: 2026-04-05
vat_quarter_ends: [2026-12-31, 2027-03-31]
payroll: false
unsettled:
  - "Cash takings are recorded weekly in a book the practice has never seen; the
    VAT returns are prepared from the till summary only."
---

Café, one site, nine years trading.

**Books:** the till summary is the record. The weekly book exists and is not
supplied. Every VAT return for three years has been prepared on incomplete
information and the practice has flagged it in writing once.

**Standing instruction:** the owner signs. He does not read what he signs, which
the file notes, in those words, from 2023.
""",
    "northgate-logistics.md": """---
name: Northgate Logistics Ltd
slug: northgate-logistics
entity: Limited company
year_end: 2027-06-30
vat_quarter_ends: [2026-12-31, 2027-03-31]
payroll: true
---

Freight forwarding, one depot, twenty-eight staff.

**Year end:** 30 June. The busiest quarter in the practice, which is why the
planning meeting happens in April and not in June.

**Payroll:** twenty-eight, four on variable hours. CIS applies to a small part of
the work and the treatment has been consistent since 2021.

**Standing instruction:** finance director signs. The managing director is copied
and does not sign.
""",
    "fenwick-farm.md": """---
name: Fenwick Farm Partnership
slug: fenwick-farm
entity: Partnership
year_end: 2027-04-05
vat_quarter_ends: [2026-11-30]
payroll: true
---

Mixed arable and livestock, three partners, one of whom is retiring in stages and
whose drawings have not been documented.

**Year end:** 5 April, aligned to the tax year.

**VAT:** quarterly, but the quarter ends are February/May/August/November, which
is unusual for this practice and is the single most common source of error on the
file.

**Standing instruction:** the two active partners sign. The retiring partner signs
nothing and is still copied on everything, which nobody has been willing to stop.
""",
    "quill-street-studio.md": """---
name: Quill Street Studio Ltd
slug: quill-street-studio
entity: Limited company
year_end: 2026-09-30
vat_quarter_ends: [2026-09-30, 2026-12-31]
payroll: false
---

Two-person design studio, incorporated three years ago.

**Year end:** 30 September. The first year was short, ending 30 September 2024,
and the comparatives are still marked as such.

**Open:** the company has never filed a confirmation statement on time. Twice it
has been reinstated after a strike-off notice and no process change followed.
""",
}

JOURNAL = """---
title: About this sample practice
scope: practice
---

# About this sample practice

Every client in this library is invented. The names, the figures and the
correspondence were written for demonstration and describe no real person, firm
or client.

It exists so that a demonstration can ask a real question — *which client has a
deadline in the next two weeks, and why?* — and get an answer that names the file
it read.

Two entries deliberately carry an `unsettled` note. That is the behaviour worth
demonstrating: the machine reporting what it could not settle, in the same size
type as what it could, rather than filling the gap with a plausible date.
"""


def build_demo_library(root: Path) -> Path:
    """Write the sample practice under `root/library`. Idempotent."""
    library = Path(root) / "library"
    clients = library / "clients"
    clients.mkdir(parents=True, exist_ok=True)

    (library / "house-style.md").write_text(HOUSE_STYLE, encoding="utf-8")
    (library / "precedent-engagement-letter.md").write_text(
        ENGAGEMENT_PRECEDENT, encoding="utf-8"
    )
    (library / "demo-journal.md").write_text(JOURNAL, encoding="utf-8")

    for filename, body in CLIENTS.items():
        (clients / filename).write_text(body, encoding="utf-8")

    return library
