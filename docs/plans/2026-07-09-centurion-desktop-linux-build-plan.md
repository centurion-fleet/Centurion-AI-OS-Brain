# Centurion Desktop (Linux) — Native Application Build Plan

> **Version lockstep:** This app is released **in lockstep with Centurion AI OS** and the **CenturionAI Remote** (iPhone app). When a new Centurion version ships (e.g. **Centurion v3 — Mission Horizon** / v3.0.0), all three — the OS, the iPhone app, and the desktop app — carry the same version number and release at the same time.

> **Architecture:** The Linux desktop app IS Centurion. It runs the full Centurion AI OS Python core — agent loop, tools, memory, model providers, cron, gateways — and wraps it in a native Tauri 2 desktop shell with terminal emulator, dashboard, and a WebSocket server for the CenturionAI Remote (iPhone) app to connect to.

**Tech stack:** Tauri 2 (Rust + WebView), React + TypeScript + Tailwind, xterm.js + node-pty, Python core via Unix socket IPC (existing `tui_gateway/`).

**Design doc:** `ios/CenturionApp/Centurion-Desktop-Design.md`
**iPhone counterpart:** `docs/plans/2026-07-09-centurionai-remote-ios-architecture.md`

---

## Phase 0: Foundation — Tauri Shell + IPC Bridge

### Task 0.1: Tauri 2 Project Scaffold

- Initialize Tauri 2 project in `desktop/` directory at repo root
- React + TypeScript + Tailwind frontend
- Rust backend with system tray, notifications, window management
- Project structure:
  ```
  desktop/
  ├── src/              # React frontend
  │   ├── App.tsx
  │   ├── main.tsx
  │   ├── components/
  │   ├── pages/
  │   └── hooks/
  ├── src-tauri/        # Rust backend
  │   ├── src/
  │   │   ├── main.rs
  │   │   ├── tray.rs
  │   │   ├── server.rs
  │   │   └── ipc.rs
  │   ├── Cargo.toml
  │   └── tauri.conf.json
  ├── package.json
  └── tailwind.config.js
  ```

**Dependencies:** Rust toolchain, Node.js, `create-tauri-app`

### Task 0.2: Python IPC Bridge

- Connect to existing `tui_gateway/` Unix socket (JSON-RPC) from Tauri Rust backend
- Rust ↔ Python bridge: send commands to Centurion AI OS, receive structured responses
- Command set for Phase 0:
  - `ping` — health check, returns latency
  - `get_status` — returns agent status, active provider, uptime
  - `chat(message)` — sends message to AI agent, returns response
  - `get_metrics` — CPU, RAM, GPU, disk usage
- Timeout handling: commands that take >5s get streaming progress updates

**Files to create:**
- `src-tauri/src/ipc.rs` — Unix socket JSON-RPC client
- `src-tauri/src/commands.rs` — Tauri command handlers

### Task 0.3: Window & System Tray

- Main window: 1200x800, remembers position/size
- System tray icon: amber Centurion globe
- Tray menu: Open, Quick Chat (popup), Status, Restart Agent, Quit
- Close to tray (minimise, not quit)

**Files to create:**
- `src-tauri/src/tray.rs` — system tray setup

---

## Phase 1: Chat Tab

### Task 1.1: Chat UI

- Conversation sidebar (LHS): list of conversations, grouped by mission area, searchable
- Active conversation panel (RHS): message bubbles, scroll to bottom on new message
- Input bar: text field + send button, markdown preview, code block formatting
- Messages render: markdown body, syntax-highlighted code blocks, file previews
- AI responses stream token-by-token (Server-Sent Events via WebSocket proxy)

**Files to create:**
- `src/components/chat/ChatPanel.tsx`
- `src/components/chat/ConversationList.tsx`
- `src/components/chat/MessageBubble.tsx`
- `src/components/chat/MessageInput.tsx`
- `src/hooks/useChat.ts`

### Task 1.2: Split-View Mode

- Resizable split pane: Chat | Terminal side-by-side
- Drag-to-resize divider
- Remember split ratio per session

**Files to create:**
- `src/components/layout/SplitView.tsx`

---

