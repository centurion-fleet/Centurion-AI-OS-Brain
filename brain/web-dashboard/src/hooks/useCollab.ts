import { useCallback, useEffect, useState } from "react";
import { bridgeCall } from "./useBridge";
import type { CollabSnapshot, CollabSwarm } from "../types/collab";

export function useCollab(enabled: boolean, intervalMs = 12_000) {
  const [snapshot, setSnapshot] = useState<CollabSnapshot | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const data = await bridgeCall<CollabSnapshot>("swarm_snapshot");
      setSnapshot(data);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!enabled) return;
    void refresh();
    const t = window.setInterval(() => void refresh(), intervalMs);
    return () => window.clearInterval(t);
  }, [enabled, intervalMs, refresh]);

  const swarms: CollabSwarm[] = snapshot?.swarms ?? [];
  return { snapshot, swarms, loading, error, refresh };
}
