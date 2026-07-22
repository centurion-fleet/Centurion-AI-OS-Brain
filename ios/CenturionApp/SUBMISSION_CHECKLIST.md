# Sovereign Remote — App Store submission checklist

Centurion v5 lockstep (`MARKETING_VERSION` **5.0.1**). Complete before App Store submit.

## Listing name & price

- [ ] ASC **App Information** name = **Sovereign Remote** (not “Personal Centurion AI Remote”)
- [ ] Price = **Free**
- [ ] Description / promotional text from [`AppStoreDescription.md`](AppStoreDescription.md) — free for Centurion customers; Sovereign required
- [ ] Review Notes pasted from AppStoreDescription.md

## Encryption export compliance

**Plist:** `ITSAppUsesNonExemptEncryption = false` in [`Info.plist`](Info.plist) and [`project.yml`](project.yml).

**Draft ASC answers (exemption path):**

| Question (paraphrased) | Draft answer |
|------------------------|--------------|
| Does your app use encryption? | Yes — standard HTTPS/TLS for optional Help (Adrian) and Crypto Chat uses publicly available algorithms. |
| Is encryption proprietary / non-standard? | No. |
| Qualify for exemption? | Yes — encryption is limited to authentication / confidentiality using standard algorithms (X25519, XSalsa20-Poly1305 via libsodium) between the owner’s iPhone and their own Sovereign; plus ordinary HTTPS. |
| Export compliance documentation | Not required if exemption claimed; keep counsel confirmation on file. |

**Decision (shipping default):** Keep `false` (claim **exemption**). Crypto Chat uses standard, publicly available algorithms solely to protect communications between the owner’s iPhone and their own Sovereign (EAR Note 4 class).

**Before submit:** Have counsel confirm. Record:

```
Encryption questionnaire confirmed:
Date:
By:
ASC path: Exempt / Non-exempt (circle one)
```

## App Privacy / copy alignment

- Listing and keywords: see [`AppStoreDescription.md`](AppStoreDescription.md) (keywords ≤100 characters).
- Crypto Chat is not Centurion cloud storage.

### ASC App Privacy checklist (draft answers)

| Data type | Disclose? | Linked to user? | Used for tracking? | Notes |
|-----------|-----------|-----------------|--------------------|-------|
| User ID (install id) | Yes if Adrian used | Yes | No | Optional help only |
| Product Interaction / diagnostics (connection + thinking health labels) | Yes if Adrian used | Yes | No | Not Crypto Chat content |
| Other User Content (short mission summary) | Yes if Adrian used | Yes | No | Capped; not full mission dump |
| Crypto Chat transcripts | No | — | — | On device / Sovereign only |
| Contact info (beneficiary referral email/phone) | Yes if feature used | Yes | No | Stored on owner’s Sovereign for Family Beneficiary; not sold |

```
App Privacy answers updated in ASC:
Date:
By:
```

## Screenshots

Required device sizes must be real PNGs under [`AppStore/`](AppStore/) (not only HTML mockups). See [`AppStore/SCREENSHOTS.md`](AppStore/SCREENSHOTS.md).

Capture checklist:

- [ ] `iphone-67-01-home.png` — Home / Pulse
- [ ] `iphone-67-02-chat.png` — Crypto Chat
- [ ] `iphone-67-03-memory-horizon.png` — Memory Horizon
- [ ] `iphone-67-04-mission-or-soul.png` — Mission or Soul
- [ ] `iphone-67-05-privacy.png` — Link / Privacy
- [ ] Uploaded to ASC Media Manager (6.7")

## Features intentionally not shipped as unfinished

- Local-only Swarm **formation** UI removed; join / invite via Connect another Sovereign remains.
- Digest preference is **in-app attention** only — no OS push / local notification entitlement in this build.
- Beneficiary complimentary Sovereign fulfillment is **ops** (team contact) — not in-app provisioning.

## Privacy manifest

- [`PrivacyInfo.xcprivacy`](PrivacyInfo.xcprivacy) declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason **CA92.1** (same-app access).
- Tracking: false. Collected-data array left empty in the manifest; complete App Store Connect App Privacy answers to match Adrian optional help (see AppStoreDescription).

## Device smoke (pre-submit)

See [`DEVICE_SMOKE.md`](DEVICE_SMOKE.md). TestFlight What to Test: [`TestFlightWhatToTest.md`](TestFlightWhatToTest.md).
