# Centurion Desktop — Linux Native Application Design

## Architecture: The Brain and the Conduit

The Linux app is not just another client — **it IS Centurion**. The iPhone app is a conduit — a thin remote interface to the Linux brain.

```
┌─────────────────────────────────────────────────────┐
│                   LINUX (The Brain)                  │
│                                                      │
│  ┌─────────────┐  ┌────────────┐  ┌──────────────┐  │
│  │ Centurion   │  │ Agent      │  │ Model        │  │
│  │ AI OS Core  │──│ Runtime    │──│ Providers    │  │
│  │ (Python)    │  │ (loop,     │  │ (API/local)  │  │
│  │             │  │  tools)    │  │              │  │
│  └─────────────┘  └────────────┘  └──────────────┘  │
│         │                │               │          │
│  ┌──────┴────────────────┴───────────────┴──────┐   │
│  │         Desktop App (Tauri + Rust)            │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────────┐  │   │
│  │  │ Terminal │ │ Dashboard│ │Gateway Admin │  │   │
│  │  │ (pty)    │ │ (health) │ │(Telegram,    │  │   │
│  │  │          │ │          │ │ Discord, etc)│  │   │
│  │  └──────────┘ └──────────┘ └──────────────┘  │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────────┐  │   │
│  │  │ System   │ │ File     │ │ Server       │  │   │
│  │  │ Tray     │ │ Browser  │ │ (WebSocket   │  │   │
│  │  │          │ │          │ │  API)        │  │   │
│  │  └──────────┘ └──────────┘ └──────────────┘  │   │
│  └───────────────────────────────────────────────┘   │
│                         │                             │
│              Secure WebSocket │ mDNS                   │
│                         │                             │
└─────────────────────────┼─────────────────────────────┘
                          │
┌─────────────────────────┼─────────────────────────────┐
│                  iPhone (The Conduit)                   │
│                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────┐  │
│  │ Chat         │  │ Mission      │  │ Security   │  │
│  │ (gateway     │  │ Control      │  │ Hub        │  │
│  │  to Linux)   │  │ (remote)     │  │ (remote)   │  │
│  └──────────────┘  └──────────────┘  └────────────┘  │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────┐  │
│  │ Connection   │  │ Server       │  │ Notif-     │  │
│  │ Manager      │  │ Health       │  │ ications   │  │
│  │ (mDNS + WS)  │  │ (read-only)  │  │ (from cron)│  │
│  └──────────────┘  └──────────────┘  └────────────┘  │
└──────────────────────────────────────────────────────┘
```

---

## Feature Comparison: Linux App vs iPhone App

### The Linux App Has — iPhone Cannot

These are **desktop-native** capabilities that only the Linux app can provide because it IS the host:

| Feature | Why Linux-Only | Priority |
|---------|---------------|----------|
| **Full Terminal (PTY)** | Native process execution, `bash`, `python`, `git`, `ssh`, `docker` — all CLI tools. Real shell, not a sandbox. | 🚀 Critical |
| **Sovereign Core** | The actual agent loop runs here — tool calls, model orchestration, memory, state management. iPhone just talks to it. | 🚀 Critical |
| **File System Access** | Read/write any file on the host. Open projects, edit configs, browse directories. Full access. | 🚀 Critical |
| **Code Execution** | Run scripts, see output, kill processes. True dev environment. | 🚀 Critical |
| **Local LLM Inference** | llama.cpp integration — run models entirely offline on your own hardware (GPU/CPU). No cloud dependency. | 🔥 High |
| **Model Provider Management** | Configure API keys, switch providers, set fallbacks, manage credential pools. | 🔥 High |
| **Gateway Admin** | Start/stop Telegram, Discord, Slack, SMS gateways. Manage connected platforms. | 🔥 High |
| **Skill Manager** | Install, create, edit, delete skills. Full authoring environment. | 🔥 High |
| **Cron Scheduler** | Create, view, pause, edit scheduled jobs. See execution history and output. | 🔥 High |
| **Plugin Management** | Install/uninstall plugins, toggle features. Full extensibility. | 🔥 High |
| **Log Viewer** | Real-time tail of `agent.log`, `errors.log`, `gateway.log`. Filter by level, session, time. | 🔥 High |
| **System Monitoring** | CPU, RAM, GPU, disk, network, uptime — live dashboard. | 🔥 High |
| **Process Management** | View/running services, start/stop/restart. Kill hung processes. | 🔥 High |
| **Profile Management** | Create, switch, edit config profiles. | 🔥 High |
| **Network Diagnostics** | Ping, traceroute, port scan, DNS check, bandwidth test. | 📋 Medium |
| **System Tray** | Minimise to tray. Quick actions: "Quick Chat", "Status Check", "Restart." Status indicator icon (connected/error/online). | 📋 Medium |
| **Desktop Notifications** | Native OS notifications for cron completions, errors, gateway disconnects. | 📋 Medium |
| **SSH/Remote Host Management** | Connect to remote servers, manage remote Centurion installations. | 📋 Medium |
| **Backup & Restore** | Full config/session/memory backup to file. One-click restore. | 📋 Medium |

