# CenturionAI Remote — App Styling Guide

**Version:** 2.0 · **Product:** Personal Centurion Remote (iOS)  
**Principles:** Calm, premium, quietly powerful — subtle Art Deco, warm amber, aged metallics, moody atmospheric lighting.

Companion to [DESIGN_RULES.md](DESIGN_RULES.md) (audience + language lock). This guide owns **tokens, materials, and component behavior**.

---

## 1. Design principles

| Principle | Expression |
|-----------|------------|
| **Purpose** | One primary action per screen; state in plain language |
| **Clarity** | Headline → explanation → action; no competing accents |
| **Calm power** | Depth through atmosphere, not decoration |
| **Art Deco restraint** | Trimmed arcs, compass geometry, metallic rims — never full neon |
| **Token-first** | No magic numbers; use `ColorTheme`, `Spacing`, `Radius`, `Elevation`, `Typography` |

---

## 2. Color tokens

Semantic roles (implement in `CenturionTheme.swift`):

| Token | Role |
|-------|------|
| `background()` | Page canvas — deep teal (dark) / warm cream (light) |
| `surface()` | Cards, bubbles |
| `surfaceElevated()` | Hero cards, modals |
| `accent()` | Primary action — gold (dark) / Centurion blue (light) |
| `dimAccent()` | Secondary accent |
| `amber()` / `agedBronze()` / `atmosphereTeal()` | Brand ramp — orbs, rims, atmosphere |
| `primaryText()` / `mutedText()` | Body hierarchy |
| `border()` | Hairline separation |
| `success()` / `error()` | Functional only — error = connection loss |

**Rule:** Collaboration attention uses warm gold, never error red.

---

## 3. Typography

| Style | Use | Font |
|-------|-----|------|
| `Typography.brandWordmark` | "PERSONAL CENTURION" compact header | System, semibold, tracked caps |
| `Typography.editorialTitle` | Mission statements, ceremony | Serif, `.title2`+ |
| `Typography.screenTitle` | Section heroes | `.title3` semibold |
| `Typography.body` | Default copy | `.body` (≥17pt at default DT) |
| `Typography.caption` | Supporting | `.caption` |
| `Typography.sectionLabel` | Section headers | `.caption` semibold, uppercase, tracked |

Serif **only** for mission/reflection. Actions and settings use system sans.

---

## 4. Spacing & layout

- Grid: multiples of 4 via `Spacing.*`
- Screen horizontal padding: `Spacing.md` (16)
- Max content width: 428pt centered
- Min touch target: 44×44pt
- Max 3 concepts above the fold

---

## 5. Radius & elevation

| Token | Value | Use |
|-------|-------|-----|
| `Radius.sm` | 12 | Buttons, chips |
| `Radius.md` | 16 | Cards |
| `Radius.lg` | 20 | Hero surfaces |
| `Radius.pill` | 999 | Pills |

Elevation via `Elevation.card` shadow + `AtmosphericSurface` vignette — moody, not Material-heavy.

---

## 6. Motion & haptics

- Springs: `Motion.standard`, `.appear`, `.heavy`, `.light`, `.celebratory`
- Honor `@Environment(\.accessibilityReduceMotion)`
- Haptics: meaningful events only (`Haptics.*`)

---

## 7. Header system (v2)

| Context | Component |
|---------|-----------|
| **Main tabs** (Chat, Home, You) | `CompactBrandHeader` — mark + "PERSONAL CENTURION" |
| **Secondary screens** (Mission, Soul, Get Help, Adrian, Privacy & Trust, …) | `FullBrandHeader` — mark + product name + tagline |
| **Sheets / modals** | No header, or `SheetHeader` (title only) |

Main tabs use `MainTabChrome` (compact brand + optional screen chrome).

---

## 8. Components

| Component | Purpose |
|-----------|---------|
| `AtmosphericSurface` | Card with vignette + optional metallic rim |
| `MetallicRim` | Art Deco arc overlay |
| `.centurionCard()` | Standard elevated card |
| `CenturionPrimaryButton` / `Secondary` / `Ghost` | Actions |
| `CenturionPillNav` | Home category pills |
| `CenturionSectionHeader` | Section labels |
| `CenturionListRow` | Settings / list rows |
| `CenturionStatusCard` | Link and thinking status cards (You tab) |
| `EmptyState` / `LoadingState` / `ErrorState` / `SuccessMoment` | Universal states |
| `SwarmOrb` / `MissionOrb` | Living collaboration + mission instruments |

---

## 9. Visual language

### Materials
- **Atmosphere:** radial teal mist behind warm cores
- **Metallic rim:** angular gradient on trimmed arcs (aged bronze + amber)
- **Pearl highlight:** specular offset on gem nuclei (orbs, hero icons)

### Lighting
- Dark mode: deep `#041c1c` canvas, gold accents glow softly
- Light mode: cream `#f5f0e8` canvas, blue accent for actions

### Icons
- SF Symbols, `.semibold` weight for section headers
- Accent color for semantic icons; muted for decorative

---

## 10. State treatment

| State | Treatment |
|-------|-----------|
| **Empty** | `EmptyState` — icon, serif-friendly headline, one CTA |
| **Loading** | `LoadingState` — calm spinner + plain words |
| **Error** | `ErrorState` — words + retry; never haptics alone |
| **Success** | `SuccessMoment` — brief, earned; optional soft haptic |

---

## 11. Screen mapping

| Tab | View | Header |
|-----|------|--------|
| Chat | `ChatView` | Compact |
| Home | `MissionPortfolioView` | Compact |
| You | `SettingsView` | Compact (+ sales hero, link, thinking inline) |

**Privacy & Trust** (`SecurityHubView`) is a secondary sheet under You — not a tab.

---

*Enforced in code via `Utils/CenturionTheme.swift`, `Utils/DesignSystem.swift`, `Utils/CenturionComponents.swift`.*
