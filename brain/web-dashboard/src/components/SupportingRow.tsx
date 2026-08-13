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
    <section className="mt-14">
      <h2 className="mb-4 px-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-ink-dim">
        Supporting
      </h2>
      <div className="grid grid-cols-[repeat(auto-fill,minmax(220px,1fr))] gap-3">
        {missions.map((m) => {
          const progress = missionProgress(m);
          return (
            <div
              key={m.id}
              className="surface rounded-2xl p-4 text-left transition-colors hover:border-amber-glow/25"
            >
              <button
                type="button"
                onClick={() => onOpen(m.id)}
                onPointerDown={() => onPrefetch?.()}
                className="w-full text-left"
              >
                <p className="line-clamp-2 font-display text-lg font-medium leading-snug text-ink">
                  {m.title}
                </p>
                <div className="mt-4">
                  <div className="mb-1.5 flex justify-between text-[11px] text-ink-dim">
                    <span>
                      {m.completed_target_count}/{m.target_count}
                    </span>
                    <span>{progress}%</span>
                  </div>
                  <ProgressBar value={progress} height="h-1.5" />
                </div>
              </button>
              {onMakePrimary && (
                <button
                  type="button"
                  onClick={() => onMakePrimary(m.id)}
                  className="mt-3 text-[11px] font-semibold text-amber-soft transition hover:text-amber-bright"
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