### The iPhone App Has — Linux Lacks (or needs porting)

These are **mobile-native** features:

| Feature | Why iPhone-Native | Status |
|---------|------------------|--------|
| **Push Notifications** | APNs — wake the phone when Linux has something important | ❌ Missing |
| **Camera/Mic Access** | Photo capture, voice recording for the AI to process | ❌ Missing |
| **Location/GPS** | Location-aware conversations, geofenced automations | ❌ Missing |
| **On-the-Go Access** | Chat from anywhere, not just at your desk | ✅ Has |
| **Touch ID / Face ID** | Biometric auth for sensitive operations | ✅ Has (Security Hub) |

---

## What's MISSING from the iPhone App for Proper Linux ↔ iPhone Communication

This is the critical gap. The iPhone app needs these to be a proper conduit:

### 1. 🔌 Connection Manager (rewrite — current one is fake)

The existing `ConnectionManager` uses a mock local connection. It needs real:

- **mDNS/Bonjour discovery** — scan the local network for Centurion Linux servers. Show a list: `Ships_AI (192.168.1.42)`, `Maximus_Jr (192.168.1.15)`.
- **Manual connection** — enter IP:port manually for remote access (Tailscale, WireGuard, public IP).
- **Connection states**: `disconnected → scanning → found → pairing → connected → authenticated`
- **Secure WebSocket** — encrypted channel to the Linux app's server API.
- **Reconnection** — exponential backoff, auto-reconnect when the phone comes back from sleep.
- **Status indicator** — green dot connected, red disconnected, yellow reconnecting.
- **Latency/ping** — show current round-trip time to the Linux server.

### 2. 🔐 Pairing & Authentication

- **QR code pairing** — Linux app shows a QR code → iPhone scans it → cryptographically paired.
- **Keypair identity** — each device gets a keypair. Messages are signed.
- **Session tokens** — short-lived tokens with refresh.
- **Device management** — Linux app shows "2 connected devices: Adrian's iPhone, Adrian's iPad." Ability to revoke.

### 3. 📡 Real-Time Channel

- **WebSocket** — persistent connection for chat, events, notifications.
- **Message ordering** — causal ordering with lamport timestamps. Messages sent offline queue and replay in order.
- **Heartbeat** — keep-alive every 10s. If Linux doesn't hear a heartbeat for 30s, marks phone offline. If phone doesn't hear heartbeat for 30s, shows "Server unreachable."

### 4. 🔔 Push Notifications (Linux → iPhone)

When the Linux app generates events while the iPhone is in background:

| Event | Notification |
|-------|-------------|
| Cron job completed | "📊 Weekly report generated" |
| System alert | "⚠️ Disk at 92% on Ships_AI" |
| Gateway error | "❌ Telegram gateway disconnected" |
| AI-initiated conversation | "💬 Centurion has a question about your mission" |
| Long task finished | "✅ Code review complete — 3 files reviewed" |