## Phase 2: Terminal Tab

### Task 2.1: xterm.js Terminal Emulator

- Full PTY terminal via xterm.js + backend PTY process
- Supports: bash, zsh, fish, python REPL, any CLI tool
- 256-color, Unicode, copy/paste, resizable
- Tab completion, history (shell-native)
- Terminal output is also fed to the AI for context-aware assistance

**Files to create:**
- `src/components/terminal/TerminalPanel.tsx`
- `src-tauri/src/pty.rs` — PTY process management in Rust

### Task 2.2: AI-Assisted Terminal Mode

- Toggle "AI Watch" mode: AI observes terminal output
- AI suggests commands, flags errors, explains output
- User can Accept/Skip/Modify AI suggestions
- Suggested commands are pre-filled, not auto-executed

**Files to create:**
- `src/components/terminal/AIAssistPanel.tsx`

---

## Phase 3: Dashboard Tab

### Task 3.1: System Health Cards

- CPU: usage %, temperature, process count — sparkline graph
- RAM: used/total, percentage bar
- GPU: utilization %, VRAM used/total (NVIDIA via `nvidia-smi`, AMD via `rocm-smi`)
- Disk: used/free per mount, percentage bar
- Network: up/down speed, active connections
- Uptime: days:hh:mm
- Auto-refresh every 3s

**Files to create:**
- `src/components/dashboard/HealthCard.tsx`
- `src/components/dashboard/Sparkline.tsx`
- `src/hooks/useMetrics.ts`

### Task 3.2: Active Services

- Gateway status per platform: Telegram ✅, Discord ❌, etc.
- Provider status: DeepSeek (100ms), fallback: none
- Active cron jobs: scheduled count, last run, next run
- Connected devices: iPhone(s), web clients
- Recent activity log: scrollable, filterable

**Files to create:**
- `src/components/dashboard/ServicesPanel.tsx`
- `src/components/dashboard/ActivityLog.tsx`

### Task 3.3: Quick Actions

- "Run Diagnostics" — health check suite
- "Restart Agent" — graceful restart
- "Clear Context" — clear conversation context
- "Check for Updates" — git pull + version check
- "Backup" — export config + sessions + memory

**Files to create:**
- `src/components/dashboard/QuickActions.tsx`

---

## Phase 4: Server Mode + iPhone Connectivity

### Task 4.1: WebSocket Server in Rust

- Standalone WebSocket server (actix-web or axum) in the Rust backend
- Endpoints:
  - `GET /ws` — WebSocket upgrade for iPhone connection
  - `POST /api/health` — health check for load balancers/proxies
- Message protocol: JSON-RPC over WebSocket
- Per-connection authentication via signed tokens

**Files to create:**
- `src-tauri/src/server.rs` — WebSocket server

### Task 4.2: mDNS Service Advertisement

- Advertise `_centurion._tcp` service on the local network via mDNS
- Service metadata: version, hostname, requires_auth
- Allows iPhone to auto-discover the Linux machine

**Files to create:**
- `src-tauri/src/mdns.rs` — mDNS advertiser (libmdns crate)

### Task 4.3: Pairing API

- `GET /api/pair/qrcode` — returns QR code data (temporary pairing key + server info)
- `POST /api/pair/confirm` — completes pairing, returns session token
- Device registry: connected devices with: device name, last active, public key fingerprint
- `GET /api/devices` — list connected devices
- `DELETE /api/devices/:id` — revoke a device

**Files to create:**
- `src-tauri/src/pairing.rs` — pairing handshake
- `src-tauri/src/auth.rs` — token issuance & verification

---

## Phase 5: Gateways & Settings Tabs

### Task 5.1: Gateways Tab

- List all connected platforms (Telegram, Discord, Slack, SMS, Email)
- Per-platform: status toggle, connection test, last activity, message count
- Configure bot tokens, webhook URLs, channel mappings

**Files to create:**
- `src/components/gateways/GatewayList.tsx`
- `src/components/gateways/GatewayConfig.tsx`

### Task 5.2: Settings Tab

