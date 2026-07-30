import { Link } from "react-router-dom";
import { memo } from "react";
import { motion } from "framer-motion";
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
  return (
    <div
      className={`w-full overflow-hidden rounded-full bg-white/5 ${height} ${className}`}
    >
      <motion.div
        className="amber-bar h-full rounded-full"
        initial={{ width: 0 }}
        animate={{ width: `${pct}%` }}
        transition={{ type: "spring", stiffness: 120, damping: 20 }}
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
}

export const PrimaryCard = memo(function PrimaryCard({
  mission,
  latestThought,
  documents = [],
  documentCount,
  onOpen,
  onDiscuss,
}: PrimaryCardProps) {
  const progress = missionProgress(mission);
  const docsHref = `/mission/${mission.id}#documents`;
  const shown = documents.slice(0, 3);
  const total = documentCount ?? documents.length;

  return (
    <motion.div
      layout
      initial={{ opacity: 0, y: 24 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ type: "spring", stiffness: 160, damping: 22 }}
      className="glass-strong group relative w-full overflow-hidden rounded-3xl p-6 text-left shadow-glass sm:p-8"
    >
      <div className="pointer-events-none absolute -right-16 -top-16 h-48 w-48 rounded-full bg-amber-glow/20 blur-3xl transition-opacity group-hover:opacity-80" />
      <div className="relative">
        <div className="mb-4 flex flex-wrap items-center gap-2">
          <span className="rounded-full bg-amber-muted px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.14em] text-amber-bright">
            Primary Mission
          </span>
          <span className="text-xs capitalize text-ink-dim">{mission.phase}</span>
          {onDiscuss && (
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                onDiscuss();
              }}
              title="Discuss in Chat"
              aria-label={`Discuss ${mission.title} in Chat`}
              className="ml-auto rounded-full border border-amber-glow/35 bg-amber-muted/70 px-3 py-1 text-sm font-semibold text-amber-bright transition hover:bg-amber-glow/25"
            >
              💬 Discuss
            </button>
          )}
        </div>

        <button type="button" onClick={onOpen} className="w-full text-left">
          <h1 className="font-display text-3xl font-semibold leading-tight tracking-tight text-ink sm:text-4xl md:text-5xl">
            {mission.title || "Untitled mission"}
          </h1>

          {(mission.statement || mission.purpose) && (
            <p className="mt-3 max-w-2xl text-base leading-relaxed text-ink-muted sm:text-lg">
              {mission.statement || mission.purpose}
            </p>
          )}

          <div className="mt-8">
            <div className="mb-2 flex items-end justify-between">
              <span className="text-sm text-ink-muted">
                {mission.completed_target_count}/{mission.target_count} targets
              </span>
              <span className="font-display text-2xl font-semibold text-amber-glow">
                {progress}%
              </span>
            </div>
            <ProgressBar value={progress} height="h-2.5" />
          </div>

          {latestThought && (
            <motion.p
              key={latestThought}
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              className="mt-6 line-clamp-2 border-t border-white/5 pt-4 text-sm italic text-ink-dim"
            >
              “{latestThought}”
            </motion.p>
          )}
        </button>

        <div className="mt-6 border-t border-white/5 pt-4">
          <div className="mb-2 flex items-center justify-between gap-2">
            <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-ink-dim">
              Documents{total > 0 ? ` · ${total}` : ""}
            </p>
            <Link
              to={docsHref}
              onClick={(e) => e.stopPropagation()}
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
            <ul className="space-y-1.5">
              {shown.map((d) => (
                <li key={d.id}>
                  <Link
                    to={docsHref}
                    onClick={(e) => e.stopPropagation()}
                    className="flex items-center gap-2 rounded-xl px-2 py-1.5 text-sm text-ink transition hover:bg-white/5"
                  >
                    <span className="min-w-0 flex-1 truncate font-medium">
                      {d.title}
                    </span>
                    <span className="shrink-0 rounded-full border border-white/10 px-2 py-0.5 text-[10px] uppercase tracking-wide text-ink-dim">
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
