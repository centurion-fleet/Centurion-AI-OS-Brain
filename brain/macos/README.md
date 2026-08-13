# macOS Brain (roadmap)

SwiftUI host for **Sovereign AI Brain** on Mac (MacBook Pro and desktop Macs).

Not shipping yet — scaffold only. See the Mac Brain effort plan:

- Bundle Python Centurion AI OS + `centurion-remote` (from [`../service/`](../service/))
- Missions via [`../web-dashboard/`](../web-dashboard/)
- Pair Centurion Remote over Crypto Chat `:9119`
- Get Brain → Download for Mac (signed `.app` / notarized DMG)

Layout (future):

```text
macos/
  CenturionBrain/   # Xcode / xcodegen SwiftUI app
  packaging/        # notarize, DMG, launchd plist
```

Until this ships, Mac users run Centurion AI OS (CLI) from the repo root installers;
there is no Get Brain Mac package yet.
