# Centurion Remote — Design Rules (Locked)

**Version:** 1.0 · **Product:** CenturionAI Remote (iOS) · **Audience:** Successful adults 50+, non-technical, newly self-directed with personal AI

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
| **Innovation** | Novel, native use of Apple tech that defines the genre | Private LAN pairing, encrypted companion link, mission-centered AI — innovation serves trust, not spectacle |
| **Interaction** | Intuitive, effortless, platform-native | One obvious next step per screen; standard iOS patterns; 44pt targets; predictable navigation |
| **Social Impact** | Meaningful improvement to people's lives | Personal mission, agency, dignity — "you are in charge of your destiny" |
| **Visuals and Graphics** | Stunning, cohesive, skillfully drawn, animated with purpose | Frank Lloyd Wright warmth: amber/teal, serif editorial, restrained motion |

---

## 2. WWDC design principles (non-negotiable)

### Purpose
Every screen answers: *Why am I here? What can I do next?*
- One primary action per screen.
- Secondary/advanced actions behind "More" or Settings.

### Clarity
- Strong visual hierarchy: headline → explanation → action.
- No competing accents or equal-weight controls.
- State is visible in plain language ("Connected to your Centurion" not "Discovering").

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
| Remote Control, protocol, transport, Bonjour, mDNS | Your Centurion, private connection, on your network |
| LLM, model, provider, agent, sub-agent, loop phase | Your Centurion is working on… / Needs your decision |
| Output, filesystem path, source loop | Document / Ready for you |
| Soul (without context) | Your Centurion's Soul — personality and rules for your AI |
| Mission (without context) | Your life purpose, commitments, and personal context |
| XSalsa20, X25519, PFS, nonce | Your conversations stay private on your network |

### Mission vs Soul (locked)
| Term | Meaning | User-facing home |
|------|---------|------------------|
| **Mission** | The **human** — life purpose, active commitments, story/values/context | Mission screen, Mission Discovery, Pulse banner |
| **Soul** | The **Centurion** — AI personality, tone, rules (maps to desktop `SOUL.md`) | Your Centurion's Soul screen, Shape Your Centurion flow |

Never ask "what is your mission?" in Soul flows. Never describe human story/values in Soul surfaces.

### Cognitive load budget
- **Max 3** concepts per screen above the fold.
- **Max 1** decision per screen for first-run flows.
- **Max 5** tabs only if each is self-explanatory; prefer progressive disclosure over more tabs.

### Emotional tone
- Warm, direct, respectful — like a trusted advisor, not a startup landing page.
- Serif for reflection and mission; system sans for actions and settings.
- Celebrate completion; never punish exploration.

### First-run journey (target)
1. Welcome — what this is, in one paragraph.
2. Connect — find Centurion on your network (guided).
3. Mission Discovery — optional but invited, ceremonial.
4. Pulse — calm view of what your Centurion is doing for you.

---

## 4. Visual system lock

Use tokens from `Utils/CenturionTheme.swift` and `Utils/DesignSystem.swift` only.

| Token | Rule |
|-------|------|
| **Spacing** | `Spacing.*` multiples of 4 only |
| **Cards** | `.cardStyle()` — no hand-rolled duplicate card chrome |
| **Corners** | 16pt cards, 12pt buttons, 20pt hero surfaces — document new radii before adding |
| **Typography** | `.title`, `.title2`, `.headline`, `.body`, `.subheadline`, `.caption` — serif only for mission/editorial headlines |
| **Min body size** | 17pt equivalent at default Dynamic Type |
| **Min touch target** | 44×44pt hit area on all tappable elements |
| **Motion** | `Motion.*` springs; honor `@Environment(\.accessibilityReduceMotion)` |
| **Haptics** | Meaningful events only — never per-keystroke |

### Tab chrome
- Remote, Pulse, Security: `TabPageChrome` (no `BrandHeader`).
- Connect: pairing ceremony may use `BrandHeader` once.
- Settings: native `Form` — familiar to iOS users.

---

## 5. Information architecture lock

### Five tabs — human names (display)
| Tab | User-facing purpose | Default content |
|-----|---------------------|-----------------|
| Connect | Link to your Centurion | Connection status + simple reassurance |
| Chat | Talk with your Centurion | Conversations, calm messaging |
| Home | What your Centurion is doing | Human outcomes, not agent topology |
| Privacy | Your data stays yours | Plain-language trust; crypto behind "Technical details" |
| You | Mission, about you, appearance | Personal, not administrative |

*(Implementation may still use internal names during migration.)*

### Pulse internal categories — human names
| Internal | User-facing |
|----------|-------------|
| Live | Working on now |
| Wins | Finished for you |
| Outputs | Documents |
| Decisions | Needs your choice |
| Pulse | Updates |

### Progressive disclosure
- **Layer 1 (default):** Outcome + one action.
- **Layer 2 (tap):** Context and options.
- **Layer 3 (Settings / Privacy):** Technical truth for the curious.

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
- [ ] Accessibility Nutrition Labels evaluated for Connect, Chat, Mission Discovery, Settings

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

*This document is the human-readable source of truth. Cursor enforces it via `.cursor/rules/ios-centurion-design.mdc`.*
