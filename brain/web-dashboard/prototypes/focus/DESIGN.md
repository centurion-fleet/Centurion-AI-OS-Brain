# Focus — design note

**Brief (Adrian, 26 Sep 2026):** Focus is the same instrument as Conjunction, for the work
that involves one Centurion instead of two. It keeps its original intent — extracting the
owner's life goals and purposes so the owner is helped on what they *should* be working on.
Take a fresh look at it with what Conjunction taught.

Written after Conjunction shipped. Conjunction is the reference implementation; where this
document and `prototypes/conjunction/DESIGN.md` disagree, the disagreement is deliberate and
is named in "What Focus does not have".

---

## 1. What Focus is

One intention, one pair: the owner and their Centurion. Everything Conjunction does to keep a
human in the decision seat, Focus does for a life rather than a project.

The difference in one line:

> **Conjunction answers "what needs me across my projects". Focus answers "am I working on
> the right thing at all".**

That second question is not a project question, and it cannot be answered by a project view.
It is the reason Focus exists separately.

## 2. What Focus keeps from Conjunction

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

## 3. What Focus has that Conjunction does not

This is Focus's whole reason for being, and it is one additional layer.

### 3.1 The centre is written, not assumed

Conjunction's still centre is *you, here, in this project*. Focus's centre is **your purpose**
— a stated primary mission with a reason, arrived at on purpose through Discovery rather than
inferred from whatever is busiest. A life view whose centre is implicit drifts toward whatever
shouted last.

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

### 3.3 Dreams feed the centre

Conjunction has no equivalent. In Focus, dreams are the raw material of purpose: they sit
below the fold, and promoting one is how the centre changes. This is the mechanic that makes
the centre *written* rather than *inherited*.

## 4. What Focus does not have

Named explicitly, because these are Conjunction features whose absence is the design:

- **No project switch.** There is one life. A switcher here would be a category error.
- **No membership or permissions.** Nothing is shared because nothing is shared *with* — there
  is no second party to scope against.
- **No second accent colour.** The two-ring bronze/steel language collapses to one ring: the
  Centurion's. The owner is the centre, and the centre has no colour.
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

One dangerous mistake exists in Focus, and it is not the wrong-project mistake Conjunction has
to defend against. It is **answering a purpose question with a task answer** — letting the
register read as "you are busy, therefore you are aligned".

So ALIGNED may only count work that traces to the stated purpose by name. Busy is not
evidence. If the purpose is empty or never written, ALIGNED says so plainly instead of
inferring one from activity.

---

## Open question for Adrian

**The fifth register.** Everything else here follows from Conjunction; ALIGNED is the one new
idea. Options:

1. **ALIGNED as a fifth register** (recommended) — reads at a glance, same weight as the other
   four, and gives the purpose a place to be visibly right or wrong.
2. **Purpose as the still centre only** — no fifth register; the purpose is stated in the middle
   and drift is left for the owner to notice.
3. **Alignment folded into WAITING ON YOU** — drift surfaces as an item needing a decision,
   rather than as a register. Cheaper, but it makes the purpose look like a task.

Recommendation: 1. Option 3 in particular hides the consequence that the thing being decided is
your purpose, not a piece of work.
