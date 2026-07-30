import { Link } from "react-router-dom";
import { memo } from "react";
import { m as motion, useReducedMotion } from "framer-motion";
import type { LifeDocument, Mission } from "../types/life";
import { missionProgress } from "../types/life";

interface ProgressBarProps {
  value: number;
  className?: string;
  height?: string;
}

export function ProgressBar({
  value,
  className = "",
  height = "h-2",
}: ProgressBarProps) {
  const pct = Math.max(0, Math.min(100, value));
  const reduce = useReducedMotion();
  return (
    <div
      className={`w-full overflow-hidden rounded-full bg-white/5 ${height} ${className}`}
    >
      <motion.div
        className="amber-bar h-full rounded-full"
        initial={reduce ? false : { width: 0 }}
        animate={{ width: `${pct}%` }}
        transition={
          reduce
            ? { duration: 0 }
            : { type: "spring", stiffness: 120, damping: 20 }
        }
      />
    </div>
  );
}

interface PrimaryCardProps {
  mission: Mission;
  latestThought?: string | null;
  documents?: LifeDocument[];
  documentCount?: number;
  onOpen: () => void;
  onDiscuss?: () => void;
  onPrefetch?: () => void;
  /** When true, render as the Focus first-viewport hero (no nested card chrome). */
  hero?: boolean;
}

export const PrimaryCard = memo(function PrimaryCard({
  mission,
  latestThought,
  documents = [],
  documentCount,
  onOpen,
  onDiscuss,
  onPrefetch,
  hero = false,
}: PrimaryCardProps) {
  const progress = missionProgress(mission);
  const docsHref = `/mission/${mission.id}#documents`;
  const shown = documents.slice(0, 3);
  const total = documentCount ?? documents.length;
  const reduce = useReducedMotion();

  const shell = hero
    ? "relative w-full overflow-hidden pt-2 text-left sm:pt-4"
    : "glass-strong group relative w-full overflow-hidden rounded-3xl p-6 text-left shadow-glass sm:p-8";

  return (
    <motion.div
      initial={reduce ? false : { opacity: 0, y: 18 }}
      animate={{ opacity: 1, y: 0 }}
      transition={
        reduce
          ? { duration: 0 }
          : { type: "spring", stiffness: 160, damping: 24 }
      }
      className={shell}
    >
      {!hero && (
        <div className="pointer-events-none absolute -right-16 -top-16 h-48 w-48 rounded-full bg-amber-glow/20 blur-3xl transition-opacity group-hover:opacity-80" />
      )}
      <div className="relative">
        <div className="mb-5 flex flex-wrap items-center gap-2">
          <span className="text-[11px] font-semibold uppercase tracking-[0.16em] text-amber-soft">
            Primary Mission
          </span>
          <span className="text-xs capitalize text-ink-dim">{mission.phase}</span>
        </div>

        <button
          type="button"
          onClick={onOpen}
          onPointerDown={() => onPrefetch?.()}
          className="w-full text-left"
        >
          <h1 className="font-display text-4xl font-medium leading-[1.08] tracking-tight text-ink sm:text-5xl md:text-6xl">
            {mission.title || "Untitled mission"}
          </h1>

          {(mission.statement || mission.purpose) && (
            <p className="mt-4 max-w-2xl text-base leading-relaxed text-ink-muted sm:text-lg">
              {mission.statement || mission.purpose}
            </p>
          )}

          <div className="mt-10 max-w-xl">
            <div className="mb-2 flex items-end justify-between">
              <span className="text-sm text-ink-muted">
                {mission.completed_target_count}/{mission.target_count} targets
              </span>
              <span className="font-display text-2xl font-medium text-amber-glow">
                {progress}%
              </span>
            </div>
            <ProgressBar value={progress} height="h-2.5" />
          </div>

          {latestThought && (
            <p className="mt-8 max-w-2xl border-t border-white/8 pt-5 font-display text-lg italic leading-snug text-ink-dim">
              “{latestThought}”
            </p>
          )}
        </button>

        <div className="mt-8 flex flex-wrap gap-3">
          <button
            type="button"
            onClick={onOpen}
            onPointerDown={() => onPrefetch?.()}
            className="rounded-full bg-amber-gradient px-5 py-2.5 text-sm font-semibold text-canvas shadow-amber-sm transition hover:brightness-110"
          >
            Open mission
          </button>
          {onDiscuss && (
            <button
              type="button"
              onClick={onDiscuss}
              className="rounded-full border border-amber-glow/40 bg-amber-muted/50 px-5 py-2.5 text-sm font-semibold text-amber-bright transition hover:bg-amber-glow/20"
            >
              Discuss
            </button>
          )}
        </div>

        <div className="mt-10 border-t border-white/8 pt-5">
          <div className="mb-2 flex items-center justify-between gap-2">
            <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-ink-dim">
              Documents{total > 0 ? ` · ${total}` : ""}
            </p>
            <Link
              to={docsHref}
              className="text-[11px] font-semibold text-amber-soft transition hover:text-amber-bright"
            >
              View all
            </Link>
          </div>
          {shown.length === 0 ? (
            <p className="text-sm text-ink-dim">
              Documents for this mission will show here.
            </p>
          ) : (
            <ul className="space-y-1">
              {shown.map((d) => (
                <li key={d.id}>
                  <Link
                    to={docsHref}
                    className="flex items-center gap-2 rounded-lg px-1 py-1.5 text-sm text-ink transition hover:text-amber-soft"
                  >
                    <span className="min-w-0 flex-1 truncate font-medium">
                      {d.title}
                    </span>
                    <span className="shrink-0 text-[10px] uppercase tracking-wide text-ink-dim">
                      {d.doc_type || "other"}
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </motion.div>
  );
});
