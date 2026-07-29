import { motion } from "framer-motion";
import type { Mission } from "../types/life";
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
  onOpen: () => void;
}

export function PrimaryCard({
  mission,
  latestThought,
  onOpen,
}: PrimaryCardProps) {
  const progress = missionProgress(mission);

  return (
    <motion.button
      type="button"
      onClick={onOpen}
      layout
      initial={{ opacity: 0, y: 24 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ type: "spring", stiffness: 160, damping: 22 }}
      className="glass-strong group relative w-full overflow-hidden rounded-3xl p-6 text-left shadow-glass sm:p-8"
    >
      <div className="pointer-events-none absolute -right-16 -top-16 h-48 w-48 rounded-full bg-amber-glow/20 blur-3xl transition-opacity group-hover:opacity-80" />
      <div className="relative">
        <div className="mb-4 flex items-center gap-2">
          <span className="rounded-full bg-amber-muted px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.14em] text-amber-bright">
            Primary Mission
          </span>
          <span className="text-xs capitalize text-ink-dim">{mission.phase}</span>
        </div>

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
      </div>
    </motion.button>
  );
}
