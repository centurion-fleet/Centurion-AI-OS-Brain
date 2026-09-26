# Steve's onboarding — review, 26 Sep 2026

**Asked for:** "do another review to make sure Steve's onboarding works for him."

**Method:** read the shipped code paths, then read the *built artifacts* for what each version
actually contains. Where a claim could only be checked by touching the live network, it is marked
as not performed rather than assumed.

Skeptical re-examination, not a defence: two things I had believed going in turned out to be wrong,
and both are corrected below.

---

## 1. What Steve is trying to do

Steve White and Kim, same office (Ballina). Each has a Brain with its own Centurion. The goal is
brain-to-brain pairing so their Centurions can talk. The screen is **Settings → Connect another
Centurion**, and it has two halves: *make this Brain reachable* (produce two values — address and
secret) and *connect to theirs* (enter their two values).

Steve's report, verbatim: *"Both machines never got past make this centurion reachable. They just
keep coming back to that same button… It just didn't change."*

## 2. Three separate defects were stacked behind that one button

All three are fixed in code. The order matters, because they produced one indistinguishable symptom.

**Defect 1 — the instruction pointed at a screen that does not exist.**
The previous dialog told the customer to get their two values from *"Collaborations → Invite another
owner → Make this Brain reachable"*. The code comment recording this is blunt about the consequence:
*"a screen that does not exist — so neither side could produce the two values, and a live call had
nowhere to go."* That alone explains "they keep coming back to that same button": the instruction
sent them somewhere empty, so they returned and pressed it again.

*Caveat, stated honestly:* I could not date this by searching the built binaries — the string does not
appear in any of 6.0.7, 6.0.8, 6.0.9, 7.0.0, 7.0.0-2. So I have it from the code comment, not from
the artifacts.

**Defect 2 — the listen address was written to a node the gateway does not read.**
`fleet_peer_enable` wrote `gateway.platforms.api_server.extra.host`. The gateway's config loader does
not read that node — it assembles platform config from the top-level `platforms:` block plus
environment variables. So the listener stayed bound to `127.0.0.1:8642`, no peer could ever reach it,
and the UI said *"nothing is listening yet. Restart the Brain"* no matter how many times the customer
restarted. The enable path now also writes `API_SERVER_ENABLED`, `API_SERVER_HOST`, `API_SERVER_PORT`
and `CENTURION_FLEET_TOKEN` to `.env`, which is the path the loader honours.

**Defect 3 — the screen did not redraw after the press.**
The two values only exist after the enable call returns. Without a redraw the customer presses the
button and the screen still reads "not reachable yet", which reads as a dead button.

## 3. What each shipped version actually contains

Read out of the built binaries with a raw byte search. (`strings` is unusable here: the copy contains
em-dashes, and `strings` only prints ASCII runs, so it silently hides the very strings being looked for.
I made that mistake first and nearly reported a false finding off it.)

| build | redraw-after-press | "reachable" message | corrected restart advice | Stillpoint | phone-tunnel unit |
|---|---|---|---|---|---|
| 6.0.7 | — | — | — | — | no |
| 6.0.8 | yes | yes | **no** | no | no |
| 6.0.9 | yes | yes | **no** | no | no |
| 7.0.0 | yes | yes | yes | no | no |
| 7.0.0-2 *(built, not published)* | yes | yes | yes | yes | **yes** |

Two conclusions that change the plan:

- **The connect screen's fixes are already in 7.0.0.** Defects 2 and 3 landed in 6.0.8; the corrected
  restart advice landed in 7.0.0. If Steve is able to update to 7.0.0, the pairing screen is fixed
  whether or not 7.0.0-2 ever ships.
- **6.0.8 and 6.0.9 have no corrected restart advice**, which is the version most likely to be the one
  Steve was on. On those builds, a failed bind ends in advice that does not work, and the customer
  loops — exactly his report.

## 4. The enable half genuinely works — verified on this machine

Not inferred from config, measured:

- `ss -ltn` shows **`0.0.0.0:18789` listening** (not loopback — all interfaces).
- `gateway.platforms.api_server` is `enabled: True`, host `0.0.0.0`, port `18789`, with a fleet token set.
- All three of `API_SERVER_ENABLED` / `API_SERVER_HOST` / `CENTURION_FLEET_TOKEN` are present in `.env`.

So the enable path produces a real bind, and the "listening" flag the UI polls is a genuine port probe,
not a config read. The code says it better than I can: *"Config saying 0.0.0.0 is a promise; this is
the fact."*

## 5. What has never been proven

**No peer has ever been registered, on any Brain.** `~/.centurion/fleet/` holds `identity.json`,
empty `locks/`, `messages/` and `outbox/` — and **no peers file**. A message has never crossed between
two Brains and come back.

Everything in section 4 proves one half: this Brain is willing and able to be reached. It does not
prove the other half — that another Brain can reach it, authenticate, and complete a crossing. Those
are different claims and only the first is evidenced.

**Not performed:** the live network probe (an authenticated `GET /fleet/status` over the LAN address,
plus the same request with no token to confirm it is refused). It was blocked pending consent and I have
not retried or worked around it. Until that runs, the crossing stays unproven.

## 6. Two real risks that remain

**6a. The reachability message over-claims, and the probe cannot detect the case where it is wrong.**
`_port_listening` targets `127.0.0.1` whenever the configured host is `0.0.0.0`. So it proves *a local
listener exists* — never that the other machine can reach it. The UI then says "This Centurion is
reachable."

Whether that bites depends entirely on the firewall zone:

- On **FedoraWorkstation** (this machine, and the Fedora default) the zone opens `1025-65535/tcp`, so
  18789 is allowed. **I checked this and it is fine** — an early draft of this review claimed the
  packaged firewalld service was the problem, because it only mentions 9119. That was wrong: the service
  file is belt-and-braces, and the port range already covers 18789.
- On a machine whose default zone is **`public`** — common on Fedora Server, or after a user changes
  zone — nothing above 1024 is open, `18789` is blocked from other hosts, and **the UI still says
  "reachable"** because the probe never leaves loopback.

The fix is small and worth doing: probe through the LAN address, so the sentence the customer reads is
the claim actually being tested.

**6b. The pairing loop has no happy-path proof for a customer to follow.** The enable screen prints the
CLI instruction (`centurion fleet peer connect …`) in the CLI path, but the GUI path expects the two
values to be swapped by hand and typed in. Nothing in what I read tests the full loop — enable → swap →
connect → a message crossing. Until that is demonstrated on two real machines, every claim about
brain-to-brain is scaffolding.

## 7. What I would do, in order

1. **Get Steve to 7.0.0 at minimum.** That fixes the pairing screen he is stuck on. 7.0.0 is published;
   7.0.0-2 is built, signed and waiting on the publish credential.
2. **Push 7.0.0-2** once the credential is in place — it additionally carries the phone-tunnel fix and
   Stillpoint, and stops the next rebuild being needed for the tunnel.
3. **Run the crossing once, on two machines, and record it.** Until then "brain-to-brain works" is a
   description of code, not a fact.
4. **Fix the probe** to test through the LAN address (6a).
5. Ask Steve **which version his Brain reports**. That single fact decides whether his failure was the
   dead-end advice on 6.0.9 or something still live on 7.0.0 — and I should not guess it for him.

---

*Prepared by Titus, 26 Sep 2026. Every version claim in section 3 was read out of the built RPMs;
every claim in section 4 was measured on this machine; section 5 is the boundary of what is known.*