### 5. 🗄️ Session Sync

- Conversations started on iPhone should be accessible on Linux and vice versa.
- Messages typed on iPhone go through the Linux app's agent and the response comes back.
- Full history available on both devices (Linux stores the canonical database; iPhone caches recent conversations).

### 6. 📁 File Transfer

Bi-directional:
- **iPhone → Linux**: Share photos, documents, audio recordings to the AI.
- **Linux → iPhone**: Export files, download generated content, share results.

### 7. 🖥️ Remote Dashboard Views

iPhone should be able to view (read-only, for now):
- **System health**: CPU, RAM, GPU, disk, uptime — live cards.
- **Cron status**: list of scheduled jobs with last-run time and status.
- **Connected gateways**: Telegram ✅, Discord ✅, etc.
- **Active provider**: DeepSeek (100ms), fallback: none.
- **Recent log tail**: last 20 lines of agent.log (tap to expand).
- **Skill list**: installed skills with version.

### 8. ⌨️ Quick Actions

From the iPhone app:
- "Ping server" — latency check
- "Run health check" — Linux runs diagnostics and reports back
- "Restart gateway" — restart Telegram/Discord/etc
- "Quick terminal" — send one shell command and get output
- "Wake up" — if Linux is in sleep/suspend mode

---

## Linux Desktop App UI Design

### Shell: The Primary Interface

Unlike iPhone which is chat-first, the Linux app should be **shell + chat**. The primary mode is a terminal emulator + AI chat side-by-side:

```
┌──────────────────────────────────────────────────────────┐
│  ┌─────────┬──────────┬──────────┬──────────┬──────────┐ │
│  │  Chat   │ Terminal │Dashboard │ Gateways │ Settings │ │
│  ├─────────┴──────────┴──────────┴──────────┴──────────┤ │
│  │                                                       │ │
│  │  ┌────────────────────┐  ┌────────────────────────┐  │ │
│  │  │                    │  │                        │  │ │
│  │  │   AI Chat Panel    │  │    Terminal (PTY)      │  │ │
│  │  │                    │  │                        │  │ │
│  │  │  ┌──────────────┐  │  │  $ git status          │  │ │
│  │  │  │ Messages     │  │  │  On branch main        │  │ │
│  │  │  │              │  │  │  $ python test.py      │  │ │
│  │  │  │ ┌──────────┐ │  │  │  ✓ All tests pass     │  │ │
│  │  │  │ │User msg  │ │  │  │  $                     │  │ │
│  │  │  │ └──────────┘ │  │  │                        │  │ │
│  │  │  │ ┌──────────┐ │  │  │                        │  │ │
│  │  │  │ │AI resp   │ │  │  │                        │  │ │
│  │  │  │ └──────────┘ │  │  │                        │  │ │
│  │  │  └──────────────┘  │  │                        │  │ │
│  │  │                    │  │                        │  │ │
│  │  │  ┌────────────────┐│  │                        │  │ │
│  │  │  │ Message...     │  │  │                        │  │ │
│  │  │  └────────────────┘│  │                        │  │ │
│  │  └────────────────────┘  └────────────────────────┘  │
│  │                                                       │
│  └───────────────────────────────────────────────────────┘
│  [System Tray] [CPU: 12%] [RAM: 4.2/16G] [GPU: 45%]    │
└──────────────────────────────────────────────────────────┘
```

### Tab-by-Tab Design

