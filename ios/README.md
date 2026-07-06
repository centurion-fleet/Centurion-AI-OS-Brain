# Centurion iOS App

Secure, private iPhone connection to your Centurion OS Desktop.

## Security Architecture

```
iPhone (SwiftUI) ←→ Encrypted Tunnel ←→ Centurion OS Desktop (Linux)
                        │
              ┌─────────┴──────────┐
              │  X25519 Key Exchange │
              │  XSalsa20-Poly1305   │
              │  Perfect Forward     │
              │  Secrecy             │
              └────────────────────┘
```

**No cloud. No servers. No metadata.**

## Connection Methods

### LAN (Home)
- mDNS/Bonjour discovery (`_centurion._tcp`)
- Direct TCP connection over local network
- Zero internet required
- Physically unreachable from outside

### Tailscale (Remote)
- WireGuard tunnel back to home network
- Same encryption on top of the tunnel
- No open ports, no VPN configuration

## Dependencies

- **libsodium** (via swift-sodium) — X25519 + XSalsa20-Poly1305
- **Tailscale SDK** — secure remote tunnel

## Building

Open in Xcode 15+:
```bash
open ios/CenturionApp.xcodeproj
```

Or build via SPM:
```bash
cd ios/CenturionApp
xcodebuild -scheme CenturionApp -destination 'platform=iOS'
```

## Project Structure

```
ios/CenturionApp/
├── CenturionApp.swift        # App entry point
├── ContentView.swift         # Main tab view
├── Info.plist                # Bonjour + networking permissions
├── Package.swift             # SPM dependencies
├── Models/
│   ├── Message.swift         # Message + roles
│   └── Conversation.swift    # Conversations + CenturionDevice
├── Views/
│   ├── ChatView.swift        # Chat interface
│   ├── ConversationListView.swift  # Conversation list
│   ├── ConnectionView.swift  # Device discovery + connection
│   └── SettingsView.swift    # Settings + key management
├── Services/
│   ├── ConnectionManager.swift  # Network + crypto orchestration
│   └── MessageService.swift     # Message lifecycle
├── Crypto/
│   ├── KeyAgreement.swift    # X25519 key exchange
│   └── SecureChannel.swift   # Encrypted message channel
└── Utils/
    └── BonjourDiscoverer.swift  # mDNS device discovery
```

## Status

**Pre-release (0.1.0).** The architecture and core crypto are implemented.
Next: Xcode project file generation, actual build testing on device.
