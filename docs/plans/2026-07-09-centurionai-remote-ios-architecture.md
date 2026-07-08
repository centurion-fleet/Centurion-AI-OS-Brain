# CenturionAI Remote (iOS) — Architecture & Build Plan

> **Version lockstep:** This app is released **in lockstep with Centurion AI OS** and the **Centurion Desktop App**. When a new Centurion version ships (e.g. **Centurion v3 — Mission Horizon** / v3.0.0), all three — the OS, the iPhone app, and the desktop app — carry the same version number and release at the same time.

> **Architecture:** The iPhone app is a **thin client / conduit** to the Linux brain. It does NOT run the AI — it connects to the Centurion AI OS running on the Linux machine (Ships_AI). All chat, tools, memory, and execution happens on Linux; the iPhone displays results and sends input.

**Goal:** Rewrite the iOS app from a local-only mock into a real remote control that discovers, pairs, and securely communicates with the Linux Centurion instance.

**Design doc:** `ios/CenturionApp/Centurion-Desktop-Design.md`

---

## Phase 0: Foundation — Network Discovery & Connection

### Task 0.1: mDNS/Bonjour Service Discovery

- Add `DNSServiceDiscovery` framework (or pure SwiftNIO mDNS) to discover `_centurion._tcp` services on the local network
- Show discovered servers in a list: "Ships_AI (192.168.1.42)", "Maximus_Jr (192.168.1.15)"
- Manual IP:port entry fallback for remote access (Tailscale, WireGuard, public IP)
- Cache last-connected server for auto-reconnect

**Files to create/modify:**
- `Services/ServerDiscovery.swift` — mDNS scanner
- `Models/CenturionServer.swift` — server identity struct
- `Views/ConnectionView.swift` — server picker UI

**Dependencies:** `DNSSD` framework (built-in on iOS) or `swift-nio` for mDNS

### Task 0.2: WebSocket Transport Layer

- Establish persistent WebSocket connection to the Linux app's server API
- Connection states: `disconnected → scanning → found → connecting → connected → authenticated`
- JSON-RPC message format over WebSocket for structured communication
- Heartbeat/ping every 10s, timeout detection at 30s
- Exponential backoff reconnection (1s → 2s → 4s → 8s → max 60s)
- Auto-reconnect when app returns from background

**Files to create:**
- `Services/WebSocketTransport.swift` — WebSocket client with reconnection
- `Services/MessageProtocol.swift` — message framing, serialization

**Dependencies:** `URLSessionWebSocketTask` (built-in, iOS 13+)

### Task 0.3: Cryptographic Pairing & Authentication

- QR code pairing flow: Linux app displays QR → iPhone scans → establishes shared secret via ed25519 key exchange
- Device identity: each iPhone generates a persistent keypair on first launch
- Session tokens: short-lived (1 hour) JWT-like tokens with refresh
- Device management: Linux tracks connected devices, ability to revoke
- All WebSocket messages signed for integrity

**Files to create:**
- `Services/CryptoManager.swift` — key generation, signing, verification
- `Services/PairingService.swift` — QR scanning, handshake protocol
- `Views/PairingView.swift` — camera scanner UI

**Dependencies:** `CryptoKit` (built-in, iOS 13+), `AVFoundation` for QR scanning

---

## Phase 1: Real Chat — Linux-Backed Conversations

### Task 1.1: Replace Mock MessageService with Real Channel

- Current `MessageService` uses local mock data and `seedInitialData()` — delete this pattern
- Messages are sent via WebSocket → Linux AI agent processes → response returned
- Local cache of recent conversations (last 50) for offline reading
- Send queue: messages composed while offline queue locally, send in order on reconnection
- Message ordering: lamport timestamps for causal ordering

**Files to modify:**
- `Services/MessageService.swift` — rewrite to use WebSocket transport

### Task 1.2: Conversation Lifecycle

- Conversations live on the Linux server, not locally
- `findOrCreateConversation(for:)` creates on Linux via RPC
- Conversation list fetched from Linux on connect
- Unread counts tracked server-side, pushed to iPhone

**Files to modify:**
- `Models/Conversation.swift` — add server ID, sync status
- `Services/MessageService.swift` — conversation lifecycle

---

## Phase 2: Remote Dashboard

### Task 2.1: Server Health View

- Read-only dashboard showing:
  - CPU usage (%, graph)
  - RAM used/total
  - GPU utilization + temperature
  - Disk usage
  - Uptime
  - Active gateway status per platform
  - Active provider + latency
  - Active cron jobs + last run
- Data pushed from Linux every 5s via WebSocket or polled on demand
- Tap any metric to expand details

**Files to create:**
- `Views/ServerHealthView.swift` — dashboard cards
- `Services/ServerMonitorService.swift` — health data polling

### Task 2.2: Cron Job Viewer

- List scheduled cron jobs with: name, schedule, last run, next run, status
- Tap to see last execution output
- Run/pause/delete actions sent to Linux via WebSocket

**Files to create:**
- `Views/CronListView.swift`
- `Views/CronDetailView.swift`

### Task 2.3: Log Viewer

- Live tail of `agent.log`, `errors.log`, `gateway.log`
- Filter by level (INFO, WARNING, ERROR)
- Auto-scroll on new entries
- Share/save log excerpt

**Files to create:**
- `Views/LogViewer.swift`
- `Services/LogStreamService.swift`

---

## Phase 3: File & Media Transfer

### Task 3.1: Send Files to Linux

- Pick from photo library, camera, or file picker
- Upload via WebSocket (chunked for large files) to Linux filesystem
- AI can access the file and process it

**Files to create:**
- `Views/FilePickerView.swift`
- `Services/FileTransferService.swift`

### Task 3.2: Receive Files from Linux

- Download generated files (images, documents, code) from Linux
- Save to photo library or files app
- Share sheet integration

---

## Phase 4: Push Notifications

### Task 4.1: Linux → iPhone Notification Channel

- Linux generates notification events for: cron completions, system alerts, gateway errors, AI-initiated messages
- iPhone registers for remote push via APNs
- Centurion Gateway relays push through a small proxy service
- Notification tap opens relevant view in the app

**Files to create:**
- `Services/PushNotificationService.swift`
- `CenturionApp.swift` — register for remote notifications

---

## Effort Estimate

| Phase | Tasks | Est. Days |
|-------|-------|-----------|
| Phase 0: Discovery + Connection + Auth | 3 tasks | 5-7 days |
| Phase 1: Real Chat | 2 tasks | 3-4 days |
| Phase 2: Remote Dashboard | 3 tasks | 4-5 days |
| Phase 3: File Transfer | 2 tasks | 2-3 days |
| Phase 4: Push Notifications | 1 task | 2-3 days |
| **Total** | **11 tasks** | **16-22 days** |

---

## Dependencies

- **Linux side:** The Tauri desktop app must be running its WebSocket server API (`server mode`). The server API exists conceptually but needs to be built (see Linux Desktop Build Plan).
- **No external services:** Discovery uses mDNS (local network), transport uses WebSocket (direct encrypted channel), auth uses CryptoKit (on-device). No cloud dependency.
