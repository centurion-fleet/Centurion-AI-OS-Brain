# Archive / TestFlight — Sovereign AI Remote 5.1.0

Engineering prep for App Store Connect upload (operator runs Archive on Mac).

## Preconditions

- Xcode with signing team `J6DY26ZGL4` (or your ASC team)
- Marketing version **5.1.0**, build **28+** (QR pairing + camera string)
- Brain reachable away-from-home (see `brain/linux/docs/EXPOSE_9119.md`) for review notes

## Generate + Archive

```bash
cd ios/CenturionApp
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
