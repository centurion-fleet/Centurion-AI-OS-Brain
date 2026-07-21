# CenturionAI Remote (iOS)

**Sovereign Remote** — private iPhone companion to your Centurion Sovereign brain.

**Status:** Centurion **v5.0.1** (marketing). TestFlight build number comes from `CURRENT_PROJECT_VERSION` in [`CenturionApp/project.yml`](CenturionApp/project.yml).

## Security Architecture

```
iPhone (SwiftUI) ←→ Encrypted Tunnel ←→ Centurion Sovereign (Desktop / brain)
                        │
              ┌─────────┴──────────┐
              │  X25519 Key Exchange │
              │  XSalsa20-Poly1305   │
              │  Perfect Forward     │
              │  Secrecy             │
              └────────────────────┘
```

Crypto Chat stays between your iPhone and your Sovereign — not Centurion cloud storage.

## Connection Methods

### LAN (Home)
- mDNS/Bonjour discovery (`_centurion._tcp`)
- Direct TCP connection over local network

### Tailscale (Remote)
- WireGuard tunnel back to home network
- Same app-layer encryption on top of the tunnel

## Building

```bash
cd ios/CenturionApp
xcodegen generate   # regenerates CenturionApp.xcodeproj from project.yml
open CenturionApp.xcodeproj
```

Release / TestFlight:

```bash
# Archive in Xcode (Product → Archive), or:
xcodebuild -scheme CenturionApp -destination 'generic/platform=iOS' \
  -configuration Release archive \
  -archivePath build/TestFlight/CenturionApp-5.0.1-<BUILD>.xcarchive

xcodebuild -exportArchive \
  -archivePath build/TestFlight/CenturionApp-5.0.1-<BUILD>.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/TestFlight/export
```

Upload with Organizer or `ExportOptionsUpload.plist` (`destination: upload`).

## Submission

- [`CenturionApp/DEVICE_SMOKE.md`](CenturionApp/DEVICE_SMOKE.md) — device smoke before TestFlight
- [`CenturionApp/TestFlightWhatToTest.md`](CenturionApp/TestFlightWhatToTest.md) — TF notes for build 13
- [`CenturionApp/SUBMISSION_CHECKLIST.md`](CenturionApp/SUBMISSION_CHECKLIST.md) — encryption + App Privacy
- [`CenturionApp/AppStoreDescription.md`](CenturionApp/AppStoreDescription.md) — listing copy
- [`CenturionApp/AppStore/SCREENSHOTS.md`](CenturionApp/AppStore/SCREENSHOTS.md) — screenshot capture guide

## Project layout

```
ios/CenturionApp/
├── CenturionApp.swift
├── ContentView.swift          # Chat / Home / You tabs
├── project.yml                # xcodegen + MARKETING_VERSION / build
├── Views/                     # Chat, Home, You, Memory Horizon, …
├── Services/                  # ConnectionManager, MessageService, stores
├── Models/
├── Crypto/
└── Utils/
```
