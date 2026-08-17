import { useCallback, useEffect, useState } from "react";
import { bridgeCall } from "./useBridge";
import type { CollabSnapshot, CollabSwarm } from "../types/collab";

/** Bridge wraps the real payload in `snapshot` / `result` (iPhone already unwraps). */
export function unwrapCollabSnapshot(data: unknown): CollabSnapshot {
  const empty: CollabSnapshot = { ok: true, swarms: [] };
  const seen = new Set<unknown>();
  const queue: unknown[] = [data];
  while (queue.length) {
    const cur = queue.shift();
    if (!cur || typeof cur !== "object" || seen.has(cur)) continue;
    seen.add(cur);
    const row = cur as Record<string, unknown>;
    if (Array.isArray(row.swarms)) {
      return row as CollabSnapshot;
    }
    if (row.snapshot) queue.push(row.snapshot);
    if (row.result) queue.push(row.result);
  }
  return empty;
}

export function useCollab(enabled: boolean, intervalMs = 12_000) {
  const [snapshot, setSnapshot] = useState<CollabSnapshot | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const applySnapshot = useCallback((data: unknown) => {
    const next = unwrapCollabSnapshot(data);
    if (next.swarms.length) {
      setSnapshot(next);
      setError(null);
      setLoading(false);
    }
    return next;
  }, []);

  const refresh = useCallback(async () => {
    try {
      const data = await bridgeCall<CollabSnapshot>("swarm_snapshot");
      const next = unwrapCollabSnapshot(data);
      setSnapshot(next);
      setError(null);
      return next;
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      return null;
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!enabled) {
      setLoading(false);
      return;
    }
    void refresh();
    const t = window.setInterval(() => void refresh(), intervalMs);
    return () => window.clearInterval(t);
  }, [enabled, intervalMs, refresh]);

  const swarms: CollabSwarm[] = snapshot?.swarms ?? [];
  return { snapshot, swarms, loading, error, refresh, applySnapshot };
}
