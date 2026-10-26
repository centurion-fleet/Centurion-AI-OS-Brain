# Sovereign AI Remote — App Store submission checklist

Centurion v5 lockstep (`MARKETING_VERSION` **5.4.0** / build **63**). Complete before App Store submit.

## Listing name & price

- [ ] ASC **App Information** name = **Sovereign AI Remote**
- [ ] Price = **Free**
- [ ] Description / promotional text from [`AppStoreDescription.md`](AppStoreDescription.md) — free for Centurion customers; Sovereign required
- [ ] Review Notes pasted from AppStoreDescription.md
- [ ] ASC iOS version created as **5.3.8** (not a stale 5.0.1 / 5.2.x / 5.3.0 train)

## Encryption export compliance

**Plist:** `ITSAppUsesNonExemptEncryption = false` in [`Info.plist`](Info.plist) and [`project.yml`](project.yml).

**Draft ASC answers (exemption path):**

| Question (paraphrased) | Draft answer |
|------------------------|--------------|
| Does your app use encryption? | Yes — standard HTTPS/TLS for optional Help (Adrian) and Crypto Chat uses publicly available algorithms. |
| Is encryption proprietary / non-standard? | No. |
| Qualify for exemption? | Yes — encryption is limited to authentication / confidentiality using standard algorithms (X25519, XSalsa20-Poly1305 via libsodium) between the owner’s iPhone and their own Sovereign; plus ordinary HTTPS. |
| Export compliance documentation | Not required if exemption claimed; keep counsel confirmation on file. |

**Decision (shipping default):** Keep `false` (claim **exemption**).

**Before submit:** Have counsel confirm. Record:

```
Encryption questionnaire confirmed:
Date:
By:
ASC path: Exempt / Non-exempt (circle one)
```

## App Privacy / copy alignment

- Listing and keywords: see [`AppStoreDescription.md`](AppStoreDescription.md) (keywords ≤100 characters).
- Crypto Chat content is not Centurion cloud storage.
- Anywhere: E2E content; Centurion cloud may see connection metadata/presence only when Chat from anywhere is enabled.
- Family & friends referrals: contact info stored on the owner’s Sovereign (optional); disclose in ASC if the feature is used.

### ASC App Privacy checklist (draft answers)

| Data type | Disclose? | Linked to user? | Used for tracking? | Notes |
|-----------|-----------|-----------------|--------------------|-------|
| User ID (install id) | Yes if Adrian used | Yes | No | Optional help only |
| Product Interaction / diagnostics (connection + thinking health labels) | Yes if Adrian used | Yes | No | Not Crypto Chat content |
| Other User Content (short mission summary) | Yes if Adrian used | Yes | No | Capped; not full mission dump |
| Crypto Chat transcripts | No | — | — | On device / Sovereign only |
| Contact info (Family & friends referral email/phone) | Yes if feature used | Yes | No | Stored on owner’s Sovereign for Family Beneficiary; not sold |

```
App Privacy answers updated in ASC:
Date:
By:
```

## Screenshots

Required device size is **iPhone 6.5"** (1284×2778). Real PNGs live under [`AppStore/`](AppStore/) — see [`AppStore/SCREENSHOTS.md`](AppStore/SCREENSHOTS.md). Build **59+** is **iPhone-only**, so App Store Connect must not require a 13-inch iPad slot once that binary is selected.

Capture checklist:

- [ ] `iphone-65-01-focus.png` — Focus / Missions (1284×2778)
- [ ] `iphone-65-02-chat.png` — Crypto Chat
- [ ] `iphone-65-03-memory-horizon.png` — Memory Horizon
- [ ] `iphone-65-04-mission.png` — Life Mission
- [ ] `iphone-65-05-connect.png` — Link / Connect (**Scan QR**)
- [ ] `iphone-69-01-focus.png` — Focus / Missions (1290×2796) when Media Manager shows 6.9"
- [ ] `iphone-69-02-chat.png` — Crypto Chat
- [ ] `iphone-69-03-memory-horizon.png` — Memory Horizon
- [ ] `iphone-69-04-mission.png` — Life Mission
- [ ] `iphone-69-05-connect.png` — Link / Connect (**Scan QR**)
- [ ] Uploaded to ASC Media Manager (6.5-inch 1284×2778, 6.9-inch if present). iPad 13" is **not** required for iPhone-only build **59+**.

## Camera / QR pairing disclosure

- [`NSCameraUsageDescription`](project.yml) — camera used **only** to scan the pairing QR on the Centurion screen.
- Review notes: pair on home Wi‑Fi via QR; **Chat from anywhere** (when enabled on the Brain) uses Centurion outbound relay — no customer port-forward. Paste fallback available.

## Features intentionally not shipped as unfinished

- Digest preference is **in-app attention** only — no OS push / local notification entitlement in this build.
- Beneficiary complimentary Sovereign fulfillment is **ops** (team contact) — not in-app provisioning.
- Desk skills / fleet / plugins / Telegram on the phone are **glance** (status only).

## Privacy manifest

- [`PrivacyInfo.xcprivacy`](PrivacyInfo.xcprivacy) declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason **CA92.1** (same-app access).
- Tracking: false. Collected-data array left empty in the manifest; complete App Store Connect App Privacy answers to match Adrian optional help and Family referrals (see AppStoreDescription).

## Device smoke (pre-submit)

See [`DEVICE_SMOKE.md`](DEVICE_SMOKE.md). TestFlight What to Test: [`TestFlightWhatToTest.md`](TestFlightWhatToTest.md).

**Away App Store “works anywhere” wording:** still gated until Away DoD in `brain/linux/docs/REMOTE_RELAY.md` is green on cellular + CGNAT.

## Accessibility (pre-submit)

- [ ] Dynamic Type on Chat / You / Focus
- [ ] VoiceOver on Chat / You / Focus
- [ ] 44pt targets on primary actions (Scan QR, send, Form swarm)
