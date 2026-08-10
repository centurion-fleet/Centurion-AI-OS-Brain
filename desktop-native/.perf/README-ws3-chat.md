# WS3 — Chat speed benchmarks (B3)

## Bridge socket (automated)

With Brain / bridge daemon running:

```bash
python3 desktop-native/.perf/bench_bridge_sock.py
```

Writes `desktop-native/.perf/ws3-bridge-bench.json`.

Expect warm single-call p50 for `bridge_ping` / `life_mission_stack` in **0–3 ms** range on a local socket.

## Chat interaction latency (Fedora / Titus gate A1)

Same machine, same 100+ message session, BEFORE (5.2.136 package) and AFTER (`ws3-chat-speed` build):

1. Open Chat on a session with ≥100 messages (mixed prose + code fences).
2. Scroll to bottom; ensure follow-bottom is on.
3. Type a short follow-up; start timer on **Enter**.
4. Stop when the user bubble is painted **and** the layout has settled (no further jank).
5. Repeat 11 times; drop first (warm-up); report p50 / p95 of the remaining 10.
6. Capture main-loop CPU during one run:

```bash
ps -Lp $(pgrep -f centurion-desktop | head -1) -o pid,lwp,%cpu,comm --sort=-%cpu | head -8
```

Record results in `desktop-native/.perf/ws3-chat-interaction.json`:

```json
{
  "session_messages": 100,
  "before": { "build": "5.2.136", "p50_ms": 0, "p95_ms": 0, "n": 10 },
  "after": { "build": "ws3-chat-speed", "p50_ms": 0, "p95_ms": 0, "n": 10 },
  "p95_reduction_pct": 0
}
```

A1 gate: **p95_reduction_pct ≥ 40**.

## Proxy (developer machine without GTK session)

```bash
cd desktop-native && cargo test -p centurion-desktop ws3_chat_render_proxy -- --nocapture
```

Reports paragraph-widget counts before/after coalescing on a synthetic 100-message corpus (structural win; not a substitute for A1).
