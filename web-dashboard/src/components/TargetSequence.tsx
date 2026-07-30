import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import type { MissionTarget, TargetStatus, TargetType } from "../types/life";
import { TARGET_LABELS } from "../types/life";
import { ProgressBar } from "./PrimaryCard";
import { bridgeCall } from "../hooks/useBridge";

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
  onTargetsChanged?: () => void | Promise<void>;
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
  onTargetsChanged,
}: TargetSequenceProps) {
  const [local, setLocal] = useState(targets);
  const [busyId, setBusyId] = useState<string | null>(null);

  useEffect(() => {
    setLocal(targets);
  }, [targets]);

  const ordered = [...local].sort(
    (a, b) => a.sequence_number - b.sequence_number,
  );
  const groups: TargetType[] = ["essential", "shouldHave", "niceToHave"];
  const mission = {
    id: missionId,
    title: missionTitle,
    statement: missionStatement,
  };

  async function toggleComplete(t: MissionTarget) {
    if (busyId) return;
    const nextStatus: TargetStatus =
      t.status === "complete" ? "in_progress" : "complete";
    const prev = local;
    setLocal((rows) =>
      rows.map((r) => (r.id === t.id ? { ...r, status: nextStatus } : r)),
    );
    setBusyId(t.id);
    try {
      await bridgeCall("life_target_put", {
        target: {
          id: t.id,
          mission_id: missionId,
          title: t.title,
          description: t.description || "",
          target_type: t.target_type,
          status: nextStatus,
          sequence_number: t.sequence_number,
        },
      });
      await bridgeCall("life_thought_post", {
        thought: {
          mission_id: missionId,
          target_id: t.id,
          activity_type: "target_update",
          summary:
            nextStatus === "complete"
              ? `Completed: ${t.title}`
              : `Reopened: ${t.title}`,
          detail: "",
        },
      });
      await onTargetsChanged?.();
    } catch {
      setLocal(prev);
    } finally {
      setBusyId(null);
    }
  }

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
                  <StatusDot
                    status={t.status}
                    busy={busyId === t.id}
                    onToggle={() => void toggleComplete(t)}
                    label={t.title}
                  />
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
                    onClick={(e) => {
                      e.stopPropagation();
                      discussTarget(mission, t);
                    }}
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

function StatusDot({
  status,
  busy,
  onToggle,
  label,
}: {
  status: string;
  busy?: boolean;
  onToggle: () => void;
  label: string;
}) {
  const color =
    status === "complete"
      ? "bg-amber-bright shadow-amber-sm"
      : status === "in_progress"
        ? "bg-amber-glow animate-pulse-soft"
        : status === "blocked"
          ? "bg-red-400/80"
          : "bg-white/20";
  const action =
    status === "complete" ? `Reopen ${label}` : `Mark ${label} complete`;
  return (
    <button
      type="button"
      disabled={busy}
      onClick={(e) => {
        e.stopPropagation();
        onToggle();
      }}
      title={action}
      aria-label={action}
      className={`mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full border border-white/10 transition hover:border-amber-glow/50 disabled:opacity-50`}
    >
      <span className={`h-2.5 w-2.5 rounded-full ${color}`} aria-hidden />
    </button>
  );
}
