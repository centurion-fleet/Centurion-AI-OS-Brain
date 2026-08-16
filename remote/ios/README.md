# CenturionAI Remote (iOS)

**Sovereign Remote** — private iPhone companion to your Centurion Sovereign brain.

**Status:** Centurion **v5.2.152** (marketing). TestFlight build number comes from `CURRENT_PROJECT_VERSION` in [`CenturionApp/project.yml`](CenturionApp/project.yml) (build **44**).

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

### Home Wi‑Fi pairing (required once)
- On your Centurion, show the pairing QR (desktop **Link iPhone** / Unbox).
- Scan with CenturionAI Remote while on the same home Wi‑Fi (paste `token:…@lan-host:9119` remains a fallback).
- First link binds this iPhone’s fingerprint; later launches reconnect automatically.

### Chat from anywhere (customer Away path)
- Enable **Chat from anywhere** on the Brain (and You → Anywhere on the phone).
- Both Brain and phone dial **out** to Centurion cloud (Vercel control + Supabase Realtime). No home IP, no port-forward, no DIY expose of TCP 9119.
- Home Wi‑Fi Crypto Chat stays preferred when both are on LAN (faster, most private for transit).
- See [`brain/linux/docs/REMOTE_RELAY.md`](../../brain/linux/docs/REMOTE_RELAY.md).

### Same Wi‑Fi (bonus)
- Optional discovery on the local network (`_centurion._tcp`)

### Tailscale / DIY `:9119` (power-user only)
- Still supported for labs; **not** the App Store Away story. See [`brain/linux/docs/EXPOSE_9119.md`](../../brain/linux/docs/EXPOSE_9119.md).

## Building

```bash
cd remote/ios/CenturionApp
xcodegen generate   # regenerates CenturionApp.xcodeproj from project.yml
open CenturionApp.xcodeproj
```

Release / TestFlight:

```bash
# Archive in Xcode (Product → Archive), or:
xcodebuild -scheme CenturionApp -destination 'generic/platform=iOS' \
  -configuration Release archive
```
