#!/usr/bin/env python3
"""WS3 B3 — bridge Unix-socket latency harness.

Usage:
  python3 desktop-native/.perf/bench_bridge_sock.py
  CENTURION_HOME=~/.centurion python3 desktop-native/.perf/bench_bridge_sock.py

Expect warm single-call RTT ~0–3ms when the daemon is already up.
"""

from __future__ import annotations

import json
import os
import socket
import statistics
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


def sock_path() -> Path:
    env = os.environ.get("CENTURION_BRIDGE_SOCKET", "").strip()
    if env:
        return Path(env)
    home = os.environ.get("CENTURION_HOME", "").strip()
    if not home:
        home = str(Path.home() / ".centurion")
    return Path(home) / "run" / "bridge.sock"


def call(action: str, timeout: float = 5.0) -> tuple[float, dict | None, str | None]:
    path = sock_path()
    payload = json.dumps({"id": f"ws3-{action}-{time.time_ns()}", "action": action}) + "\n"
    t0 = time.perf_counter()
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect(str(path))
            s.sendall(payload.encode())
            s.shutdown(socket.SHUT_WR)
            buf = b""
            while not buf.endswith(b"\n") and len(buf) < 8_000_000:
                chunk = s.recv(65536)
                if not chunk:
                    break
                buf += chunk
        ms = (time.perf_counter() - t0) * 1000.0
        line = buf.decode(errors="replace").strip().splitlines()[-1] if buf.strip() else ""
        try:
            return ms, json.loads(line), None
        except json.JSONDecodeError:
            return ms, None, f"bad json: {line[:200]}"
    except OSError as e:
        ms = (time.perf_counter() - t0) * 1000.0
        return ms, None, str(e)


def percentile(xs: list[float], p: float) -> float:
    if not xs:
        return float("nan")
    ys = sorted(xs)
    k = (len(ys) - 1) * (p / 100.0)
    f = int(k)
    c = min(f + 1, len(ys) - 1)
    if f == c:
        return ys[f]
    return ys[f] + (ys[c] - ys[f]) * (k - f)


def main() -> int:
    path = sock_path()
    print(f"socket: {path}")
    if not path.exists():
        print("ERROR: bridge.sock not found — start Brain / bridge daemon first.", file=sys.stderr)
        return 2

    # Warm single-call series
    actions = ("bridge_ping", "life_mission_stack")
    results: dict = {"socket": str(path), "single": {}, "concurrent": {}}

    for action in actions:
        samples: list[float] = []
        errors = 0
        for _ in range(30):
            ms, body, err = call(action)
            if err or not (body or {}).get("ok", True):
                # life_mission_stack may return ok:false without daemon features — still count RTT
                if err:
                    errors += 1
                    continue
            samples.append(ms)
        if not samples:
            results["single"][action] = {"error": "no samples", "errors": errors}
            continue
        results["single"][action] = {
            "n": len(samples),
            "errors": errors,
            "p50_ms": round(percentile(samples, 50), 3),
            "p95_ms": round(percentile(samples, 95), 3),
            "mean_ms": round(statistics.fmean(samples), 3),
        }
        print(
            f"  {action}: p50={results['single'][action]['p50_ms']}ms "
            f"p95={results['single'][action]['p95_ms']}ms n={len(samples)}"
        )

    # Concurrent: 10 threads × life_mission_stack (or bridge_ping fallback)
    action = "life_mission_stack"
    latencies: list[float] = []
    with ThreadPoolExecutor(max_workers=10) as pool:
        futs = [pool.submit(call, action) for _ in range(10)]
        for fut in as_completed(futs):
            ms, _body, err = fut.result()
            if not err:
                latencies.append(ms)
    if latencies:
        results["concurrent"] = {
            "action": action,
            "threads": 10,
            "n": len(latencies),
            "mean_ms": round(statistics.fmean(latencies), 3),
            "p95_ms": round(percentile(latencies, 95), 3),
        }
        print(
            f"  concurrent×10 {action}: mean={results['concurrent']['mean_ms']}ms "
            f"p95={results['concurrent']['p95_ms']}ms"
        )

    out = Path(__file__).resolve().parent / "ws3-bridge-bench.json"
    out.write_text(json.dumps(results, indent=2) + "\n")
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
