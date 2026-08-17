import { useCallback, useEffect, useState } from "react";
import { bridgeCall } from "./useBridge";

export interface ReviewPlan {
  id: string;
  title: string;
  goal?: string;
  summary?: string;
  steps?: string[];
  risks?: string[];
  status?: string;
  related_mission?: string | null;
  relatedMission?: string | null;
}

const PENDING = new Set(["pending_review", "held", "adjusted", "proposed", "pending"]);

export function isPendingPlan(p: ReviewPlan): boolean {
  return PENDING.has(String(p.status || "pending_review").toLowerCase());
}

export async function fetchPendingPlans(): Promise<ReviewPlan[]> {
  const res = await bridgeCall<{ ok: true; plans: ReviewPlan[] }>("plans_list", {
    status: "pending_review",
  });
  return (res.plans || []).filter(isPendingPlan);
}

export async function decidePlan(
  planId: string,
  choice: "approve" | "request_changes" | "hold",
): Promise<void> {
  await bridgeCall("plan_decide", { plan_id: planId, choice });
}

export function usePendingPlans(enabled: boolean, pollMs = 12_000) {
  const [plans, setPlans] = useState<ReviewPlan[]>([]);
  const [loading, setLoading] = useState(false);

  const refresh = useCallback(async () => {
    if (!enabled) return;
    setLoading(true);
    try {
      setPlans(await fetchPendingPlans());
    } catch {
      setPlans([]);
    } finally {
      setLoading(false);
    }
  }, [enabled]);

  useEffect(() => {
    if (!enabled) {
      setPlans([]);
      return;
    }
    void refresh();
    const id = window.setInterval(() => void refresh(), pollMs);
    return () => window.clearInterval(id);
  }, [enabled, pollMs, refresh]);

  return { plans, loading, refresh };
}
