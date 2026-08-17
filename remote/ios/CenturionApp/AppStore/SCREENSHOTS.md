# App Store screenshots & icon

## Apps list icon

After a processed build is **selected** on version **5.3.0** and **Saved**, ASC copies the 1024 marketing icon from the binary. Hard-refresh Apps if the list lags the version page.

## App Store icon (1024×1024)

Source: [`../Assets.xcassets/AppIcon.appiconset/`](../Assets.xcassets/AppIcon.appiconset/)  
Export: [`AppStoreIcon-1024.png`](AppStoreIcon-1024.png) (RGB, no alpha, full-bleed).

## Required captures (iPhone 6.5")

App Store Connect for this listing currently accepts **6.5-inch** portrait sizes only:

- **1284 × 2778** (use this set)
- **1242 × 2688** (older 6.5")

Do not upload 1290 × 2796 (6.9") unless Media Manager shows a 6.9-inch slot.

| File | Size | Screen |
|------|------|--------|
| `iphone-65-01-focus.png` | 1284×2778 | Focus — Missions pill |
| `iphone-65-02-chat.png` | 1284×2778 | Crypto Chat |
| `iphone-65-03-memory-horizon.png` | 1284×2778 | Memory Horizon |
| `iphone-65-04-mission.png` | 1284×2778 | Life Mission |
| `iphone-65-05-connect.png` | 1284×2778 | Connect — Scan QR |

```bash
SIZE=6.5 bash remote/ios/CenturionApp/AppStore/export-screenshots.sh
```

Preview the storyboard in a browser: `remote/ios/CenturionApp/AppStoreScreenshots.html`.

### Device capture (optional, closer to review)

If App Review wants pixel-identical chrome, capture on iPhone 15/16 Pro Max (or Simulator) from build **45** / **5.3.0**:

```bash
xcrun simctl io booted screenshot remote/ios/CenturionApp/AppStore/iphone-69-0N-NAME.png
```

Do **not** upload HTML. Upload the PNGs. Do **not** upload `RoutingAppCoverage.geojson` — this is not a routing app.

iPad screenshots are not required (iPhone, portrait).

## Status

- [ ] Build selected on **iOS 5.3.0** (build **45**)
- [ ] 6.5" PNGs generated (or recaptured from device)
- [ ] 6.9" PNGs in `AppStore/` when Media Manager shows that slot
- [ ] Screenshots uploaded to App Store Connect Media Manager (6.5-inch, 1284×2778)
- [ ] Listing preview reviewed (language: Focus / Missions, not Home / Plans)
