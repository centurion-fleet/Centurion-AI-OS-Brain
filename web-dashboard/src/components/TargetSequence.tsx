import { motion } from "framer-motion";
import type { MissionTarget, TargetType } from "../types/life";
import { TARGET_LABELS } from "../types/life";
import { ProgressBar } from "./PrimaryCard";

const BADGE: Record<TargetType, string> = {
  essential: "bg-amber-glow/20 text-amber-bright border-amber-glow/30",
  shouldHave: "bg-white/5 text-ink-muted border-white/10",
  niceToHave: "bg-white/[0.03] text-ink-dim border-white/5",
};

function groupProgress(targets: MissionTarget[]): number {
  if (!targets.length) return 0;
  const done = targets.filter((t) => t.status === "complete").length;
  return Math.round((100 * done) / targets.length);
}

interface TargetSequenceProps {
  targets: MissionTarget[];
  missionId: string;
  missionTitle: string;
  missionStatement?: string;
}

function discussTarget(
  mission: {
    id: string;
    title: string;
    statement?: string;
  },
  t: MissionTarget,
) {
  const w = window as Window & {
    centurionDiscuss?: (p: Record<string, unknown>) => void;
  };
  if (typeof w.centurionDiscuss !== "function") return;
  const label = TARGET_LABELS[t.target_type] || "Target";
  w.centurionDiscuss({
    id: mission.id,
    title: mission.title,
    statement: mission.statement || "",
    target_id: t.id,
    target_title: t.title,
    target_type: t.target_type,
    target_description: t.description || "",
    target_status: t.status,
    sequence_number: t.sequence_number,
    kickoff: `Let's discuss this ${label} target: ${t.title}`,
  });
}

export function TargetSequence({
  targets,
  missionId,
  missionTitle,
  missionStatement,
}: TargetSequenceProps) {
  const ordered = [...targets].sort(
    (a, b) => a.sequence_number - b.sequence_number,
  );
  const groups: TargetType[] = ["essential", "shouldHave", "niceToHave"];
  const mission = {
    id: missionId,
    title: missionTitle,
    statement: missionStatement,
  };

  return (
    <div className="space-y-6">
      {groups.map((type) => {
        const list = ordered.filter((t) => t.target_type === type);
        if (!list.length) return null;
        const progress = groupProgress(list);
        return (
          <motion.section
            key={type}
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ type: "spring", stiffness: 180, damping: 22 }}
            className="glass rounded-2xl p-4 sm:p-5"
          >
            <div className="mb-3 flex items-center justify-between gap-3">
              <span
                className={`rounded-full border px-2.5 py-0.5 text-[11px] font-semibold uppercase tracking-wider ${BADGE[type]}`}
              >
                {TARGET_LABELS[type]}
              </span>
              <span className="text-sm text-amber-soft">{progress}%</span>
            </div>
            <ProgressBar value={progress} className="mb-4" />
            <ul className="space-y-2">
              {list.map((t, i) => (
                <motion.li
                  key={t.id}
                  initial={{ opacity: 0, x: -8 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{
                    type: "spring",
                    stiffness: 200,
                    damping: 22,
                    delay: i * 0.04,
                  }}
                  className="flex items-start gap-3 rounded-xl bg-white/[0.02] px-3 py-2.5"
                >
                  <StatusDot status={t.status} />
                  <div className="min-w-0 flex-1">
                    <p
                      className={`text-sm font-medium ${
                        t.status === "complete"
                          ? "text-ink-dim line-through"
                          : "text-ink"
                      }`}
                    >
                      {t.title}
                    </p>
                    {t.description && (
                      <p className="mt-0.5 text-xs text-ink-dim">
                        {t.description}
                      </p>
                    )}
                  </div>
                  <button
                    type="button"
                    onClick={() => discussTarget(mission, t)}
                    title="Discuss in Chat"
                    aria-label={`Discuss ${t.title} in Chat`}
                    className="shrink-0 rounded-full border border-amber-glow/30 bg-amber-muted/60 px-2.5 py-1.5 text-sm font-semibold text-amber-bright transition hover:bg-amber-glow/25"
                  >
                    💬
                  </button>
                </motion.li>
              ))}
            </ul>
          </motion.section>
        );
      })}
    </div>
  );
}

function StatusDot({ status }: { status: string }) {
  const color =
    status === "complete"
      ? "bg-amber-bright shadow-amber-sm"
      : status === "in_progress"
        ? "bg-amber-glow animate-pulse-soft"
        : status === "blocked"
          ? "bg-red-400/80"
          : "bg-white/20";
  return (
    <span
      className={`mt-1.5 h-2 w-2 shrink-0 rounded-full ${color}`}
      aria-hidden
    />
  );
}
