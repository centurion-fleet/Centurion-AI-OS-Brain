# Centurion Desktop App — Design Guide

## Architectural Principles (from the iOS Mission Chat Redesign)

The Linux native desktop app (Tauri) must carry forward the same philosophical foundation as the iOS app. This document captures the exact patterns to replicate.

---

## 1. Single Message Store

```rust
// Rust backend state — one source of truth for ALL messages
struct MessageStore {
    all_messages: Vec<Message>,
    conversations: Vec<Conversation>,
}

struct Message {
    id: Uuid,
    conversation_id: Uuid,
    content: String,
    role: MessageRole,  // User | Centurion | System
    timestamp: DateTime<Utc>,
}

struct Conversation {
    id: Uuid,
    context: ConversationContext,
    last_active: DateTime<Utc>,
}

enum ConversationContext {
    Program { id: Uuid, name: String },
    Target { id: Uuid, name: String, program_name: String },
    Task { id: Uuid, name: String, target_name: String, program_name: String },
    Standalone { title: String },
}
```

**Hard rule:** There is ONE message list. Every message from every entry point goes here.

---

## 2. Three Entry Points, One Stream

| Entry Point | Creates Context | Appears In |
|---|---|---|
| 💬 on a Program card | `.program` | Global stream + conversation |
| 💬 on a Target row | `.target` | Global stream + conversation |
| 💬 on a Task inline | `.task` | Global stream + conversation |
| Chat tab input (no context) | `.standalone` | Global stream |
| Quick-thought FAB | `.standalone` | Global stream |

All messages flow into the same chronological stream. Every message carries its context badge.

---

## 3. Two View Modes

### Stream Mode (Chat tab, no conversation selected)

```
┌─────────────────────────────────────┐
│  ──────── July 8, 2026 ────────     │
│                                     │
│  🎯 Q3 Go-to-Market                 │
│  Human: How's the launch looking?   │
│  ● Centurion: Tracking well...      │
│                                     │
│  🎯 Q3 > Partner Onboarding         │
│  ● Centurion: I've drafted the kit  │
│                                     │
│  ──────── July 7, 2026 ────────     │
│                                     │
│  💬 Morning Briefing                │
│  Human: What's on today?            │
│  ● Centurion: Three priorities...   │
└─────────────────────────────────────┘
```

Each message shows:
- Context badge (icon + mission path) — colored by level
- Author avatar (person for human, amber dot for Centurion)
- Message content
- Spring entrance animation

### Context Mode (conversation selected)

```
┌─────────────────────────────────────┐
│  Q3 Go-to-Market > Partner Onboard  │
│                                     │
│  Human: What's the status?          │
│                                     │
│  ● Centurion: Currently backlogged. │
│    Dependencies: legal review, API  │
│    docs. I've drafted the kit.      │
│                                     │
│  Human: Yes, let's move this along. │
│                                     │
│  ─────────────────────────────────  │
│  Message about Partner Onboarding…  │
└─────────────────────────────────────┘
```

Shows:
- Context path header at top
- No badges on individual messages (context is known)
- Input bar with contextual placeholder

---

## 4. No Separate Comment System

**The critical rule:** There is no `Comment` struct, no `CommentSheet`, no separate comment API. Comments ARE messages. The same `Message` struct, the same `MessageStore`, the same chronological stream.

Old approach (iOS before redesign):
```
MissionProgram.comments: [MissionComment]   ← separate data model
MissionCommentSheet                         ← separate UI
```

New approach:
```
MessageService.allMessages                  ← single data model
ChatView (context mode)                     ← single UI
```

---

## 5. Conversation Grouping in the Side Panel

The conversations panel (☰) groups by mission area, not by date:

```
🎯 ACTIVE MISSIONS
   Q3 Go-to-Market
   Partner Onboarding
   Content Strategy

💬 CHATS
   Morning Briefing
   Pipeline Review
   Quick Thought
```

Each row shows: icon + title + context path (for mission convs) + last message preview + relative time.

---

## 6. The 💬 Pattern (Visual Affordance)

Every mission element that can be chatted about must have a 💬 button:

| Element | Button Style | Location |
|---|---|---|
| Program | Amber capsule with message icon | Right side of Program card |
| Target | Amber capsule with message icon | Right side of Target row |
| Task | Amber capsule with message icon | Right side of Task row |

Implementation pattern:
```rust
// Click handler pattern
fn on_chat_button(context: ConversationContext) {
    let conversation = message_store.find_or_create(context);
    open_chat_sheet(conversation);
}
```

---

## 7. Context Chat FAB

A floating action button (message icon, accent colour, shadow) appears on ALL tabs:

- Position: bottom-right, above the tab bar
- Tap: opens lightweight chat sheet (280pt, drag dismiss)
- Context header shows which tab the user was on ("From: Mission Control")
- Send creates a standalone conversation in the unified stream

---

## 8. Vital Statistic North Star

The mission dashboard always shows:
- The human's life mission statement
- The vital statistic (one number that matters)
- Progress ring

This is the top of Mission Control. Everything else is subordinate.

---

## 9. Sovereign Remote

Contextual thoughts from the Sovereign appear in Mission Control — not just reactive answers:

- Progress updates ("Revenue at 74% of quarterly target")
- Alerts ("Content Strategy is blocked — awaiting feedback for 8 days")
- Suggestions ("I suggest we reprioritise Partner Onboarding")
- Insights ("Cashflow projection updated — next 30 days look stable")

---

## 10. Platform-Specific Considerations for Tauri

### State Management
- Use Tauri's state management (not Redux) for the message store
- Persist messages to SQLite via `rusqlite` or `sqlx`
- Conversation contexts derive from the mission hierarchy data

### IPC Pattern
```rust
// Commands exposed to the frontend
#[tauri::command]
fn send_message(context: ConversationContext, text: String) -> Message { ... }

#[tauri::command]
fn get_stream() -> Vec<Message> { ... }

#[tauri::command]
fn get_conversations() -> Vec<Conversation> { ... }

#[tauri::command]
fn find_or_create_conversation(context: ConversationContext) -> Conversation { ... }
```

### Frontend (WebView)
- React with TypeScript — use the same component hierarchy as SwiftUI
- CSS spring animations (cubic-bezier matching the iOS Motion enum)
- No emoji text — use Lucide icons or SVG indicators
- Flat frosted glass chrome via `backdrop-filter: blur(20px)`

### Crypto
- Use the same X25519 + XSalsa20-Poly1305 via `libsodium` Rust bindings (`sodiumoxide` or `libsodium-sys`)
- Wire protocol identical to iOS: 24-byte nonce prepended to ciphertext, hex-encoded in JSON
- Bonjour advertising via `zeroconf` Python module already in the backend

---

## Appendix: Key Differences from Conventional Design

| Convention | Centurion Approach |
|---|---|
| Chat is a separate feature | Chat IS the interface — every interaction is a message |
| Comments are a separate UI | Comments are just messages in the unified stream |
| PM tools have their own chat | PM elements ARE chat topics with 💬 affordance |
| Conversations sorted by recency | Conversations grouped by mission context |
| Task status is checkbox | Task status is three amber dots (Things 3 inspired) |
| Notifications per app | One stream — the human's complete dialogue with Centurion |
