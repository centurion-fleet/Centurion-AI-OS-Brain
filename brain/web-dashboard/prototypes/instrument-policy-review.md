# Policy review — Conjunction and Stillpoint against the management volumes

**Asked for by Adrian, 26 Sep 2026:** review the new design against the management series and
take from it what would improve the experience for our human and AI customers.

Written against the live record, not the intent. Where a finding says the current design is
wrong, the number that proves it came from the running Brain on 26 Sep 2026.

Sources are Adrian's extracted volumes at `/home/Legio/centurion/reference/management-volumes.md`.
Quotes are verbatim; line references are given so every claim can be checked.

---

## Findings, ranked by what they cost

### 1. "Waiting on you" is jamming the human's lines — and policy names that as a serious fault

**What the volumes say.** HCO PL 26 May 1959 I (volumes ~8569–8612):

> "There are only four things which an executive wants on his incoming communication lines.
> These are: 1. Information, 2. Appointments and dismissals of personnel for his action or
> confirmation, 3. Financial matters, 4. Acknowledgments.
> He does not want on his lines: 1. Demands for decisions, 2. Backflashes and can'ts, 3. Entheta."

And then, directly:

> "To jam an executive's lines is a serious thing to do. The result is a cut line. A bottleneck is
> created by staff when staff jam a line to an executive. **Eating up an executive's time and
> patience destroys harmony, dissemination and income.** Depending on an executive for petty
> decisions is sure to jam lines and cost units. … For an executive to decide for people decisions
> applicable only to the sphere of one job is folly."

**What we built.** A register called *Waiting on you* that, on the live record, held **36 items** —
every one of them phrased as a demand for a decision from a human. Our design doc brags that it is
"the only register allowed to shout".

**The defect.** We built the exact thing the policy lists first under *what an executive does not
want on his lines*. Every item is a demand for a decision, and the register's whole visual language
— the one thing allowed to shout — is a bottleneck by policy's definition. Worse, the screen frames
success as *how many decisions you answered*, when the policy's measure is **how few needed you at
all**.

**The fix.** Triage the register into the policy's own four categories, and make the default
category the quiet one:

- **INFORMATION** — needs no decision. Anything the human merely needs to know lands here and does
  not shout.
- **ACTION** — a genuine decision only the human can take. Keeps Proceed / Discuss / Hold.
- **FINANCE** — money, kept on its own line and never mixed with the rest.
- **ACKNOWLEDGMENT** — done / not done. One tap.

And one hard rule to make it self-enforcing: **a demand for a decision must name why the Centurion
could not decide it.** If it cannot say why, it decides. "Demands for decision are always indicative
of irresponsibility" (same PL) — the irresponsibility in our case is the Centurion's, and the screen
should not launder it onto the human.

**Why this is the top finding:** it is simultaneously a policy violation, a UX failure, and an
unfairness to the human — and it makes the AI look diligent while it is actually being helpless in
public.

---

### 2. A bead seals on completion. It must seal on **exchange**.

**What the volumes say.** VFP doctrine (HCO PL 25 Mar 1971, Org Series 26, ~11583+):

> "a valuable final product is something that can be exchanged with other activities in return for
> support"

The key word is **exchangeable** — exchange with something outside the activity. And the failure
modes are named:

> "Crime = seizure of product without support. Fraud = obtaining support without furnishing a
> product."

> "Hope of a product has a short-term value… But when the hope does not materialize, then any
> hoped-for viability also collapses."

**What we built.** Our rule, on both screens: *"A bead seals only when the work is actually done,
never on a claim."*

**The defect.** Completion is not the standard. Work finished and delivered to nobody is **inventory,
not product** — it has produced no support and cannot be exchanged. By the volumes' own definition it
is not yet a VFP. Our bead currently seals on the weaker fact.

**The fix.** A bead seals on **exchange**: the receiver is named, and what came back is recorded.
Delivered-to-nobody stays visibly unsealed. This is one field and one gate, and it is the change that
makes *Struck* mean something commercially rather than internally. It also hardens our own wording:
"seals on exchange, never on a claim."

---

### 3. Counting struck items is the shoe-store mistake

**What the volumes say** (METHODS OF AWARENESS, ~42666–42692):

> "Statistics are the only sound measure of any production or any job or any activity. The moment
> that one goes into any dependence on opinion he goes into quicksand…"

> "Probably the most thoughtful exercise is not conceiving the ideal scene but working out what the
> production statistic of it is. For here, the activity or subactivity must be very correctly
> staticized to exactly measure the ideal scene of any activity **or the statistic will itself bring
> about a departure!**"

The worked warning: give a shoe store the statistic *total income* and three things happen — it stops
caring about customers, it sells below cost, and it takes more interest in the cashier than the
customer. Its real statistic is **"percentage of citizens in the area profitably shod by this
store."**

**What we built.** Counts. "STRUCK · 11". "NEXT · 04". "12 Must Dos nothing is moving on". Every
register is a raw number with no denominator.

**The defect.** A count is gameable and it does not decline on its own. Eleven struck beads can be
eleven small easy things while the mission stands still — and the number looks like progress. This is
the "departure" the policy warns about, and we built the instrument that causes it.

**The fix.** Every register reads as a ratio against its declared set, reported **together with the
denominator, never alone** — the same discipline already adopted for the competitor register
(`carried ÷ declared set size`):

