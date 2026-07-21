# App Store screenshots & icon

## Why the Apps list still shows the grid placeholder

Uploading a TestFlight build is **not enough**. App Store Connect only copies the 1024×1024 marketing icon onto the **Apps** list after you:

1. Wait until the build finishes processing (TestFlight → Builds → status ready).
2. Open **Personal Centurion AI Remote** → **iOS 5.0.1** (Prepare for Submission).
3. In the **Build** section, click **+** / **Select a build**, choose the latest build (**18+**), then **Save**.
4. Hard-refresh the Apps list (or sign out/in). The grid placeholder should become the sphere icon.

Until a build is attached to that version and saved, ASC keeps the template grid — even if the IPA contains a perfect icon.

There is **no** separate Media Manager icon upload for modern iOS apps; the icon comes from the binary’s `ios-marketing` 1024 asset.

## App Store icon (1024×1024)

Source of truth: [`../Assets.xcassets/AppIcon.appiconset/`](../Assets.xcassets/AppIcon.appiconset/)  
Export copy: [`AppStoreIcon-1024.png`](AppStoreIcon-1024.png) (RGB, no alpha, full-bleed square — no pre-rounded black corners).

Verify marketing icon is inside an archive before upload:

```bash
APP="build/TestFlight/CenturionApp-5.0.1-18.xcarchive/Products/Applications/CenturionApp.app"
xcrun --sdk iphoneos assetutil --info "$APP/Assets.car" | rg -n 'marketing|1024|AppIcon' | head
```

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

App Store Connect requires real device screenshots. The HTML mockup [`../AppStoreScreenshots.html`](../AppStoreScreenshots.html) is **design reference only** — do not upload it.

## Status

- [ ] Build **18+** processed in TestFlight
- [ ] Build selected on **iOS 5.0.1** and **Saved**
- [ ] Apps list shows sphere icon (not grid)
- [ ] Screenshots captured for 6.7"
- [ ] Screenshots uploaded to App Store Connect
