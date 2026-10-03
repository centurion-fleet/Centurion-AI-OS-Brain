# Stillpoint — design note

**Brief (Adrian, 26 Sep 2026):** the screen formerly called Focus is the same instrument as
Conjunction, for the work that involves one Centurion instead of two. It keeps its original
intent — extracting the owner's life goals and purposes so the owner is helped on what they
*should* be working on. Take a fresh look at it with what Conjunction taught.

Written after Conjunction shipped. Conjunction is the reference implementation; where this
document and `prototypes/conjunction/DESIGN.md` disagree, the disagreement is deliberate and
is named in "What Stillpoint does not have".

---

## Naming

The tab was called **Focus**, which described an activity, not the thing itself. The pair now
reads as one family:

- **Conjunction** — when two bodies meet. Two Centurions, one project.
- **Stillpoint** — the point that does not move. One Centurion, one life, held at the centre.

Conjunction is the moment of meeting; Stillpoint is the centre it is measured from. Both are
positions in the same instrument, which is the whole point: a person should feel they are
looking at one device with two eyepieces, not two products.

Stillpoint also names the product's actual claim — that the still centre is where the human
belongs — and it is older language than the software: *the still point of the turning world*.
A screen that tells you whether you are working on the right thing should be named for the
place you judge it from.

**Internal identifiers deliberately keep the old word.** The React screen is still `Deck.tsx`,
the route is still `/`, the back bar is still `FocusBackBar`, and the bridge actions still say
`focus`. Renaming plumbing to match a label buys nothing a reader can see and risks a broken
build in the one area where the tab must never fail to open. The word a customer reads is
Stillpoint; the word the code uses is a private matter.

---

## 1. What Stillpoint is

One intention, one pair: the owner and their Centurion. Everything Conjunction does to keep a
human in the decision seat, Stillpoint does for a life rather than a project.

The difference in one line:

> **Conjunction answers "what needs me across my projects". Stillpoint answers "am I working
> on the right thing at all".**

That second question is not a project question, and it cannot be answered by a project view.
It is the reason this screen exists separately.

## 2. What Stillpoint keeps from Conjunction

The instrument, unchanged in kind:

- **The still centre.** The human sits at the middle; the Centurion works the ring. The owner
  is not shown raw work — only the next move.
- **The four registers**, named identically, so the two screens are one language:
  - **STRUCK** — delivered and verified. A bead seals on the work, never on the claim.
  - **IN HAND** — moving now, with the Centurion named against it.
  - **NEXT** — the agreed order, numbered.
  - **WAITING ON YOU** — the only register allowed to shout. Same three verbs.
- **The verbs.** *Proceed* starts the work and hands it over; *Discuss* opens a thread on the
  item and the item stays where it is; *Hold* keeps it visible, marked held.
- **Silence is the only failure.** Something waiting that the owner cannot see is the single
  error this screen exists to prevent.
- The paper-and-bronze house style, and the shared implementation.

## 3. What Stillpoint has that Conjunction does not

This is the screen's whole reason for being, and it is one additional layer.

### 3.1 The centre is written, not assumed

Conjunction's still centre is *you, here, in this project*. Stillpoint's centre is **your
purpose** — a stated primary mission with a reason, arrived at on purpose through Discovery
rather than inferred from whatever is busiest. A life view whose centre is implicit drifts
toward whatever shouted last.

### 3.2 The fifth register: ALIGNED

The register no project view can have, and the answer to "am I working on the right thing":

- What is moving that **traces to the stated purpose**
- What is moving that **does not** — work that is real, and untethered
- What the purpose asks for that **nothing is moving on at all**

The last of those is the one that earns the register. A project view can show you that a task
stalled; only a life view can show you that your stated purpose has had nothing moving on it
for a month while you were busy.

ALIGNED is deliberately quiet when the answer is "everything traces". It is not a nag — it is
the purpose check, and it should be able to say nothing.

**ALIGNED must never count what the record cannot support.** On the live record, plans and
decisions carry no mission link at all. Reading that absence as "no purpose attached" would be
literally true and badly misleading, because the work serves the purpose perfectly well — the
record simply does not say so. Unlinked is not untethered. When nothing links, the register
says so and declines to judge; when some things link, the absence becomes informative and it
counts them properly.

### 3.3 Dreams feed the centre