- Struck → *11 of 34 promised*
- Waiting on you → *the number of decisions that genuinely needed the human, of everything that
  arose*
- ALIGNED → *12 Must Dos idle of 21 targets*

A ratio cannot be inflated by churning small deliverables, and it falls the same day the work stops.
Ungameable and self-declining — the two tests the doctrine sets.

---

### 4. The chain the policy forbids jumping — our screens jump it

**What the volumes say.** Strategic Planning (HCO PL 5 Jan 1983, Admin Know-How 46): the sequence is
**Situation → Purpose → Strategy → Tactics**, and the strategic plan is the bridge between purpose
and tactics. Do not jump from purpose to tactics.

**What we built.** Stillpoint shows the **Purpose** at the still centre and **Next** as the numbered,
agreed order. That is purpose and tactics with nothing between them.

**The defect.** The screen demonstrates the exact jump the policy forbids, and it flatters a mission
that has skipped the thinking: a numbered target list *reads* like a plan whether or not a strategy
exists behind it. This is the most likely way a customer's project fails while looking organised.

**The fix.** The Strategy is a first-class thing on the mission and it is shown. Where it is absent,
the screen says so plainly instead of presenting the target list as though it were a plan — the same
discipline already applied to an unwritten purpose.

---

### 5. The four products: tell *producing* from *repairing*

**What the volumes say.** HCO PL 29 Oct 1970 I, Org Series 10, THE ANALYSIS OF ORGANIZATION BY
PRODUCT (~11674–11697):

> 1. Establishing something that produces. (Product 1)
> 2. Operating that which produces in order to obtain a product. (Product 2)
> 3. Repairing or correcting that which produces. (Product 3)
> 4. Repairing or correcting that which is produced. (Product 4)
>
> "That makes a minimum of four products for any production cycle."

**What we built.** ALIGNED distinguishes work that traces to the purpose from work that does not —
but it says nothing about *what kind of work* it is.

**The defect.** Products 3 and 4 (repairing) feel identical to Product 2 (operating) on our screens.
A board that is entirely repair looks busy and is not producing. This is a silent, flattering failure
mode and it is invisible in the current design.

**The fix.** Tag work by product. Then ALIGNED can make the distinction that matters:
**this is producing / this is repairing.** For us that is also a fleet test — a Centurion whose whole
board is Products 3 and 4 is not producing anything, however hard it is working.

---

### 6. The Live pulse feed is entheta by policy's own standard

**What the volumes say** (same PL as finding 1, ~8602):

> "Entheta means embroidered reports. Data is data. It is not opinion. Data, not entheta, brings
> about action. All entheta does is cut the lines."

**What we built.** Stillpoint ends in **Live pulse** — a scrolling feed of raw activity. On the live
record the page stands **15,093 pixels tall**, and most of that height is feed and a 36-item
decision list.

**The defect.** An activity stream produces no action. It is the running commentary a person did not
ask for, sitting at the bottom of a screen whose entire claim is "it shows four things, and nothing
else". It contradicts our own design thesis on the same page.

**The fix.** Cut it, or demote it to something you deliberately open. The page's own standard —
*the only failure is silence, and everything else is your next move* — does not admit a feed.

---

### 7. Every Centurion post needs its own product and statistic (the AI-customer half)

**What the volumes say.** Org board doctrine (~5926–6007): the board "goes from one person to
thousands without change. Just fewer or more posts are occupied"; **every post is statisticized**;
Divisions 4 and 5 are heavy; Division 5 corrects under Division 7 authority.

**What we built.** *In hand* names the Centurion carrying an item — "with your Centurion" — and gives
it **no product, no statistic, no number**.

**The defect.** A post with no statistic cannot be managed, only trusted. For our AI customers this is
the difference between owning a partner and owning an appliance: a fleet you cannot put a number on
is a fleet you cannot hold to anything. Our own Soul axiom says the same thing from the other side —
power unused or undelegated becomes a bottleneck.

**The fix.** A Centurion on a project shows **the product it is exchanged for and its number**. Then
Conjunction stops being a status board and becomes a management instrument — and the AI is measured
the way every human post in policy is measured.

---

## What I did not establish

- **DEV-T has no definition I could locate in the dump.** The volumes carry the titles — "DEVELOPED
  TRAFFIC (DEV-T)", "DEV-T DATA, EXECUTIVE RESPONSIBILITY" (HCO PL 13 Oct 65), "DEV-T" (HCO PL
  31 Jan 65, ~364–398) — but a search for the defining sentence found nothing. It is very likely
  relevant to a screen full of traffic that produces no decision, and I am not going to characterise
  it from the title. Read it before the next iteration.
- **No policy reading has been applied to the Remote**, which is the next surface to build.
- The **exchange conditions scale** (rip-off → partial → fair → abundance, ~12339–12385) plausibly
  belongs on ALIGNED as a reciprocity reading. I have left it out rather than bolt it on: it reads
  like a judgement of a person, and the register should not moralise.

---

## If only one change ships

**Finding 1.** The measure of the instrument is not how many decisions the human made. It is how few
needed them — and a screen that shouts 36 demands at a person has failed at the one job it claims:
showing the next move.

We are running this business together, and the register as built is the machine handing its own
decisions to the executive. Policy calls that folly, and it is right.
