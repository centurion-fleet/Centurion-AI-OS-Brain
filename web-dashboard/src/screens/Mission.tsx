import { Link, useParams } from "react-router-dom";
import { motion } from "framer-motion";
import { TargetSequence } from "../components/TargetSequence";
import { ActivityFeed } from "../components/ActivityFeed";
import { ProgressBar } from "../components/PrimaryCard";
import { useMissionDetail } from "../hooks/useLife";
import { useSSE } from "../hooks/useSSE";
import { missionProgress } from "../types/life";

export function Mission() {
  const { id } = useParams<{ id: string }>();
  const { mission, decisions, thoughts, loading, error } = useMissionDetail(id);
  const { thoughts: live } = useSSE();

  const merged = [
    ...live.filter((t) => !t.mission_id || t.mission_id === id),
    ...thoughts.filter((t) => !live.some((l) => l.id === t.id)),
  ];

  if (loading && !mission) {
    return (
      <div className="flex min-h-screen items-center justify-center text-ink-muted">
        Opening mission…
      </div>
    );
  }

  if (error || !mission) {
    return (
      <div className="mx-auto max-w-lg px-4 py-20 text-center">
        <p className="text-ink-muted">{error || "Mission not found"}</p>
        <Link to="/" className="mt-4 inline-block text-amber-soft">
          ← Back to Deck
        </Link>
      </div>
    );
  }

  const progress = missionProgress(mission);

  return (
    <div className="mx-auto min-h-screen max-w-3xl px-4 pb-20 pt-6 sm:px-6">
      <Link
        to="/"
        className="mb-6 inline-flex text-sm text-ink-dim transition hover:text-amber-soft"
      >
        ← Deck
      </Link>

      <motion.header
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ type: "spring", stiffness: 160, damping: 22 }}
      >
        <p className="text-[11px] font-semibold uppercase tracking-[0.16em] text-amber-soft">
          {mission.mission_type} · {mission.phase}
        </p>
        <h1 className="mt-2 font-display text-3xl font-semibold leading-tight tracking-tight text-ink sm:text-4xl">
          {mission.title}
        </h1>
        {mission.statement && (
          <p className="mt-3 text-lg text-ink-muted">{mission.statement}</p>
        )}
        <div className="mt-6">
          <div className="mb-2 flex justify-between text-sm text-ink-dim">
            <span>
              {mission.completed_target_count}/{mission.target_count} complete
            </span>
            <span className="text-amber-glow">{progress}%</span>
          </div>
          <ProgressBar value={progress} height="h-2.5" />
        </div>
        <button
          type="button"
          onClick={() => {
            const w = window as Window & {
              centurionDiscuss?: (p: Record<string, unknown>) => void;
            };
            if (typeof w.centurionDiscuss === "function") {
              w.centurionDiscuss({
                id: mission.id,
                title: mission.title,
                statement: mission.statement || mission.purpose,
                kickoff: `Let's talk about my mission: ${mission.title}`,
              });
            }
          }}
          className="mt-6 rounded-full border border-amber-glow/40 bg-amber-muted px-5 py-2.5 text-sm font-semibold text-amber-bright shadow-amber-sm transition hover:bg-amber-glow/25"
        >
          Discuss in Chat
        </button>
      </motion.header>

      <div className="mt-10 space-y-6">
        <EditorialBlock label="Situation" body={mission.situation} />
        <EditorialBlock label="WHY" body={mission.why} />
        <EditorialBlock label="Purpose" body={mission.purpose} />
      </div>

      <section className="mt-12">
        <h2 className="mb-4 text-[11px] font-semibold uppercase tracking-[0.16em] text-ink-dim">
          Target sequence
        </h2>
        <TargetSequence targets={mission.targets || []} />
      </section>

      <ActivityFeed thoughts={merged} title="Thought stream" />

      <section className="mt-8">
        <h2 className="mb-3 text-[11px] font-semibold uppercase tracking-[0.16em] text-ink-dim">
          Decisions
        </h2>
        <div className="glass rounded-2xl divide-y divide-white/5 overflow-hidden">
          {decisions.length === 0 ? (
            <p className="px-4 py-8 text-center text-sm text-ink-dim">
              No decisions logged yet.
            </p>
          ) : (
            decisions.map((d) => (
              <div key={d.id} className="px-4 py-3">
                <p className="text-sm font-medium text-ink">{d.title}</p>
                {d.chosen && (
                  <p className="mt-1 text-xs text-amber-soft">Chose: {d.chosen}</p>
                )}
                {d.context && (
                  <p className="mt-1 text-xs text-ink-dim">{d.context}</p>
                )}
              </div>
            ))
          )}
        </div>
      </section>
    </div>
  );
}

function EditorialBlock({ label, body }: { label: string; body: string }) {
  if (!body) return null;
  return (
    <motion.section
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ type: "spring", stiffness: 180, damping: 22 }}
      className="border-l-2 border-amber-glow/40 pl-4"
    >
      <h3 className="text-[11px] font-semibold uppercase tracking-[0.16em] text-amber-soft">
        {label}
      </h3>
      <p className="mt-2 text-base leading-relaxed text-ink-muted">{body}</p>
    </motion.section>
  );
}
