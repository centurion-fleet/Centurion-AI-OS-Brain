# App Store screenshots & icon

## Apps list icon

After a processed build is **selected** on version **5.3.0** and **Saved**, ASC copies the 1024 marketing icon from the binary. Hard-refresh Apps if the list lags the version page.

## App Store icon (1024×1024)

Source: [`../Assets.xcassets/AppIcon.appiconset/`](../Assets.xcassets/AppIcon.appiconset/)  
Export: [`AppStoreIcon-1024.png`](AppStoreIcon-1024.png) (RGB, no alpha, full-bleed).

## Required captures (iPhone 6.5")

Build **59+** is **iPhone-only**. App Store Connect requires iPhone 6.5" screenshots only — not 13-inch iPad — once that binary is selected on the version.

- **iPhone 6.5"** — **1284 × 2778** (1242 × 2688 also accepted)
- Do not upload 1290 × 2796 (6.9") unless Media Manager shows a 6.9-inch slot.
- iPad 13" PNGs in this folder are leftover from the Universal **54** upload; they are unused after the iPhone-only binary is selected.

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

iPad screenshots are not required for iPhone-only build **59+**.

## Status

- [ ] Build **59** selected on the iOS version
- [ ] 6.5" PNGs uploaded (1284×2778)
- [ ] 6.9" PNGs in `AppStore/` when Media Manager shows that slot
- [ ] Listing preview reviewed (language: Focus / Missions, not Home / Plans)
