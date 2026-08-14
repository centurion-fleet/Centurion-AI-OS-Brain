# Archive / TestFlight — Sovereign AI Remote 5.2.145

## Version (do not ship under 5.0.1)

- Marketing / ASC iOS App Version: **5.2.145**
- Build: **38**
- Bundle ID: `com.centurion.ios` (adamId `6789119835`)

If App Store Connect still shows an old train (e.g. **5.0.1**), create a new
iOS version **5.2.145** under App Store → iOS App → (+) before distributing,
or select the **5.2.145** build under TestFlight → iOS Builds after processing.

## Generate + Archive

```bash
cd remote/ios/CenturionApp
xcodegen generate
open CenturionApp.xcodeproj
```

Confirm Xcode → Target CenturionApp → General → Version **5.2.145**, Build **38**.

Then: Product → Archive → Distribute App → App Store Connect → Upload.