Conjunction has no equivalent. In Stillpoint, dreams are the raw material of purpose: they sit
below the fold, and promoting one is how the centre changes. This is the mechanic that makes
the centre *written* rather than *inherited*.

## 4. What Stillpoint does not have

Named explicitly, because these are Conjunction features whose absence is the design:

- **No project switch.** There is one life. A switcher here would be a category error.
- **No membership or permissions.** Nothing is shared because nothing is shared *with* — there
  is no second party to scope against.
- **No second accent colour.** The two-ring bronze/steel language collapses to one ring: the
  Centurion's. The owner is the centre, and the centre has no colour.
  *(Amended 3 Oct 2026: one ring still — but that ring now **turns**. See §7.)*
- **No peers, no swarms, no pairing.** Brain-to-brain belongs to Conjunction's world; pairing
  and boards remain reachable from the masthead, not from here.

## 5. Where settings live

**Settings do not belong on the phone.** The Remote captures thought and orders, then gets out
of the way. Every setting, toggle and account control lives in the Brain app, in **You**, which
is where a person already expects to find them and where there is room to explain a consequence
before it is accepted.

The Remote's test is not "can we fit it", it is: *does this capture a thought, or does it
change a setting?* If the latter, it is in the wrong app.

## 6. The rule that keeps it honest

One dangerous mistake exists here, and it is not the wrong-project mistake Conjunction has to
defend against. It is **answering a purpose question with a task answer** — letting the register
read as "you are busy, therefore you are aligned".

So ALIGNED may only count work that traces to the stated purpose by name. Busy is not evidence.
If the purpose is empty or never written, ALIGNED says so plainly instead of inferring one from
activity.

## 7. Added 3 Oct 2026 — shared motion, and the thought stream

**The owner's direction, recorded as a decision. It supersedes two earlier rules on this page.**

Until today Stillpoint was the page that *did not move* and *did not have a feed*. Both were
deliberate: §4 kept a single, un-turning ring, and the policy review (§6, *"The Live pulse feed is
entheta by policy's own standard"*) called an activity stream a defect. **Both are overruled.**
Recorded here so the change reads as a decision rather than as drift.

### 7.1 The ring turns

The ring now carries the same slow counter-orbit as Conjunction: the ring and the work it carries
turn one way (`spin-cw`, 190s), the sealed work accumulating along the lower arc turns the other
(`spin-ccw`, 230s). Everything that is a **fixed frame** — the register marks, the still centre, the
purpose, the labels — still does not turn.

**Why this is not simply Conjunction's mistake repeated.** Conjunction's own note said *"No ambient
animation: a page that is always moving cannot be photographed."* That rule is now retired on both
pages, because the two readings conflicted and **liveness won.** What the rule protected — a frame
that survives being photographed and forwarded — is met by the **rate**, not by stillness. Motion at
all is the proof this is a live reading and not a still. `prefers-reduced-motion` stops both.

### 7.2 The thought stream

A **Live · what it is doing** plate now sits above the Register, reading the same
`life_thoughts_list` source Conjunction reads — so the two pages can never disagree about what has
been done. Rows are bronze: this page has one Centurion, so the steel voice does not appear.

**What makes it different from the feed the review cut:**

1. **The work in its own words, not a log of plumbing** — the standard Conjunction is held to.
2. **A settled list, not a ticker.** Rows arrive, light once, then settle. It carries data; it is not
   ambient motion.

⚠️ **The review's finding was not wrong — it was overruled.** An unsolicited feed at the bottom of a
page whose whole claim is *"four things, and nothing else"* **is** a defect. What changed is the
owner's decision that the visibility a customer asked for — and one language across both tabs — is
worth more than Stillpoint's purity. If the plate later reads as noise, §6's original fix remains
the fallback and is the version that satisfies both: **demote it behind a control the owner
deliberately opens.**

---

## Open question for Adrian

**The verb sets still differ.** Conjunction offers Proceed / Discuss / Hold. The decision items
on this screen (via `AttentionBanner`) offer Review / Proceed / Adjust / Hold — there is no
Discuss. Section 2 claims "same three verbs", so that claim is false until the sets match.

Options:

1. **Add Discuss, keep Adjust** (recommended) — Discuss opens the same thread as Conjunction;
   Adjust stays as the fast "changes requested" path, which is what most revisions actually are.
2. **Three verbs exactly** — drop Adjust, so the two screens are identical.
3. **Leave them different** — defensible only if the two screens are meant to feel different,
   which contradicts the whole premise.
