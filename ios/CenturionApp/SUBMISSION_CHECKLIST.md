# Sovereign Remote — App Store submission checklist

Centurion v5 lockstep (`MARKETING_VERSION` **5.0.1**). Complete before TestFlight / App Store submit.

## Encryption export compliance

**Plist:** `ITSAppUsesNonExemptEncryption = false` in [`Info.plist`](Info.plist) and [`project.yml`](project.yml).

**Decision (shipping default):** Keep `false` (claim **exemption**). Crypto Chat uses standard, publicly available algorithms (X25519 key agreement, XSalsa20-Poly1305 via libsodium / swift-sodium) solely to protect communications between the owner’s iPhone and their own Sovereign. That is the same class of use many apps declare under the EAR **Note 4** exemption for encryption that is publicly available and used for authentication / confidentiality of data.

**Before submit:** Have counsel / App Store Connect questionnaire confirm this exemption still applies to your build. Record confirmation date below. If Apple’s questionnaire routes you to a non-exempt path, set `ITSAppUsesNonExemptEncryption` to `true` and complete the annual self-classification report — do not ship a false claim.

**Do not** describe Crypto Chat as proprietary “military” crypto that would imply non-standard classification in App Store Connect answers.

```
Encryption questionnaire confirmed:
Date:
By:
ASC path: Exempt / Non-exempt (circle one)
```

## App Privacy / copy alignment

- Listing and keywords: see [`AppStoreDescription.md`](AppStoreDescription.md) (keywords ≤100 characters).
- Crypto Chat is not Centurion cloud storage.
- Optional Adrian may send install id, app version, connection/thinking health, short mission summary to help.1human1ai.com — disclose in App Privacy if you answer “Yes” for those data types when Adrian is used.

### ASC App Privacy checklist (match Connect answers)

| Data type | Disclose? | Notes |
|-----------|-----------|-------|
| User ID (install id) | Yes if Adrian used | Optional help only |
| Product Interaction / diagnostics (connection + thinking health labels) | Yes if Adrian used | Not Crypto Chat content |
| Other User Content (short mission summary) | Yes if Adrian used | Capped; not full mission dump |
| Crypto Chat transcripts | No — not collected by Centurion cloud | Processed on device / Sovereign |

```
App Privacy answers updated in ASC:
Date:
By:
```

## Features intentionally not shipped as unfinished

- Local-only Swarm **formation** UI removed; join / invite via Connect another Sovereign remains.
- Digest preference is **in-app attention** only — no OS push / local notification entitlement in this build.

## Privacy manifest

- [`PrivacyInfo.xcprivacy`](PrivacyInfo.xcprivacy) declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason **CA92.1** (same-app access).
- Tracking: false. Collected-data array left empty in the manifest; complete App Store Connect App Privacy answers to match Adrian optional help (see AppStoreDescription).

## Screenshots

Required device sizes must be real PNGs under [`AppStore/`](AppStore/) (not only `AppStoreScreenshots.html`). See [`AppStore/SCREENSHOTS.md`](AppStore/SCREENSHOTS.md).

## Device smoke (pre-submit)

See [`DEVICE_SMOKE.md`](DEVICE_SMOKE.md). TestFlight What to Test: [`TestFlightWhatToTest.md`](TestFlightWhatToTest.md).
