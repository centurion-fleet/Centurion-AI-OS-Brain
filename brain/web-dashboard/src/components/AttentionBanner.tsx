import { Link } from "react-router-dom";
import type { Decision } from "../types/life";

/** In-deck list of open decisions so the Focus badge always has a visible target. */
export function AttentionBanner({
  decisions,
}: {
  decisions: Decision[];
}) {
  if (decisions.length === 0) return null;

  return (
    <div
      className="mt-6 rounded-2xl border-2 border-amber-glow/50 bg-amber-muted px-4 py-4"
      role="status"
      aria-live="polite"
    >
      <div className="flex items-center gap-3">
        <span
          className="inline-flex min-h-7 min-w-7 items-center justify-center rounded-full bg-accent text-sm font-bold text-[var(--on-accent)]"
          aria-label={`${decisions.length} need your choice`}
        >
          {decisions.length}
        </span>
        <p className="text-sm font-semibold text-ink">Needs your choice</p>
      </div>
      <ul className="mt-3 space-y-2">
        {decisions.map((d) => {
          const mid = d.mission_id;
          const body = (
            <>
              <span className="font-medium text-ink">{d.title}</span>
              {d.context ? (
                <span className="mt-0.5 block text-xs text-ink-dim line-clamp-2">
                  {d.context}
                </span>
              ) : null}
            </>
          );
          return (
            <li key={d.id}>
              {mid ? (
                <Link
                  to={`/mission/${mid}?attention=${encodeURIComponent(d.id)}`}
                  className="block rounded-xl px-2 py-2 transition hover:bg-amber-glow/15"
                >
                  {body}
                  <span className="mt-1 block text-[11px] font-semibold text-amber-bright">
                    Open this choice
                  </span>
                </Link>
              ) : (
                <div className="px-2 py-1.5">{body}</div>
              )}
            </li>
          );
        })}
      </ul>
    </div>
  );
}
