# Own the Interface — gates, for future reference

**Decision (Adrian, 15 Nov 2026):** build continuously from here until it is done.
No calendar estimates, no parking. This document is the reference of record for
what is being built and the order in which it is proved. It is not a schedule.

**Plan object:** `35e50d08-d94c-4b74-9ef6-fd7a15a5bd32` (Plans, status
pending_review → active on Proceed).

---

## Where we are today (measured, 15 Nov 2026)

| Surface | State |
|---|---|
| Brain software | Live on Linux (this box, `ships-ai`) |
| iPhone app | 28,118 lines of SwiftUI, TestFlight build 45 — **built, not shipped** |
| Android | README scaffold only |
| Web interface | Mission Deck only (React + Vite, missions UI) — no chat client |
| Desktop | Linux GTK/Rust Brain shell; macOS scaffold |
| Daily interface | Telegram and WhatsApp via gateway platform adapters |

The Brain already exposes an HTTP API: `gateway/platforms/api_server.py` is an
aiohttp server with Bearer auth and SSE streaming, listening on `:18789`. A web
client therefore needs a *client*, not a new server. That is the single fact
this whole programme is built on.

---

## The architecture decision

**Two codebases, not five.**

1. **One TypeScript/React web client** — the canonical client. Served by the
   Brain itself. Wrapped for desktop (Tauri: Linux, macOS, Windows) and for
   Android plus tablets (Capacitor). Windows tablets come free with the desktop
   shell.
2. **The existing SwiftUI app** — finished for iPhone and iPad. Not rewritten.
   Rewriting 28k working lines into the web stack is the expensive version of
   this programme and it buys nothing.

**Transport:** the Brain's own HTTP API (Bearer + SSE) on `:18789`, extended,
not replaced. The Rust Crypto Chat channel on `:9119` stays for the phone's
paired path; it is not the client contract.

**Sovereignty rule:** the client is served by the customer's own Brain, over the
customer's own network or tunnel. No hosted front door, no relay in the default
path.

---

## The gates, in order

Each gate ends in a demonstration. The next gate starts in the same session.

### Gate 0 — Freeze the client contract
Document the `api_server` surface the client will use, and write the endpoints
that do not exist: **thread history**, **per-person identity**, **approval
actions**.
**Proof:** a curl script drives a full conversation and an approval with no
messenger in the path.

### Gate 1 — Identity
Lift `webauthn.py` and its store out of `centurion_cli/practice_desk/` into a
shared module. First-run claim. Roles. Sign-in rate limiting.
**Proof:** two people sign in to one Brain with separate passkeys and hold
separate threads. No multi-person Brain ships on a shared token.

### Gate 2 — Web Desk
React client served by `api_server`: streaming chat, threads, file drop,
missions, approvals.
**Proof:** Adrian works a full day with Telegram closed.

### Gate 3 — Served to the network
The mDNS name, own CA and join-page pattern from the practice desk applied to
the Brain: HTTPS, trusted certificate, join instructions.
**Proof:** a phone on the same Wi-Fi opens the Desk with a green certificate and
signs in with a fingerprint.

### Gate 4 — Desktop shells
Tauri wrapping the same web build for Linux, macOS and Windows: tray, autostart,
drag-and-drop, native window.
**Proof:** the Linux Brain launches it as the default UI; the Mac and Windows
builds open and stream.

### Gate 5 — Android and tablets
Capacitor wrap of the same build. Play signing and listing.
**Proof:** installed from Play on a phone and a tablet, streaming.

### Gate 6 — iPhone and iPad
Finish the SwiftUI app against the frozen contract. Add the iPad universal
layout. Submit.
**Proof:** live on the App Store, not TestFlight. Needs the MacBook and an Apple
Developer account; if either is missing, Gates 4, 5, 7 and 8 proceed and this
queues rather than stalls the run.

### Gate 7 — Away access
The customer's own tunnel as the default. The existing Vercel + Supabase relay
demoted to explicit opt-in with the cost written down.
**Proof:** a phone on mobile data reaches its Brain over its own tunnel with no
relay in the path.

### Gate 8 — Retire the messengers
Telegram and WhatsApp demoted to optional bridges, off by default for the owner,
left available for the fleet.
**Proof:** a full week with no messenger adapter enabled and nothing missed.

---

## Standing order

The run does not stop between gates. Each demonstration is reported as evidence,
then the next gate starts in the same session.

When a gate overruns, **scope is cut inside that gate** — never the gate order,
never the run.

---

## Risks held against this programme

1. **No calendar means no parking.** Overrun is answered by cutting scope inside
   the gate, not by deferring the gate or quietly widening the plan.
2. **The Away path dials out to Vercel + Supabase Realtime** (`REMOTE_RELAY.md`).
   A third party inside the pipe of a sovereignty product, and it lets the box be
   switched off. Must become explicit opt-in with the cost written down, or be
   replaced by the customer's own tunnel. Gate 7.
3. **Auth today is one shared Bearer token.** Correct for one person, unsafe for
   a firm. Gate 1 is load-bearing: nothing multi-person ships before it.
4. **The Brain becomes a login page on a customer's network.** TLS, passkeys and
   rate limiting are structural, not polish.
5. **Store review is a third party that can delay or refuse delivery.** The web
   client is the hedge — which is why it is Gate 2, not Gate 6.
6. **Do not rewrite the SwiftUI app** into the web stack. It already works.
7. **Only external dependencies:** Apple Developer ($99/yr) for Gate 6, Play
   Console ($25 once) for Gate 5, the MacBook for Gate 6. Decisions plus money,
   not work.
8. **Do not cut Telegram before the Web Desk has proved itself for a week.**
   Gate 8 is last for that reason.

---

## Definition of done for the programme

Adrian's daily interface — chat, missions, approvals, files — runs on a client
he owns, served by his own Brain, on every screen he uses: phone, tablet, laptop,
desktop. Telegram and WhatsApp are optional bridges, not the product. Nothing in
the path can switch his assistant off.
