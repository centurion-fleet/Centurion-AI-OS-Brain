# App Store screenshots & icon

## App Store icon (1024×1024)

Source of truth: [`../Assets.xcassets/AppIcon.appiconset/`](../Assets.xcassets/AppIcon.appiconset/)  
Export for Media Manager: [`AppStoreIcon-1024.png`](AppStoreIcon-1024.png) (RGB, no alpha, full-bleed square).

If App Store Connect still shows the grid placeholder next to the app name:

1. Open **App Information** (or version **5.0.1** → scroll to App Icon if shown).
2. Upload `AppStoreIcon-1024.png`.
3. Or attach a processed build that includes the marketing icon (build **14+**), then refresh.

App Store Connect requires real device screenshots. The HTML mockup [`../AppStoreScreenshots.html`](../AppStoreScreenshots.html) is **design reference only** — do not upload it.

## Required captures (iPhone)

Capture on a physical device or Simulator at **6.7"** (iPhone 15 Pro Max / 16 Pro Max) and **6.1"** if ASC still asks for a second size:

1. **Home / Pulse** — calm Live surface with brand visible  
2. **Crypto Chat** — conversation with Sovereign (no secrets)  
3. **You → Memory Horizon** — three horizon cards with fill bars  
4. **You → Mission** or Soul — life purpose / personality (one screen)  
5. **Link / Privacy** — private connection or Privacy & Trust reassurance  

Save as:

```
AppStore/iphone-67-01-home.png
AppStore/iphone-67-02-chat.png
AppStore/iphone-67-03-memory-horizon.png
AppStore/iphone-67-04-mission-or-soul.png
AppStore/iphone-67-05-privacy.png
```

Optional iPad if `TARGETED_DEVICE_FAMILY` stays `1,2`.

## Status

- [ ] Screenshots captured for 6.7"
- [ ] Uploaded to App Store Connect
- [ ] Listing preview reviewed on phone
