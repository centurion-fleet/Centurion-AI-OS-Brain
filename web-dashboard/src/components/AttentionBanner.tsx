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
      className="mt-6 rounded-2xl border border-amber-glow/35 bg-amber-muted/40 px-4 py-3"
      role="status"
      aria-live="polite"
    >
      <p className="text-[11px] font-semibold uppercase tracking-[0.16em] text-amber-soft">
        Needs your choice ({decisions.length})
      </p>
      <ul className="mt-2 space-y-2">
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
                  className="block rounded-xl px-2 py-1.5 transition hover:bg-amber-glow/15"
                >
                  {body}
                  <span className="mt-1 block text-[11px] font-semibold text-amber-bright">
                    Open →
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
