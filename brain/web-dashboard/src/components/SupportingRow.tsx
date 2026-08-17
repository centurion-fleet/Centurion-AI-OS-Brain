import { memo } from "react";
import type { Mission } from "../types/life";
import { missionProgress } from "../types/life";
import { ProgressBar } from "./PrimaryCard";

interface SupportingRowProps {
  missions: Mission[];
  onOpen: (id: string) => void;
  onMakePrimary?: (id: string) => void;
  onPrefetch?: () => void;
}

export const SupportingRow = memo(function SupportingRow({
  missions,
  onOpen,
  onMakePrimary,
  onPrefetch,
}: SupportingRowProps) {
  if (!missions.length) return null;

  return (
    <section className="mt-12">
      <div className="mb-4 flex items-end justify-between gap-3 px-1">
        <div>
          <h2 className="font-display text-2xl font-medium text-ink sm:text-3xl">
            Supporting missions
          </h2>
          <p className="mt-1 text-sm text-ink-muted">
            Other work on this Brain — tap one to open it.
          </p>
        </div>
        <span className="inline-flex min-h-7 min-w-7 items-center justify-center rounded-full bg-accent text-sm font-bold text-[var(--on-accent)]">
          {missions.length}
        </span>
      </div>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        {missions.map((m) => {
          const progress = missionProgress(m);
          const blurb = (m.statement || m.purpose || "").trim();
          return (
            <div
              key={m.id}
              className="surface rounded-3xl p-5 text-left shadow-sm transition-colors hover:border-amber-glow/40"
            >
              <button
                type="button"
                onClick={() => onOpen(m.id)}
                onPointerDown={() => onPrefetch?.()}
                className="w-full text-left"
              >
                <p className="text-[11px] font-semibold uppercase tracking-[0.16em] text-amber-soft">
                  Supporting
                </p>
                <p className="mt-2 line-clamp-2 font-display text-2xl font-medium leading-snug text-ink">
                  {m.title}
                </p>
                {blurb ? (
                  <p className="mt-2 line-clamp-3 text-sm text-ink-muted">{blurb}</p>
                ) : null}
                <div className="mt-5">
                  <div className="mb-1.5 flex justify-between text-[11px] text-ink-dim">
                    <span>
                      {m.completed_target_count}/{m.target_count}
                    </span>
                    <span>{progress}%</span>
                  </div>
                  <ProgressBar value={progress} height="h-2" />
                </div>
              </button>
              {onMakePrimary && (
                <button
                  type="button"
                  onClick={() => onMakePrimary(m.id)}
                  className="mt-4 min-h-11 rounded-full px-3 text-sm font-semibold text-amber-soft transition hover:text-amber-bright"
                >
                  Set as Primary
                </button>
              )}
            </div>
          );
        })}
      </div>
    </section>
  );
});
