# App Store screenshots & icon

## Apps list icon

After a processed build is **selected** on version **5.0.2** and **Saved**, ASC copies the 1024 marketing icon from the binary. Hard-refresh Apps if the list lags the version page.

## App Store icon (1024×1024)

Source: [`../Assets.xcassets/AppIcon.appiconset/`](../Assets.xcassets/AppIcon.appiconset/)  
Export: [`AppStoreIcon-1024.png`](AppStoreIcon-1024.png) (RGB, no alpha, full-bleed).

## Required captures (iPhone 6.7")

Capture on device or Simulator (iPhone 15/16 Pro Max). Do **not** upload HTML mockups.

| File | Screen |
|------|--------|
| `iphone-67-01-home.png` | Home / Pulse — calm Live surface with brand |
| `iphone-67-02-chat.png` | Crypto Chat — conversation with Sovereign (no secrets) |
| `iphone-67-03-memory-horizon.png` | You → Memory Horizon — three cards with fill bars |
| `iphone-67-04-mission-or-soul.png` | You → Mission or Soul |
| `iphone-67-05-privacy.png` | Link / Privacy & Trust |

Optional iPad if `TARGETED_DEVICE_FAMILY` stays `1,2`.

### Capture helper (Simulator)

```bash
# Boot a 6.7" simulator, install Release build, then for each screen:
xcrun simctl io booted screenshot ios/CenturionApp/AppStore/iphone-67-0N-NAME.png
```

## Status

- [ ] Build selected on **iOS 5.0.2** (sphere on build row)
- [ ] Screenshots captured for 6.7" (operator — five PNGs above)
- [ ] Screenshots uploaded to App Store Connect
- [ ] Listing preview reviewed