- **Providers:** API key management, model selection, fallback chain, base URLs
- **Skills:** installed skills list, enable/disable, install from hub, author new skills
- **Cron:** job table, create/edit/delete, execution history
- **Plugins:** list, enable/disable
- **Profiles:** switch profiles, edit profile config
- **Network:** server port, TLS, allowed hosts
- **Backup:** export/import settings, sessions, memory

**Files to create:**
- `src/components/settings/ProviderSettings.tsx`
- `src/components/settings/SkillManager.tsx`
- `src/components/settings/CronManager.tsx`
- `src/components/settings/PluginManager.tsx`
- `src/components/settings/ProfileManager.tsx`

---

## Phase 6: Packaging & Distribution

### Task 6.1: Build System

- `scripts/build-desktop.sh` — builds Tauri app + bundles Python runtime
- Output: `.deb` (Debian/Ubuntu), `.rpm` (Fedora/RHEL), AppImage (universal)
- Include Python venv with all Centurion AI OS dependencies bundled
- Systemd service file for background server mode

**Files to create:**
- `scripts/build-desktop.sh`
- `desktop/centos/centurion.service` — systemd unit
- `desktop/centos/centurion.desktop` — desktop entry

### Task 6.2: Auto-Update

- GitHub Releases-based update mechanism
- Check for new version on launch
- Download + apply update without disrupting running agent

---

## Effort Estimate

| Phase | Tasks | Est. Days |
|-------|-------|-----------|
| Phase 0: Tauri shell + IPC | 3 tasks | 4-5 days |
| Phase 1: Chat Tab | 2 tasks | 3-4 days |
| Phase 2: Terminal Tab | 2 tasks | 4-5 days |
| Phase 3: Dashboard Tab | 3 tasks | 3-4 days |
| Phase 4: Server + iPhone Connectivity | 3 tasks | 5-7 days |
| Phase 5: Gateways + Settings | 2 tasks | 4-5 days |
| Phase 6: Packaging | 2 tasks | 2-3 days |
| **Total** | **17 tasks** | **25-33 days** |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                   Tauri 2 Shell (Rust)                    │
│                                                          │
│  ┌────────────┐  ┌────────────┐  ┌──────────────────┐   │
│  │ React UI   │  │ System     │  │ WebSocket Server │   │
│  │ (WebView)  │──│ Tray       │  │ (actix-web)      │───┼──→ iPhone
│  │            │  │ Notif-     │  │  mDNS advertiser  │   │
│  │ Chat │     │  │ ications   │  │  Pairing API      │   │
│  │ Term │     │  │            │  │  Device registry  │   │
│  │ Dash │     │  └────────────┘  └──────────────────┘   │
│  └──────┼─────┘                                          │
│         │ Unix Socket (JSON-RPC)                         │
│  ┌──────┴──────────────────────────────────────────────┐ │
│  │         Centurion AI OS Python Core                  │ │
│  │  ┌─────────┐ ┌────────┐ ┌────────┐ ┌────────────┐  │ │
│  │  │ Agent   │ │ Tools  │ │ Memory │ │ Gateways   │  │ │
│  │  │ Loop    │ │ File   │ │ Store  │ │ Telegram   │  │ │
│  │  │         │ │ Code   │ │        │ │ Discord    │  │ │
│  │  │         │ │ Web    │ │        │ │ etc.       │  │ │
│  │  └─────────┘ └────────┘ └────────┘ └────────────┘  │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## Key Design Decisions

1. **Tauri over Electron:** Tauri produces a ~5MB binary vs Electron's ~150MB. Native system tray, notifications. Widely compatible with Linux distros.
2. **Python core via IPC, not embedded:** The existing Python AI agent runs as a separate process. Tauri communicates via the Unix socket (`tui_gateway/`) that already exists. No need to rewrite the AI in Rust.
3. **xterm.js for terminal:** Proven, battle-tested terminal emulator. Works in a WebView. PTY managed by Rust backend (`portable-pty` crate).
4. **Actix-web for server:** Fast, production-grade HTTP/WS server in Rust. Handles iPhone connections without blocking the UI.
5. **Split-view by default:** Chat + Terminal side-by-side is the killer feature. The AI watches your terminal and helps — that's what makes desktop more powerful than mobile.
