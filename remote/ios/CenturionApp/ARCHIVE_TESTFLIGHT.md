# Archive / TestFlight — Sovereign AI Remote 5.2.137

Engineering prep for App Store Connect upload (operator runs Archive on Mac).

## Preconditions

- Xcode with signing team `J6DY26ZGL4` (or your ASC team)
- Marketing version **5.2.137**, build **30+** (QR pairing + camera string)
- For Away review: Brain with **Chat from anywhere** enabled (Centurion relay) — not DIY `EXPOSE_9119`

## Generate + Archive

```bash
cd remote/ios/CenturionApp
xcodegen generate
open CenturionApp.xcodeproj
```

In Xcode:

1. Scheme **CenturionApp** → Any iOS Device (or connected iPhone)
2. Product → Archive
3. Organizer → Distribute App → App Store Connect → Upload
4. Wait for processing; add build to TestFlight internal group
5. Install on physical iPhone; run [`DEVICE_SMOKE.md`](DEVICE_SMOKE.md) on **cellular** (Scan QR)

## Review window notes (paste into ASC)

Provide a temporary public/tunnel hostname + pairing QR (or connection string)
so App Review can link away-from-home. Camera is used only to scan that QR;
paste fallback is under Connect → Paste code instead.
