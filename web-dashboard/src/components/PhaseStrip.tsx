import { PHASE_COPY, PHASE_ORDER } from "../lib/missionPhases";
import type { MissionPhase } from "../types/life";

type Props = {
  phase: MissionPhase;
};

/**
 * Compact lifecycle strip: past muted, current highlighted, future dim.
 */
export function PhaseStrip({ phase }: Props) {
  const currentIdx = PHASE_ORDER.indexOf(phase);
  const activeIdx = currentIdx < 0 ? 0 : currentIdx;
  const help = PHASE_COPY[phase]?.help ?? PHASE_COPY.executing.help;

  return (
    <div className="mt-4">
      <ol
        className="flex flex-wrap items-center gap-x-1 gap-y-2"
        aria-label="Mission stages"
      >
        {PHASE_ORDER.map((step, i) => {
          const { label } = PHASE_COPY[step];
          const isCurrent = i === activeIdx;
          const isPast = i < activeIdx;
          return (
            <li key={step} className="flex items-center gap-1">
              {i > 0 && (
                <span
                  className={`mx-0.5 hidden h-px w-3 sm:block ${
                    isPast || isCurrent
                      ? "bg-amber-glow/50"
                      : "bg-ink-dim/25"
                  }`}
                  aria-hidden
                />
              )}
              <span
                className={
                  isCurrent
                    ? "rounded-full bg-amber-muted px-2.5 py-0.5 text-[11px] font-semibold tracking-wide text-amber-bright"
                    : isPast
                      ? "px-1.5 text-[11px] font-medium text-ink-muted"
                      : "px-1.5 text-[11px] font-medium text-ink-dim/70"
                }
                aria-current={isCurrent ? "step" : undefined}
              >
                {label}
              </span>
            </li>
          );
        })}
      </ol>
      <p className="mt-2 text-sm text-ink-muted">{help}</p>
    </div>
  );
}
