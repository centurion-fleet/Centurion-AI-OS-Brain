import { useCallback, useEffect, useState } from "react";
import { bridgeCall } from "./useBridge";
import type { Decision } from "../types/life";

/** Decisions that still need a choice (empty `chosen`) — drives the Focus tab badge. */
export function isOpenDecision(d: Decision): boolean {
  return !(d.chosen || "").trim();
}

export async function fetchOpenDecisions(limit = 20): Promise<Decision[]> {
  const res = await bridgeCall<{ ok: true; decisions: Decision[] }>(
    "life_decisions_list",
    { limit },
  );
  return (res.decisions || []).filter(isOpenDecision);
}

export async function resolveOpenDecision(
  decisionId: string,
  chosen = "Done",
): Promise<void> {
  await bridgeCall("life_decision_resolve", {
    decision_id: decisionId,
    chosen,
  });
}

/** Poll open decisions while the Focus tab is visible. */
export function useOpenDecisions(enabled: boolean, pollMs = 12_000) {
  const [open, setOpen] = useState<Decision[]>([]);
  const [loading, setLoading] = useState(false);

  const refresh = useCallback(async () => {
    if (!enabled) return;
    setLoading(true);
    try {
      setOpen(await fetchOpenDecisions());
    } catch {
      setOpen([]);
    } finally {
      setLoading(false);
    }
  }, [enabled]);

  useEffect(() => {
    if (!enabled) {
      setOpen([]);
      return;
    }
    void refresh();
    const id = window.setInterval(() => void refresh(), pollMs);
    return () => window.clearInterval(id);
  }, [enabled, pollMs, refresh]);

  return { open, loading, refresh };
}
