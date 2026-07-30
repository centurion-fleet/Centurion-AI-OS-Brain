import { Link, useParams } from "react-router-dom";
import { useState } from "react";
import { motion } from "framer-motion";
import { TargetSequence } from "../components/TargetSequence";
import { ActivityFeed } from "../components/ActivityFeed";
import { ProgressBar } from "../components/PrimaryCard";
import { useMissionDetail } from "../hooks/useLife";
import { useSSE } from "../hooks/useSSE";
import { useDeckVisible } from "../hooks/useDeckVisible";
import { missionProgress } from "../types/life";
import { bridgeCall } from "../hooks/useBridge";

export function Mission() {
  const { id } = useParams<{ id: string }>();
  const deckVisible = useDeckVisible();
  const { mission, decisions, thoughts, loading, error, refresh } =
    useMissionDetail(id);
  const { thoughts: live } = useSSE({ enabled: deckVisible });
  const [primaryBusy, setPrimaryBusy] = useState(false);
  const [logOpen, setLogOpen] = useState(false);
  const [logTitle, setLogTitle] = useState("");
  const [logChosen, setLogChosen] = useState("");
  const [logContext, setLogContext] = useState("");
  const [logBusy, setLogBusy] = useState(false);
  const [logError, setLogError] = useState<string | null>(null);

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
          ← Back to Focus
        </Link>
      </div>
    );
  }

  const progress = missionProgress(mission);
  const missionId = mission.id;
  const missionTitle = mission.title;

  function discussDecision(d: {
    id: string;
    title: string;
    chosen?: string;
    context?: string;
    target_id?: string | null;
  }) {
    const w = window as Window & {
      centurionDiscuss?: (p: Record<string, unknown>) => void;
    };
    if (typeof w.centurionDiscuss !== "function") return;
    w.centurionDiscuss({
      kind: "decision",
      id: d.id,
      title: d.title,
      chosen: d.chosen || "",
      context: d.context || "",
      mission_id: missionId,
      mission_title: missionTitle,
      target_id: d.target_id || undefined,
      kickoff: `Let's revisit this decision: ${d.title}${
        d.chosen ? ` (chose: ${d.chosen})` : ""
      }`,
    });
  }

  async function submitDecision() {
    const title = logTitle.trim();
    if (!title) {
      setLogError("Title is required");
      return;
    }
    setLogBusy(true);
    setLogError(null);
    try {
      await bridgeCall("life_decision_log", {
        decision: {
          mission_id: missionId,
          title,
          chosen: logChosen.trim(),
          context: logContext.trim(),
        },
      });
      setLogTitle("");
      setLogChosen("");
      setLogContext("");
      setLogOpen(false);
      await refresh();
    } catch (e) {
      setLogError(e instanceof Error ? e.message : "Could not log decision");
    } finally {
      setLogBusy(false);
    }
  }

  return (
    <div className="mx-auto min-h-screen max-w-3xl px-4 pb-20 pt-6 sm:px-6">
      <Link
        to="/"
        className="mb-6 inline-flex text-sm text-ink-dim transition hover:text-amber-soft"
      >
        ← Focus
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
        <div className="mt-6 flex flex-wrap gap-3">
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
            className="rounded-full border border-amber-glow/40 bg-amber-muted px-5 py-2.5 text-sm font-semibold text-amber-bright shadow-amber-sm transition hover:bg-amber-glow/25"
          >
            Discuss in Chat
          </button>
          {mission.mission_type !== "primary" && (
            <button
              type="button"
              disabled={primaryBusy}
              onClick={() => {
                void (async () => {
                  setPrimaryBusy(true);
                  try {
                    await bridgeCall("life_stack_set_primary", {
                      mission_id: mission.id,
                    });
                    await refresh();
                  } finally {
                    setPrimaryBusy(false);
                  }
                })();
              }}
              className="rounded-full border border-ink-dim/30 bg-glass px-5 py-2.5 text-sm font-semibold text-ink transition hover:border-amber-glow/40 hover:text-amber-bright disabled:opacity-50"
            >
              {primaryBusy ? "Setting…" : "Set as Primary"}
            </button>
          )}
        </div>
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
        <TargetSequence
          targets={mission.targets || []}
          missionId={mission.id}
          missionTitle={mission.title}
          missionStatement={mission.statement || mission.purpose}
        />
      </section>

      <ActivityFeed thoughts={merged} title="Thought stream" />

      <section className="mt-8">
        <div className="mb-3 flex items-center justify-between gap-3">
          <h2 className="text-[11px] font-semibold uppercase tracking-[0.16em] text-ink-dim">
            Decisions
          </h2>
          <button
            type="button"
            onClick={() => setLogOpen((o) => !o)}
            className="rounded-full border border-amber-glow/30 bg-amber-muted/50 px-3 py-1 text-[11px] font-semibold text-amber-bright transition hover:bg-amber-glow/25"
          >
            {logOpen ? "Cancel" : "Log a decision"}
          </button>
        </div>

        {logOpen && (
          <div className="glass mb-3 space-y-3 rounded-2xl p-4">
            <input
              value={logTitle}
              onChange={(e) => setLogTitle(e.target.value)}
              placeholder="Decision title"
              className="w-full rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-sm text-ink outline-none placeholder:text-ink-dim focus:border-amber-glow/40"
            />
            <input
              value={logChosen}
              onChange={(e) => setLogChosen(e.target.value)}
              placeholder="What you chose (optional)"
              className="w-full rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-sm text-ink outline-none placeholder:text-ink-dim focus:border-amber-glow/40"
            />
            <textarea
              value={logContext}
              onChange={(e) => setLogContext(e.target.value)}
              placeholder="Context (optional)"
              rows={2}
              className="w-full resize-none rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-sm text-ink outline-none placeholder:text-ink-dim focus:border-amber-glow/40"
            />
            {logError && <p className="text-sm text-amber-soft">{logError}</p>}
            <button
              type="button"
              disabled={logBusy}
              onClick={() => void submitDecision()}
              className="rounded-full bg-amber-gradient px-5 py-2 text-sm font-semibold text-canvas shadow-amber disabled:opacity-50"
            >
              {logBusy ? "Saving…" : "Save decision"}
            </button>
          </div>
        )}

        <div className="glass rounded-2xl divide-y divide-white/5 overflow-hidden">
          {decisions.length === 0 ? (
            <p className="px-4 py-8 text-center text-sm text-ink-dim">
              No decisions logged yet.
            </p>
          ) : (
            decisions.map((d) => (
              <div
                key={d.id}
                className="flex items-start gap-3 px-4 py-3"
              >
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-medium text-ink">{d.title}</p>
                  {d.chosen && (
                    <p className="mt-1 text-xs text-amber-soft">
                      Chose: {d.chosen}
                    </p>
                  )}
                  {d.context && (
                    <p className="mt-1 text-xs text-ink-dim">{d.context}</p>
                  )}
                </div>
                <button
                  type="button"
                  title="Discuss in Chat"
                  aria-label={`Discuss decision ${d.title}`}
                  onClick={() => discussDecision(d)}
                  className="shrink-0 rounded-full border border-amber-glow/30 bg-amber-muted/60 px-2.5 py-1.5 text-sm font-semibold text-amber-bright transition hover:bg-amber-glow/25"
                >
                  💬
                </button>
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
