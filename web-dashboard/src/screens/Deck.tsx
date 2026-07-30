import { Link, useNavigate } from "react-router-dom";
import { useCallback, useEffect, useRef, useState } from "react";
import { m as motion, useReducedMotion } from "framer-motion";
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
import { prefetchMissionChunk } from "../prefetch";

export function Deck() {
  const navigate = useNavigate();
  const deckVisible = useDeckVisible();
  const reduce = useReducedMotion();
  const [findOpen, setFindOpen] = useState(false);
  const { stack, loading, error, refresh } = useMissionStack(20_000, deckVisible);
  const { thoughts, connected } = useSSE({
    enabled: deckVisible,
    limit: 32,
    onDataVersion: () => {
      void refresh();
    },
  });
  const autoDiscoveryDone = useRef(false);

  const primary = stack?.primary ?? null;
  const supporting = stack?.supporting ?? [];
  const dreams = stack?.dreams ?? [];
  const empty = !loading && !primary && supporting.length === 0;

  const { documents: primaryDocs, count: primaryDocCount } = usePrimaryDocuments(
    primary?.id,
    deckVisible && !!primary,
    60_000,
  );

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

  const promoteDream = useCallback(
    async (dreamId: string) => {
      try {
        await bridgeCall("life_dream_promote", { dream_id: dreamId });
        await refresh();
      } catch {
        /* surface via refresh error next cycle */
      }
    },
    [refresh],
  );

  const makePrimary = useCallback(
    async (missionId: string) => {
      try {
        await bridgeCall("life_stack_set_primary", { mission_id: missionId });
        await refresh();
      } catch {
        /* surface via refresh error next cycle */
      }
    },
    [refresh],
  );

  const openPrimary = useCallback(() => {
    if (!primary) return;
    navigate(`/mission/${primary.id}`, { state: { mission: primary } });
  }, [navigate, primary]);

  const discussPrimary = useCallback(() => {
    if (!primary) return;
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
  }, [primary]);

  const openSupporting = useCallback(
    (id: string) => {
      const m = supporting.find((x) => x.id === id);
      navigate(`/mission/${id}`, m ? { state: { mission: m } } : undefined);
    },
    [navigate, supporting],
  );

  return (
    <div className="mx-auto min-h-screen max-w-5xl px-4 pb-20 pt-8 sm:px-6 sm:pt-10">
      {/* First viewport: brand + Primary as one composition */}
      <header className="mb-2 flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="font-display text-3xl font-medium tracking-tight text-ink sm:text-4xl">
            Centurion
          </p>
          <p className="mt-1 text-[11px] font-semibold uppercase tracking-[0.18em] text-amber-soft">
            Focus
          </p>
        </div>
        <div className="flex items-center gap-3 pb-1">
          <PulseIndicators connected={connected} loading={loading} />
          <Link
            to="/tv"
            className="text-sm font-semibold text-ink-dim transition hover:text-amber-soft"
          >
            TV Mode
          </Link>
        </div>
      </header>

      {error && (
        <div className="surface mt-6 rounded-2xl border-amber-glow/20 px-4 py-3 text-sm text-amber-soft">
          Couldn’t reach the Brain bridge: {error}
        </div>
      )}

      {loading && !stack ? (
        <div className="mt-16 animate-pulse-soft text-center text-ink-dim">
          Opening your deck…
        </div>
      ) : !deckVisible && !stack ? (
        <div className="mt-16 text-center text-ink-dim">
          Focus is paused while another Brain tab is active.
        </div>
      ) : empty ? (
        <motion.div
          initial={reduce ? false : { opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={reduce ? { duration: 0 } : { duration: 0.35 }}
          className="mt-16 max-w-lg"
        >
          <p className="font-display text-3xl font-medium text-ink sm:text-4xl">
            Nothing on the board yet
          </p>
          <p className="mt-3 text-ink-muted">
            Find what you’re building toward — a calm ceremony to shape your
            primary mission.
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
          {primary ? (
            <PrimaryCard
              hero
              mission={primary}
              latestThought={latestThought}
              documents={primaryDocs}
              documentCount={primaryDocCount}
              onOpen={openPrimary}
              onDiscuss={discussPrimary}
              onPrefetch={prefetchMissionChunk}
            />
          ) : (
            <div className="mt-10 text-ink-muted">
              No primary mission crowned yet.{" "}
              <Link to="/discovery" className="text-amber-soft underline">
                Discover one
              </Link>
            </div>
          )}

          {/* Below the fold */}
          <SupportingRow
            missions={supporting}
            onOpen={openSupporting}
            onMakePrimary={(id) => void makePrimary(id)}
            onPrefetch={prefetchMissionChunk}
          />

          <DreamList dreams={dreams} onPromote={promoteDream} />

          <ActivityFeed thoughts={thoughts} title="Live pulse" max={32} />
        </>
      )}

      <nav className="mt-14 flex w-full flex-col items-center gap-5">
        {findOpen && (
          <div className="w-full max-w-2xl">
            <DocumentSearch
              enabled={deckVisible}
              defaultOpen
              hideToggle
              onClose={() => setFindOpen(false)}
            />
          </div>
        )}
        <div className="flex justify-center gap-6 text-sm text-ink-dim">
          <Link to="/discovery" className="hover:text-amber-soft">
            Discovery
          </Link>
          <button
            type="button"
            onClick={() => setFindOpen((o) => !o)}
            className={
              findOpen
                ? "text-amber-soft"
                : "hover:text-amber-soft"
            }
          >
            Find documents
          </button>
        </div>
      </nav>
    </div>
  );
}
