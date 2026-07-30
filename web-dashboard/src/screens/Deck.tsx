import { Link, useNavigate } from "react-router-dom";
import { useEffect, useRef } from "react";
import { motion } from "framer-motion";
import { PrimaryCard } from "../components/PrimaryCard";
import { DocumentSearch } from "../components/DocumentSearch";
import { SupportingRow } from "../components/SupportingRow";
import { DreamList } from "../components/DreamList";
import { ActivityFeed } from "../components/ActivityFeed";
import { PulseIndicators } from "../components/PulseIndicators";
import { useMissionStack, usePrimaryDocuments } from "../hooks/useLife";
import { useSSE } from "../hooks/useSSE";
import { useDeckVisible } from "../hooks/useDeckVisible";
import { bridgeCall } from "../hooks/useBridge";

export function Deck() {
  const navigate = useNavigate();
  const deckVisible = useDeckVisible();
  const { stack, loading, error, refresh } = useMissionStack(20_000, deckVisible);
  const { thoughts, connected } = useSSE({ enabled: deckVisible });
  const autoDiscoveryDone = useRef(false);

  const primary = stack?.primary ?? null;
  const supporting = stack?.supporting ?? [];
  const dreams = stack?.dreams ?? [];
  const empty = !loading && !primary && supporting.length === 0;

  const { documents: primaryDocs, count: primaryDocCount } = usePrimaryDocuments(
    primary?.id,
    deckVisible && !!primary,
  );

  // Guided first-run: empty board → Discovery once per session (don't fight Back).
  useEffect(() => {
    if (!empty || !deckVisible || autoDiscoveryDone.current) return;
    if (sessionStorage.getItem("centurion_discovery_auto") === "1") {
      autoDiscoveryDone.current = true;
      return;
    }
    autoDiscoveryDone.current = true;
    sessionStorage.setItem("centurion_discovery_auto", "1");
    navigate("/discovery", { replace: true });
  }, [empty, deckVisible, navigate]);

  const latestThought =
    thoughts.find((t) => !primary || !t.mission_id || t.mission_id === primary.id)
      ?.summary ?? thoughts[0]?.summary;

  async function promoteDream(dreamId: string) {
    try {
      await bridgeCall("life_dream_promote", { dream_id: dreamId });
      await refresh();
    } catch {
      /* surface via refresh error next cycle */
    }
  }

  async function makePrimary(missionId: string) {
    try {
      await bridgeCall("life_stack_set_primary", { mission_id: missionId });
      await refresh();
    } catch {
      /* surface via refresh error next cycle */
    }
  }

  return (
    <div className="mx-auto min-h-screen max-w-5xl px-4 pb-16 pt-6 sm:px-6 sm:pt-8">
      <header className="mb-8 flex flex-wrap items-center justify-between gap-4">
        <div>
          <p className="text-[11px] font-semibold uppercase tracking-[0.18em] text-amber-soft">
            Centurion
          </p>
          <h1 className="font-display text-2xl font-semibold tracking-tight text-ink sm:text-3xl">
            Focus
          </h1>
        </div>
        <div className="flex items-center gap-3">
          <PulseIndicators connected={connected} loading={loading} />
          <Link
            to="/tv"
            className="rounded-full border border-amber-glow/35 bg-amber-muted px-4 py-2 text-sm font-semibold text-amber-bright shadow-amber-sm transition hover:bg-amber-glow/25"
          >
            TV Mode
          </Link>
        </div>
      </header>

      {error && (
        <div className="glass mb-6 rounded-2xl border-amber-glow/20 px-4 py-3 text-sm text-amber-soft">
          Couldn’t reach the Brain bridge: {error}
        </div>
      )}

      {loading && !stack ? (
        <div className="glass-strong animate-pulse-soft rounded-3xl px-6 py-20 text-center text-ink-dim">
          Opening your deck…
        </div>
      ) : !deckVisible && !stack ? (
        <div className="glass-strong rounded-3xl px-6 py-20 text-center text-ink-dim">
          Focus is paused while another Brain tab is active.
        </div>
      ) : empty ? (
        <motion.div
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ type: "spring", stiffness: 160, damping: 20 }}
          className="glass-strong rounded-3xl px-6 py-14 text-center shadow-glass sm:px-10"
        >
          <p className="font-display text-2xl font-semibold text-ink sm:text-3xl">
            Nothing on the board yet
          </p>
          <p className="mx-auto mt-3 max-w-md text-ink-muted">
            Let’s find what you’re building toward — a calm ceremony to shape
            your primary mission.
          </p>
          <Link
            to="/discovery"
            className="mt-8 inline-flex rounded-full bg-amber-gradient px-6 py-3 text-sm font-semibold text-canvas shadow-amber transition hover:brightness-110"
          >
            Begin Discovery
          </Link>
        </motion.div>
      ) : (
        <>
          <DocumentSearch
            enabled={deckVisible}
            preferredMissionId={primary?.id}
          />

          {primary ? (
            <PrimaryCard
              mission={primary}
              latestThought={latestThought}
              documents={primaryDocs}
              documentCount={primaryDocCount}
              onOpen={() => navigate(`/mission/${primary.id}`)}
              onDiscuss={() => {
                const w = window as Window & {
                  centurionDiscuss?: (p: Record<string, unknown>) => void;
                };
                if (typeof w.centurionDiscuss !== "function") return;
                w.centurionDiscuss({
                  id: primary.id,
                  title: primary.title,
                  statement: primary.statement || primary.purpose,
                  kickoff: `Let's talk about my mission: ${primary.title}`,
                });
              }}
            />
          ) : (
            <div className="glass rounded-3xl p-6 text-center text-ink-muted">
              No primary mission crowned yet.{" "}
              <Link to="/discovery" className="text-amber-soft underline">
                Discover one
              </Link>
            </div>
          )}

          <SupportingRow
            missions={supporting}
            onOpen={(id) => navigate(`/mission/${id}`)}
            onMakePrimary={(id) => void makePrimary(id)}
          />

          <DreamList dreams={dreams} onPromote={promoteDream} />

          <ActivityFeed thoughts={thoughts} title="Live pulse" />
        </>
      )}

      <nav className="mt-10 flex justify-center gap-4 text-sm text-ink-dim">
        <Link to="/discovery" className="hover:text-amber-soft">
          Discovery
        </Link>
      </nav>
    </div>
  );
}
