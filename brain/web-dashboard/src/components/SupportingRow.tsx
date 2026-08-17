import { memo, useEffect, useState } from "react";
import type { Mission } from "../types/life";
import { missionProgress } from "../types/life";
import { ProgressBar } from "./PrimaryCard";

const PREVIEW_COUNT = 4;

interface SupportingRowProps {
  missions: Mission[];
  onOpen: (id: string) => void;
  onMakePrimary?: (id: string) => void;
  onPrefetch?: () => void;
}

function MissionCard({
  mission,
  onOpen,
  onMakePrimary,
  onPrefetch,
}: {
  mission: Mission;
  onOpen: (id: string) => void;
  onMakePrimary?: (id: string) => void;
  onPrefetch?: () => void;
}) {
  const progress = missionProgress(mission);
  const blurb = (mission.statement || mission.purpose || "").trim();
  return (
    <div className="surface rounded-3xl p-5 text-left shadow-sm transition-colors hover:border-amber-glow/40">
      <button
        type="button"
        onClick={() => onOpen(mission.id)}
        onPointerDown={() => onPrefetch?.()}
        className="w-full text-left"
      >
        <p className="text-[11px] font-semibold uppercase tracking-[0.16em] text-amber-soft">
          Supporting
        </p>
        <p className="mt-2 line-clamp-2 font-display text-2xl font-medium leading-snug text-ink">
          {mission.title}
        </p>
        {blurb ? (
          <p className="mt-2 line-clamp-3 text-sm text-ink-muted">{blurb}</p>
        ) : null}
        <div className="mt-5">
          <div className="mb-1.5 flex justify-between text-[11px] text-ink-dim">
            <span>
              {mission.completed_target_count}/{mission.target_count}
            </span>
            <span>{progress}%</span>
          </div>
          <ProgressBar value={progress} height="h-2" />
        </div>
      </button>
      {onMakePrimary && (
        <button
          type="button"
          onClick={() => onMakePrimary(mission.id)}
          className="mt-4 min-h-11 rounded-full px-3 text-sm font-semibold text-amber-soft transition hover:text-amber-bright"
        >
          Set as Primary
        </button>
      )}
    </div>
  );
}

export const SupportingRow = memo(function SupportingRow({
  missions,
  onOpen,
  onMakePrimary,
  onPrefetch,
}: SupportingRowProps) {
  const [allOpen, setAllOpen] = useState(false);
  const preview = missions.slice(0, PREVIEW_COUNT);
  const hiddenCount = Math.max(0, missions.length - preview.length);

  useEffect(() => {
    if (!allOpen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setAllOpen(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [allOpen]);

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
        {preview.map((m) => (
          <MissionCard
            key={m.id}
            mission={m}
            onOpen={onOpen}
            onMakePrimary={onMakePrimary}
            onPrefetch={onPrefetch}
          />
        ))}
      </div>
      {hiddenCount > 0 && (
        <button
          type="button"
          onClick={() => setAllOpen(true)}
          className="mt-4 inline-flex min-h-11 items-center rounded-full bg-accent px-4 py-2 text-sm font-semibold text-[var(--on-accent)] transition hover:brightness-110"
        >
          See all {missions.length} supporting missions
        </button>
      )}

      {allOpen && (
        <div
          className="fixed inset-0 z-40 flex items-end justify-center bg-ink/50 p-4 sm:items-center"
          role="dialog"
          aria-modal="true"
          aria-labelledby="supporting-all-title"
          onClick={() => setAllOpen(false)}
        >
          <div
            className="max-h-[80vh] w-full max-w-2xl overflow-y-auto rounded-3xl bg-canvas p-5 shadow-lg"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-4 flex items-center justify-between gap-3">
              <h3
                id="supporting-all-title"
                className="font-display text-xl font-medium text-ink"
              >
                Supporting missions
              </h3>
              <button
                type="button"
                onClick={() => setAllOpen(false)}
                className="inline-flex min-h-11 items-center rounded-full border border-border px-4 text-sm font-semibold text-ink"
              >
                Close
              </button>
            </div>
            <ul className="divide-y divide-border">
              {missions.map((m) => {
                const progress = missionProgress(m);
                return (
                  <li key={m.id}>
                    <button
                      type="button"
                      onClick={() => {
                        setAllOpen(false);
                        onOpen(m.id);
                      }}
                      className="flex min-h-14 w-full items-center gap-3 py-3 text-left"
                    >
                      <span className="min-w-0 flex-1">
                        <span className="block font-medium text-ink">
                          {m.title}
                        </span>
                        {m.statement ? (
                          <span className="mt-0.5 block truncate text-xs text-ink-muted">
                            {m.statement}
                          </span>
                        ) : null}
                      </span>
                      <span className="shrink-0 text-[11px] text-ink-dim">
                        {progress}%
                      </span>
                    </button>
                  </li>
                );
              })}
            </ul>
          </div>
        </div>
      )}
    </section>
  );
});
