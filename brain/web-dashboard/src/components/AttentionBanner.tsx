import { useState } from "react";
import { Link } from "react-router-dom";
import type { Decision } from "../types/life";
import { resolveOpenDecision } from "../hooks/useOpenDecisions";
import {
  decidePlan,
  type ReviewPlan,
} from "../hooks/usePendingPlans";

/** Plans + open choices waiting on you — Review / Proceed / Adjust / Hold. */
export function AttentionBanner({
  decisions,
  plans,
  onResolved,
}: {
  decisions: Decision[];
  plans?: ReviewPlan[];
  onResolved?: () => void;
}) {
  const pendingPlans = plans || [];
  const [busyKey, setBusyKey] = useState<string | null>(null);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const total = pendingPlans.length + decisions.length;
  if (total === 0) return null;

  async function run(key: string, fn: () => Promise<void>) {
    setBusyKey(key);
    try {
      await fn();
      onResolved?.();
    } finally {
      setBusyKey(null);
    }
  }

  return (
    <div
      className="mt-6 rounded-2xl border-2 border-amber-glow/50 bg-amber-muted px-4 py-4"
      role="status"
      aria-live="polite"
    >
      <div className="flex items-center gap-3">
        <span
          className="inline-flex min-h-7 min-w-7 items-center justify-center rounded-full bg-accent text-sm font-bold text-[var(--on-accent)]"
          aria-label={`${total} decisions needed`}
        >
          {total}
        </span>
        <p className="text-sm font-semibold text-ink">Decisions needed</p>
      </div>
      <ul className="mt-3 space-y-3">
        {pendingPlans.map((plan) => {
          const expanded = expandedId === plan.id;
          const busy = busyKey === `plan:${plan.id}`;
          return (
            <li
              key={`plan:${plan.id}`}
              className="rounded-xl border border-amber-glow/20 bg-canvas/40 px-3 py-3"
            >
              <p className="font-medium text-ink">{plan.title}</p>
              {(plan.goal || plan.summary) && (
                <p className="mt-0.5 text-xs text-ink-dim line-clamp-2">
                  {plan.goal || plan.summary}
                </p>
              )}
              {expanded && (plan.steps || []).length > 0 ? (
                <ol className="mt-2 list-decimal space-y-1 pl-4 text-xs text-ink-muted">
                  {(plan.steps || []).slice(0, 8).map((step, i) => (
                    <li key={`${plan.id}-s-${i}`}>{step}</li>
                  ))}
                </ol>
              ) : null}
              <div className="mt-3 flex flex-wrap gap-2">
                <button
                  type="button"
                  onClick={() =>
                    setExpandedId((cur) => (cur === plan.id ? null : plan.id))
                  }
                  className="inline-flex min-h-11 items-center rounded-full px-3 text-xs font-semibold text-amber-bright"
                >
                  {expanded ? "Hide" : "Review"}
                </button>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() =>
                    void run(`plan:${plan.id}`, async () => {
                      await decidePlan(plan.id, "approve");
                    })
                  }
                  className="inline-flex min-h-11 items-center rounded-full bg-accent px-4 text-xs font-semibold text-[var(--on-accent)] disabled:opacity-50"
                >
                  {busy ? "Saving…" : "Proceed"}
                </button>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() =>
                    void run(`plan:${plan.id}`, async () => {
                      await decidePlan(plan.id, "request_changes");
                    })
                  }
                  className="inline-flex min-h-11 items-center rounded-full border border-amber-glow/40 px-4 text-xs font-semibold text-amber-bright disabled:opacity-50"
                >
                  Adjust
                </button>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() =>
                    void run(`plan:${plan.id}`, async () => {
                      await decidePlan(plan.id, "hold");
                    })
                  }
                  className="inline-flex min-h-11 items-center rounded-full px-4 text-xs font-semibold text-ink-dim disabled:opacity-50"
                >
                  Hold
                </button>
              </div>
            </li>
          );
        })}
        {decisions.map((d) => {
          const mid = d.mission_id;
          const busy = busyKey === `dec:${d.id}`;
          return (
            <li
              key={`dec:${d.id}`}
              className="rounded-xl px-2 py-2"
            >
              <p className="font-medium text-ink">{d.title}</p>
              {d.context ? (
                <p className="mt-0.5 text-xs text-ink-dim line-clamp-2">
                  {d.context}
                </p>
              ) : null}
              <div className="mt-3 flex flex-wrap gap-2">
                {mid ? (
                  <Link
                    to={`/mission/${mid}?attention=${encodeURIComponent(d.id)}`}
                    className="inline-flex min-h-11 items-center rounded-full px-3 text-xs font-semibold text-amber-bright"
                  >
                    Review
                  </Link>
                ) : null}
                <button
                  type="button"
                  disabled={busy}
                  onClick={() =>
                    void run(`dec:${d.id}`, async () => {
                      await resolveOpenDecision(d.id, "Proceed");
                    })
                  }
                  className="inline-flex min-h-11 items-center rounded-full bg-accent px-4 text-xs font-semibold text-[var(--on-accent)] disabled:opacity-50"
                >
                  {busy ? "Saving…" : "Proceed"}
                </button>
                <button
                  type="button"
                  className="inline-flex min-h-11 items-center rounded-full px-4 text-xs font-semibold text-ink-dim"
                >
                  Hold
                </button>
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