#### 1. Chat Tab
- Main conversation interface with the AI
- **LHS**: Conversation history sidebar (like the iOS app's tray)
- **RHS**: Active conversation + input bar
- Can accept: text, code blocks (syntax highlighted), file attachments (drag-and-drop)
- AI responses include: text, code blocks, file previews, images
- Split-view toggle: chat + terminal side-by-side

#### 2. Terminal Tab
- Full PTY terminal emulator (xterm-256color)
- Supports: bash, zsh, fish, python REPL, any CLI tool
- The AI can see terminal output and suggest/execute commands
- "AI-assisted mode" — AI watches your terminal and offers help
- Split: terminal output on top, AI suggestions on bottom
- Process viewer: see running processes, kill signals, resource usage

#### 3. Dashboard Tab
- **System Health** cards — CPU, RAM, GPU, Disk, Network, Uptime
- **Active Services** — Gateway (Telegram ✅), Provider (DeepSeek, 100ms), Cron (scheduled: 3)
- **Recent Activity** — log entries: "08:42:15 — cron 'daily-report' completed ✓", "08:30:00 — gateway connected"
- **Quick Actions** — "Run Diagnostics", "Restart Gateway", "Clear Cache", "Check for Updates"
- **Memory/Context** — current context size, token counts, active sessions

#### 4. Gateways Tab
- List of connected platforms: Telegram, Discord, Slack, SMS, Email, Webhook
- Per-platform: status (connected/disconnected/error), message count, last activity
- Toggle each gateway on/off
- Configuration per platform (bot token, webhook URL, etc.)
- Connection test button

#### 5. Settings Tab
- **Provider Settings**: API keys, model selection, fallback chain, base URLs
- **Skills**: installed skills list, enable/disable, install new (from hub or URL), skill authoring
- **Cron**: job table, create/edit/delete jobs, execution history
- **Plugins**: plugin list, enable/disable, configure
- **Profiles**: profile switcher, profile config editor
- **Network**: port settings, TLS/SSL, allowed hosts
- **Updates**: check for updates, changelog
- **Backup**: export/import config, session data, memory

### System Tray
- Centurion icon (amber globe)
- Right-click menu:
  - "Open Centurion" — focus main window
  - "Quick Chat" — small popup window to type a message
  - "Status" — GPU temp, last activity, connected devices
  - "Restart Agent" — quick restart
  - "Quit" — shutdown cleanly

### Server Mode (Headless)
- Run without the desktop UI — just the WebSocket server + system tray icon
- All management done via iPhone app or web dashboard
- Auto-start on boot (systemd service)

---

## Technology Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| **Desktop framework** | Tauri 2 (Rust + WebView) | Native Linux binary, small (<10MB), system tray, notifications, file system |
| **Frontend** | React + TypeScript + Tailwind | Familiar, fast iteration, proven pattern |
| **Terminal emulator** | xterm.js + node-pty | True terminal in the webview, PTY passthrough |
| **IPC between UI and Sovereign** | Unix socket + JSON-RPC | Already exists in the codebase (`tui_gateway/`) |
| **Server mode** | Rust HTTP/WS server (actix-web or axum) | Accept incoming connections from iPhone |
| **mDNS discovery** | Rust (libmdns) | Auto-discovery on local network |
| **Encryption** | TLS 1.3 + ed25519 keypairs | Secure channel between Linux ↔ iPhone |
| **Packaging** | `.deb` + `.rpm` + AppImage | Mainstream Linux distribution |

---

## Missing iPhone Features — Implementation Priority

For the Linux + iPhone to talk properly, these are the iPhone app gaps to fill, in priority order:

| Priority | Feature | Why First |
|----------|---------|-----------|
| P0 | **Real ConnectionManager** (mDNS + WebSocket) | Without this, they can't talk at all |
| P0 | **Authentication/Pairing** (QR code + keys) | Without this, the channel is insecure |
| P0 | **Secure WebSocket chat** | Current chat is local-only mock data |
| P1 | **Server Health View** (read-only dashboard) | Immediate utility — "is my server OK?" |
| P1 | **Reconnection logic** | iPhone goes to sleep, needs to reconnect |
| P2 | **Push notifications** (via APNs proxy) | Background notifications from cron/tasks |
| P2 | **File transfer** (send/receive via websocket) | Share photos with AI, receive generated files |
| P2 | **Cron status view** | See and monitor scheduled jobs |
| P3 | **Quick actions** (ping, restart, diags) | Convenience |
| P3 | **Session sync** (message history from Linux) | Full conversation continuity |
