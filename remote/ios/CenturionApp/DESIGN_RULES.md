# Sovereign Remote — Design Rules (Locked)

**Version:** 1.1 · **Product:** Sovereign Remote (iOS) · **Audience:** Successful adults 50+, non-technical, newly self-directed with personal AI

**Locked release (v1.1):** Calm Remote UX (device link ≠ thinking, Get Help, plain language) + **Adrian** online (You only, founder mission-first personality). Do not regress without explicit product review.

This ruleset synthesizes the **2025–2026 Apple Design Awards** criteria, **WWDC25/26 design principles**, **Human Interface Guidelines**, and **Centurion Companion Calm** — our audience-specific layer.

Sources:
- [Apple Design Awards 2026](https://developer.apple.com/design/awards/) — six categories
- [Principles of great design (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/250/) — purpose, clarity, flexibility, simplicity
- [Principles of inclusive app design (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/316/)
- [Accessibility Nutrition Labels (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/224/)
- [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

---

## 1. Apple Design Award alignment

Every screen must consciously serve at least one category. Ship nothing that only looks good in a screenshot.

| Category | Apple expects | Centurion interpretation |
|----------|---------------|--------------------------|
| **Delight and Fun** | Memorable, satisfying, enhanced by Apple tech | Ceremonial moments (Mission Discovery), warm haptics, earned celebration — never gimmicks |
| **Inclusivity** | Works for varied abilities, ages, languages | Dynamic Type, VoiceOver, high contrast, plain language, no jargon on default surfaces |
| **Innovation** | Novel, native use of Apple tech that defines the genre | Crypto Chat (private LAN pairing + encrypted companion link), mission-centered AI — innovation serves trust, not spectacle |
| **Interaction** | Intuitive, effortless, platform-native | One obvious next step per screen; standard iOS patterns; 44pt targets; predictable navigation |
| **Social Impact** | Meaningful improvement to people's lives | Personal mission, agency, dignity — "you are in charge of your destiny" |
| **Visuals and Graphics** | Stunning, cohesive, skillfully drawn, animated with purpose | Centurion v5: cream canvas, near-ink text, cool interactive blue for chrome; serif editorial; restrained motion (see `shared/shared/design-tokens/tokens.json`) |

---

## 2. WWDC design principles (non-negotiable)

### Purpose
Every screen answers: *Why am I here? What can I do next?*
- One primary action per screen.
- Secondary/advanced actions behind "More" or Settings.

### Clarity
- Strong visual hierarchy: headline → explanation → action.
- No competing accents or equal-weight controls.
- State is visible in plain language ("Connected to your Sovereign" not "Discovering").

### Simplicity (friction removal, not minimalism)
- Strip machinery from default views.
- Every element earns its place.
- Add words when they reduce confusion; remove chrome when it adds noise.

### Flexibility
- Support Dynamic Type through semantic text styles — **never** fixed sizes below 15pt for body copy.
- Respect Reduce Motion.
- Support Light/Dark with consistent meaning (accent = action, muted = supporting).

---

## 3. Centurion Companion Calm (audience lock)

**Who:** Executives and founders 50+ who delegate IT. First time feeling directly in charge of powerful AI.

**They must feel:** Calm, capable, trusted, unhurried, never stupid.

**They must never feel:** Like they're operating a dev console, reading a security whitepaper, or failing a technical exam.

### Language rules
| Never (default UI) | Always |
|--------------------|--------|
| Remote Control, protocol, transport, Bonjour, mDNS | Your Sovereign, private connection, on your network |
| LLM, model, provider, agent, sub-agent, loop phase | Your Sovereign is working on… / Needs your decision |
| Output, filesystem path, source loop | Document / Ready for you |
| Soul (without context) | Your Sovereign's Soul — personality and rules for your AI |
| Mission (without context) | Your life purpose, commitments, and personal context |
| XSalsa20, X25519, PFS, nonce | Your conversations stay private on your network |

### Mission vs Soul (locked)
| Term | Meaning | User-facing home |
|------|---------|------------------|
| **Mission** | The **human** — life purpose, active commitments, story/values/context | Mission screen, Mission Discovery, Pulse banner |
| **Soul** | The **Centurion** — AI personality, tone, rules (maps to desktop `SOUL.md`) | Your Sovereign's Soul screen, Shape Your Sovereign flow |
| **Plan** | A **reviewable proposal** from your Sovereign before consequential work. Shown on Focus as **Missions** (synced from Brain). Distinct from Life Mission (purpose). | Chat “Propose first”, Focus **Missions** / Needs your choice / Documents, Plan review |
| **Memory Horizon** | **How Centurion remembers** — Hot Cache, Session Recall, Vault (not life purpose) | You → Your Sovereign → Memory Horizon; Desktop Settings → Your Sovereign |

Never ask "what is your mission?" in Soul flows. Never describe human story/values in Soul surfaces. Life Mission is purpose (Mission Stack). The Focus **Missions** pill is the reviewable work queue that syncs with Brain. Never call Memory Horizon “Mission” — Memory Horizon is recall layers. Hot Cache fill is a **software budget**, not appliance RAM; Session Recall / Vault grow with use and share **disk on your Sovereign**.

### Cognitive load budget
- **Max 3** concepts per screen above the fold.
- **Max 1** decision per screen for first-run flows.
- **Three tabs** — Chat, Focus, You. Prefer progressive disclosure over more tabs. Pairing, thinking, privacy, and Family & friends live under You, behind sub-menus.

### Emotional tone
- Warm, direct, respectful — like a trusted advisor, not a startup landing page.
- Serif for reflection and mission; system sans for actions and settings.
- Celebrate completion; never punish exploration.

### First-run journey (target)
1. Welcome — what this is, in one paragraph.
2. Link — find Centurion on your network in **You** (guided).
3. Mission Discovery — optional but invited, ceremonial.
4. Pulse — calm view of what your Sovereign is doing for you.

---

## 4. Visual system lock

Use tokens from `Utils/CenturionTheme.swift` and `Utils/DesignSystem.swift` only.

### Tab chrome (v2 — award restyle)

Use `MainTabChrome` on all **four** main tabs with **`CompactBrandHeader`** (app mark + "SOVEREIGN").

| Context | Header |
|---------|--------|
| Main tabs (Chat, Focus, You) | `CompactBrandHeader` via `MainTabChrome` |
| Secondary screens (Mission, Soul, Memory Horizon, Get Help, Adrian, Privacy & Trust, Discovery, …) | `FullBrandHeader` |
| Sheets / modals | `SheetHeader` or navigation title only — no full brand |

Full token + component reference: **`STYLING_GUIDE.md`**.

| Token | Rule |
|-------|------|
| **Spacing** | `Spacing.*` multiples of 4 only |
| **Cards** | `.centurionCard()` — no hand-rolled duplicate card chrome |
| **Corners** | `Radius.sm/md/lg` — document new radii in STYLING_GUIDE before adding |
| **Typography** | `Typography.*` — serif only for mission/editorial |
| **Min body size** | 17pt equivalent at default Dynamic Type |
| **Min touch target** | 44×44pt hit area on all tappable elements |
| **Motion** | `Motion.*` springs; honor `@Environment(\.accessibilityReduceMotion)` |
| **Haptics** | Meaningful events only — never per-keystroke |

---

## 5. Information architecture lock

### Three tabs — human names (display)
| Tab | User-facing purpose | Default content |
|-----|---------------------|-----------------|
| Chat | Talk with your Sovereign | Conversations, calm messaging |
| Home | What your Sovereign is doing | Human outcomes, not agent topology |
| You | Personal hub | You first (Mission, Soul, Autonomy), then Your Sovereign, Collaborations, Family & friends, Connect, This Brain, Privacy & Trust, Help & about |

**Connect is not a tab.** Mission, Soul, and Autonomy open at the top of **You**. Pairing lives under **You → Connect**. Thinking, memory, and reporting live under **You → Your Sovereign**. Family & friends is lower in the same list.

**Privacy is not a separate tab.** Full privacy comparison lives under **You → Privacy & Trust** (`SecurityHubView`).

*(Implementation may still use internal names during migration.)*

### Pulse internal categories — human names
| Internal | User-facing |
|----------|-------------|
| Live | Working on now |
| Plans | Plans (reviewable proposals) |
| Wins | Finished for you |
| Outputs | Documents |
| Decisions | Needs your choice |
| Pulse | Updates |

### Progressive disclosure
- **Layer 1 (default):** Outcome + one action.
- **Layer 2 (tap):** Context and options.
- **Layer 3 (You → Privacy & Trust):** Technical truth and comparison tables for the curious — and for clients who need to answer "AI is unsafe" pushback.

---

## 6. Workflow rules

1. **Truthful state** — Never show preview data as live. Demo mode must be labeled.
2. **Recoverable errors** — Every failure gets words + retry. Haptics alone are insufficient.
3. **Persistent context** — Tab switches must not destroy conversation, scroll, or form progress.
4. **One completion path** — Mission Discovery ends with one clear "Save" (share is optional follow-up).
5. **Connection before capability** — Chat and share explain what's needed when offline.
6. **Accessible alternatives** — No interaction relies solely on long-press, dot color, or 7pt labels.

---

## 7. Accessibility checklist (ship gate)

Before any release:
- [ ] VoiceOver labels on all interactive elements
- [ ] Dynamic Type to AX5 without clipping on primary flows
- [ ] Contrast ≥ 4.5:1 for body text (WCAG AA)
- [ ] Reduce Motion disables orbital/loop animations
- [ ] Accessibility Nutrition Labels evaluated for Chat, You, Mission Discovery

---

## 8. Anti-patterns (reject in review)

- Fixed font sizes below 15pt for readable content
- Monospaced micro-labels on default surfaces
- Hardcoded preview data presented as live
- Cryptographic algorithm names above the fold
- LLM provider selection as a primary onboarding step
- Simulated success when disconnected
- Duplicate security copy across tabs
- Nested share sheets
- "Discuss" buttons that only open chat without carrying context
- Developer paths (`/outputs/...`) in user-visible UI

---

## 9. Review cadence

- **Every PR touching `ios/CenturionApp/Views/`:** Section 3 language rules + Section 6 workflow rules.
- **Monthly:** Full tab walkthrough as a new user aged 55+.
- **Pre-release:** Section 7 accessibility checklist + Apple Design Award self-score (1–5 per category).

---

## 10. Calm Remote UX (locked)

### Device link vs thinking service
- **Device link** — iPhone connected to the Sovereign computer on the LAN.
- **Thinking service** — whether the Sovereign on the computer can think.
- Never merge these into one status on default surfaces.

### Get Help (host-backed)
- Support codes, auto-fix, and health checks require a device link.
- Plain language only; no provider slugs on iPhone default paths.
- One filled primary CTA per screen.

### Adrian (cloud-backed) — locked

- **Single source of truth:** support content lives only in the **personal-centurion-help-center** repo (`content/`). Web Ask Adrian (`/api/ask`) and iPhone Talk to Adrian (`/api/v1/chat`) both retrieve from those articles. Do not duplicate procedures in iOS strings or `centurion_cli/adrian/knowledge.md` for customer-facing guidance.
- **Adrian** is Adrian online — Sovereign's creator, hosted at [help.1human1ai.com](https://help.1human1ai.com); no customer API keys.
- **Placement:** **You** → Support only (`Talk to Adrian` beside Get Help). No global floating control on other tabs.
- **Passion:** help users **live their mission** — lift daily pressure, free thinking, deepen 1:1 with private Sovereign.
- **Evolving mission:** missions change over time; never treat mission as a one-time checkbox.
- **Personality:** listen first; one step at a time (Loop: understand → act → adjust); expert before advising; plain language.
- **Superpowers:** AI speed clears the path; human creativity dreams the future — Adrian aligns both.
- **Privacy:** independent of LAN link; sanitized context only; never chat history or secrets.
- **Welcome copy** lives in `AdrianService.seedWelcomeIfNeeded()` — update only with DESIGN_RULES + prompt/knowledge alignment.

### Do not regress (v1.1 ship gate)

- [ ] Device link and thinking service remain separate sections on You
- [ ] No provider slugs or dev jargon on default iPhone surfaces
- [ ] Adrian not promoted on Chat or Home tabs
- [ ] Adrian intro reflects mission-first founder voice, not generic helpdesk tone

---

## 11. Swarm / Collaborations (locked)

**Placement:** Ambient constellation on **Home** — not a sixth tab. Progressive drill-in via orb tap (detail sheet) and "+N" (full constellation sheet). Tertiary list in **You → Collaborations**.

### Language rules

| Never (default UI) | Always |
|--------------------|--------|
| Swarm, sub-agent, kanban, column, task board | Collaboration, your Sovereigns |
| Blocked task, sprint phase, dispatcher | Paused, in progress, needs your choice |
| Agent topology, spawn tree | Show how it's working (opt-in) |

### Pulse ↔ orb vocabulary

| Internal `pulse` | User-facing (orb + subtitle) | Home badge |
|------------------|------------------------------|------------|
| `idle` | Working smoothly | none |
| `active` | In progress | Working on now dot |
| `attention` / `waiting` | Needs your choice / Waiting for you | Decisions pill + orb beacon |
| `blocked` | Paused | See what's needed |
| `complete` | Finished for you | Wins (48h) |

**No red/error colors for Swarm attention** — reserve red for connection loss only.

### Human attention model

- Humans see **Signals** only (decisions, ceremonies) — not handoffs, tool progress, or activity log.
- Pulse attention setting (in-app only): **Surface decisions in the app when needed** (default) vs **Keep Pulse quieter until I open it**. Does **not** schedule OS push or local notifications in the current ship.
- Collaboration entry: **Start a collaboration** — Form a local swarm, empty board, or Join/Invite via Mission Control. A down portal must fail honestly.

### Brain vs Remote architecture

Sovereign Remote is a pocket mission cockpit, not the collaboration database.
The Linux Centurion Brain owns all collaboration state under the active
`CENTURION_HOME`:

| Layer | Owns | Remote sees |
|-------|------|-------------|
| Linux Brain | kanban boards, workspaces, portal tokens, artifacts, Signals, outcomes | mission-progress summaries and actions |
| iPhone Remote | digest preference, last-seen timestamps, transient render cache | no canonical Swarm data |

Default mobile surfaces must include everything the human needs to progress
their mission while out in the world:

- Orient: constellation, Pulse badges, mission grounding.
- Decide: open Signals with one clear action.
- Receive: finished documents/outcomes, readable and shareable.
- Steer: Discuss with collaboration context carried back to the Brain.
- Collaborate: **Start a collaboration** (local board); portal invite/connect frozen. Brain owns boards.

### Collaboration isolation

One collaboration maps to one hard sharing boundary:

- LAN-local collaboration: one kanban board (`CENTURION_KANBAN_BOARD` pins
  workers so they cannot see other boards).
- Portal collaboration: one `ctk_proj_*` project token.
- Files: one collaboration workspace path; Remote never shows raw paths by
  default.
- Memory and chat: scope by `swarm_id` / board slug before adding mission
  context.

Centurions may share comments, tasks, artifacts, and outcomes inside that
collaboration boundary. They must not see unrelated boards, portal projects,
workspaces, memories, or chat context unless the human explicitly links them.

### Ship gate (Swarm UX)

- [ ] No sixth tab for collaborations
- [ ] Home hero shows constellation (not a task list) when swarms exist
- [ ] Default surfaces use plain language from table above
- [ ] Orb motion honors Reduce Motion
- [ ] Demo swarms labeled when `showsDemoContent` is on
- [ ] Remote reads collaboration state from the Sovereign Brain; iPhone stores
      only preferences/cache
- [ ] Dashboard `/mission` and Remote use the same Brain-owned snapshot service

---

## 12. Orb visual system (locked)

Two orb families share `OrbDesign` tokens in `DesignSystem.swift`:

| Orb | Meaning | Motion character |
|-----|---------|------------------|
| **Mission Orb** | Human's Life Mission — gravitational north star | Ultra-slow 6s breath; compass rose; never urgent |
| **Swarm Orb** | One collaboration — Centurions at work | Pulse-driven; same state machine as §11 |

### Material language (both orbs)

- **Atmosphere veil** — radial teal→accent mist behind the orb (moody, not neon).
- **Art Deco arcs** — three trimmed metallic ring segments (120° offset), slow drift.
- **Gem core** — pearl highlight + radial gradient nucleus; specular offset highlight.
- **Human gold** — `#EBC773` participant node; invitation states warm this, never red.

### Swarm pulse → emotional read (motion states fixed)

| `pulse` | Existing motion | Enhanced emotional layer |
|---------|-----------------|--------------------------|
| `idle` / `forming` | 3.5s breath + slow orbit | Hearth mist; satellites drift lazily |
| `active` | 3s breath + 10s rotation | Filaments to active Centurions; core glow pulse |
| `attention` | 0.8s beacon | Gold invitation ripple + gradient halo |
| `waiting` | 2-count beacon | Ripple with pause between cycles; human node scales with beacon |
| `blocked` | 2.5s throb | Mist contracts; core dims — held breath, not failure |
| `complete` | still | Pearl afterglow ring; settled gem |

### Mission Orb states

- **Unset mission** — seed constellation dots; lower mist; invite Discovery.
- **Set mission** — brighter core; tether line to collaboration row on Focus hero.

### Ship gate (orbs)

- [ ] All orb motion respects Reduce Motion
- [ ] No red for collaboration attention
- [ ] Mission Orb appears above collaboration constellation on Focus when swarms exist
- [ ] VoiceOver describes mission/collaboration state without internal pulse names

---

## Pairing (Connect) — QR first

- Primary CTA: **Scan QR code** (camera). Payload is the existing `token:…@lan-host:9119` string for **home Wi‑Fi pairing**.
- Secondary: **Paste code instead** (accessibility / no-camera / App Review).
- Do not present paste as the default path. Away-from-home uses **Chat from anywhere** (Centurion relay) after enable — not DIY tunnel/public `:9119` as the default topology. Same Wi‑Fi / Bonjour is optional convenience at home.

---

*This document is the human-readable source of truth. Cursor enforces it via `.cursor/rules/ios-centurion-design.mdc`.*
