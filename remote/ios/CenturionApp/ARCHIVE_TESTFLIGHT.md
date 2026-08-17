# Archive / TestFlight — Sovereign AI Remote 5.3.0

## Version (do not ship under 5.0.1)

- Marketing / ASC iOS App Version: **5.3.0**
- Build: **45**
- Bundle ID: `com.centurion.ios` (adamId `6789119835`)

If App Store Connect still shows an old train (e.g. **5.0.1** / **5.2.x**), create a new
iOS version **5.3.0** under App Store → iOS App → (+) before distributing,
or select the **5.3.0** build under TestFlight → iOS Builds after processing.

## Generate + Archive

```bash
cd remote/ios/CenturionApp
xcodegen generate
open CenturionApp.xcodeproj
```

Confirm Xcode → Target CenturionApp → General → Version **5.3.0**, Build **45**.

Then: Product → Archive → Distribute App → App Store Connect → Upload.

## Review pairing window

Brain online, QR on home Wi‑Fi. Enable Chat from anywhere only if reviewers are off-LAN **and** Away DoD is green.
