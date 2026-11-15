# The client contract — frozen at Gate 0

Everything a Centurion client talks to lives on the customer's own Brain. The
web Desk, the desktop shells, Android and the iPhone app all speak this. If a
shape changes here, it changes in one document first.

**Base:** `http://<brain>:18789` on loopback, `https://<name>.local:18789` on a
network, or over the customer's tunnel for Away. Served by
`gateway/platforms/api_server.py`.

**Auth:** `Authorization: Bearer <key>` on every route except `/health`.
Today that is one shared key per Brain (see Gate 1 — this is replaced by
per-person passkeys before any multi-person Brain ships).

**Session addressing:** a conversation is a `session_id`. A client continues one
by sending `X-Centurion-Session-Id`; it scopes long-term memory with
`X-Centurion-Session-Key`. Both optional, both documented by the server at
`/v1/capabilities`.

---

## Talking

### `POST /v1/chat/completions`
OpenAI Chat Completions shape. `stream: true` returns `text/event-stream` with
incremental `data:` frames and a terminating `data: [DONE]`. Stateless unless
`X-Centurion-Session-Id` is sent. This is the simple path: ask, receive, done.

### `POST /v1/runs` → `202 {run_id}`
The path a real client uses. Body:

```json
{
  "input": "the user's message",
  "instructions": "optional system preamble",
  "previous_response_id": "optional",
  "conversation_history": [{"role": "...", "content": "..."}]
}
```

Returns immediately so the UI never holds a socket open waiting for a thought.

### `GET /v1/runs/{run_id}/events` → SSE
Structured lifecycle events: tool progress, tokens, and approval requests. This
is what makes a spinner honest — the client can show what the agent is doing
rather than guessing.

### `GET /v1/runs/{run_id}` → status
`POST /v1/runs/{run_id}/stop` → interrupt.
`POST /v1/runs/{run_id}/approval` with `{"choice": "once" | "session" | "always" | "deny"}`.

Approvals are the reason a client must exist: a messenger can only show a wall
of text and hope. A client can hold a decision open with a button.

### `GET /v1/models`, `GET /v1/capabilities`
`capabilities` is the machine-readable contract — endpoints, features, headers.
A client should read it and adapt, not assume.

---

## Reopening — the Gate 0 addition

### `GET /api/threads?limit=30&offset=0`

```json
{
  "object": "list",
  "threads": [
    {
      "id": "20261115_174901_abc123",
      "title": "Webinar plan",
      "size_of_conversation": 42,
      "started_at": "2026-11-15T17:49:01",
      "last_active": "2026-11-15T18:02:11",
      "preview": "first line of the conversation, for a list row",
      "source": "desk"
    }
  ],
  "limit": 30,
  "offset": 0
}
```

Most recent activity first. Compression continuations are projected to their
live tip, so one logical conversation is one row. A thread with no stored title
gets one derived from its first message — a list row is never blank.

### `GET /api/threads/{session_id}?limit=500`

```json
{
  "id": "20261115_174901_abc123",
  "title": "Webinar plan",
  "size_of_conversation": 42,
  "messages": [
    {"id": 1, "role": "user", "content": "...", "truncated": false,
     "created_at": "...", "tool_calls": []}
  ],
  "returned": 12,
  "truncated": false
}
```

Exact id or a unique prefix. Returns the **last** `limit` messages — a client
opens a long thread at the sharp end, not the beginning. Content over 4,000
characters is cut and the message is flagged `truncated: true`; a silently
shortened quote would be worse than an obviously shortened one.

`404 thread_not_found` rather than an empty conversation, because an empty chat
where a thread used to be is a lie about what happened.

---

## The client itself

### `GET /desk` and `GET /desk/{path}`

The web client, served by the Brain from `CENTURION_WEB_CLIENT_DIR` (default
`brain/desk/dist`). Unknown paths fall through to `index.html` so a single-page
client owns its own URLs and a refresh does not 404. Path traversal is refused.
If no client is built on the machine the answer is `503 client_not_built`, said
plainly.

**Why this route exists:** the page that talks to a customer's Brain is
delivered by that Brain. No hosted front door, nothing a third party can switch
off, and an update ships the moment it is built.

---

## What is deliberately not in the contract yet

- **Identity.** `GET /api/me` arrives at Gate 1 with passkeys, roles and
  sign-in rate limiting. Until then every request carries the one shared key.
- **Missions, plans, approvals as first-class objects.** They exist in the iOS
  app's own service layer; the contract for the web client is frozen at Gate 2
  against what the Desk actually needs, not guessed now.
- **Files.** Upload and delivery shapes land with the Desk.
