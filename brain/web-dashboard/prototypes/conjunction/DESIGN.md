# CONJUNCTION — a fresh design for the Collab tab

**Brief (Adrian, 26 Sep 2026):** the page must tell a human, without explanation, what the two
Centurions have delivered, what they have planned, which one is doing what, what questions are
waiting for a human, and the register of decisions made. Graphics over words. Stunning, not
average — and promotable across Europe and Asia.

---

## 1. The idea

**Conjunction** — the astronomical term for two bodies coming into alignment. It names the only
thing this page is about. It travels: *coniunctio, conjonction, Konjunktion, congiunzione, conjunción*
— and translates into Asian markets without importing American startup vocabulary. It sounds like
something that mattered before software existed, which is the whole positioning: **an instrument, not
a dashboard.**

The page is not a status board. It is a reading. The hero is an armillary — a paper instrument of
the kind the Islamic world, Greece and Europe used to track bodies moving together against a fixed
sky. It is cool, exact and old; nothing about it reads Silicon Valley.

## 2. What each part says, and why it needs no explanation

| Element | Reads as | Data behind it |
|---|---|---|
| Two counter-tilted rings | two independent minds, at work | one ring per Centurion |
| Their crossing, with a flare | the moment the two align — a handoff | items passed between Brains |
| The still centre, "THE STILL CENTRE — YOU" | the human is the axis everything turns about | the owner |
| Sealed beads along the lower arc | work finished, accumulating | delivered items, newest largest |
| Hollow rings riding the ring | work in hand, and whose ring it rides on | live per-Centurion work |
| Amber **diamond** | stopped, waiting for a person | blocked items |
| Outer ring of marks | the record of decisions | register: filled = decided, hollow amber = still open |
| Amber pointer from the centre | what the instrument is reading right now | the newest urgent item |

## 3. Colour discipline (Kennedy's Rule 2, kept strictly)

Three signals, and only three:

- **Bronze** — one Centurion (matte, engraved)
- **Steel** — the other (matte, engraved)
- **Amber** — the human. Reserved. Nothing else on the page may use it, *and it never appears as a
  plain dot*: the waiting state always carries the diamond shape too. That survives greyscale,
  colour-blindness, and a phone at arm's length — which matters because this page will be
  photographed and forwarded.

The first draft failed this test: amber and bronze sat too close together and the whole hero was
too subtle to read. Field 02 fixed the read; field 03 gave it physical depth.

## 4. Craft decisions worth keeping

- **Light comes from above** (Kennedy 1). Each ring is drawn as two arcs: the far half is a thin,
  dim hairline that takes the highlight where it faces the sky; the near half is heavier and
  brighter, with its own bloom. The instrument stands in its own pool of shadow.
- **One motion, and it means something — REVISED 3 Oct 2026.** The rings settle into place on load,
  then the crossings flare once — *coming into conjunction*. After that they **keep turning, slowly
  and against each other**: `spin-cw` 190s / `spin-ccw` 230s, `linear infinite`.
  ⚠️ **This supersedes the original rule on this page — *"No ambient animation: a page that is
  always moving cannot be photographed."*** That rule is retired, and the reason matters: the two
  readings were in conflict and **liveness won.** What the old rule protected — a frame that
  survives being photographed and forwarded — is now met by the **rate** rather than by stillness:
  190s and 230s per revolution is slow enough that any single frame is legible, while the motion
  itself is the page's proof that this is a live reading and not a still. The owner confirmed the
  change on 3 Oct 2026 and directed the same treatment onto Stillpoint, so the two instrument pages
  read as one language. `prefers-reduced-motion` stops both, as it always did.
- **Whitespace is the default.** Plates are generous; the registers breathe.
- **Words are demoted.** Every register is legible as shape first, label second. The labels name
  what the shape already said.

## 5. What is not built yet

- **It is not wired.** Field 01–03 run on sample state filled with real, observed figures. The
  bridge actions it needs already exist: `fleet_peer_status` (peers + each one's activity),
  `swarm_snapshot` (boards and cards), plan/decision lists for the register, `fleet_inbox`.
- **The promotion claim is unwritten.** The page wants one true sentence — something like "the first
  instrument for two private intelligences working as one" — and it must be *true* before it is
  printed. Steve and Kim working live is what makes it true, and that is not yet witnessed.
- **No fonts are self-hosted yet.** The prototype uses a system serif/sans stack deliberately;
  shipping should self-host (a transitional serif for numerals + a neutral sans).

## 6. Files

- `field-01.html` — first pass. Kept: it shows the problem (too subtle to read).
- `field-02.html` — legibility pass: heavier rings, direct ring labels, amber carries a shape.
- `field-03.html` — **the current one.** Depth, sky light, the conjunction axis, one moment of motion.
