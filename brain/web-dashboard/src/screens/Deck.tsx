import { Link, useNavigate } from "react-router-dom";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { ReactNode } from "react";
import { m as motion, useReducedMotion } from "framer-motion";
import { PrimaryCard } from "../components/PrimaryCard";
import { DocumentSearch } from "../components/DocumentSearch";
import { SupportingRow } from "../components/SupportingRow";
import { DreamList } from "../components/DreamList";
import { ActivityFeed } from "../components/ActivityFeed";
import { PulseIndicators } from "../components/PulseIndicators";
import { useMissionStack } from "../hooks/useLife";
import { useSSE } from "../hooks/useSSE";
import { useDeckVisible } from "../hooks/useDeckVisible";
import { useOpenDecisions } from "../hooks/useOpenDecisions";
import { usePendingPlans } from "../hooks/usePendingPlans";
import { bridgeCall } from "../hooks/useBridge";
import { prefetchMissionChunk } from "../prefetch";
import { AttentionBanner } from "../components/AttentionBanner";
import { DocumentsRow } from "../components/DocumentsRow";
import { missionProgress } from "../types/life";
import type { Mission, MissionTarget } from "../types/life";

/**
 * Stillpoint — the Conjunction instrument for one pair.
 *
 * Conjunction answers "what needs me across my projects": two Centurions, a
 * project switch, membership as the boundary. Stillpoint answers a different
 * question, and that difference is the whole reason it exists separately:
 *
 *   am I working on the right thing at all?
 *
 * So the shape is Conjunction's — the owner at a still centre, registers for
 * what is delivered, moving, agreed and waiting, and nothing on screen but the
 * owner's next move — with two changes:
 *
 *   1. The centre is the owner's stated PURPOSE, not "you, here, in this
 *      project". A purpose that is never written drifts toward whatever was
 *      loudest, so an unwritten centre says so instead of guessing.
 *   2. A register Conjunction cannot have: ALIGNED. What is moving that traces
 *      to the purpose, what is moving with no purpose attached at all, and —
 *      the one a project view can never show — what the purpose asks for that
 *      nothing is moving on.
 *
 * What is deliberately absent: any project switch, any membership or
 * permissions, any second accent, any pairing. There is one life and one ring.
 * Settings live in the Brain's You tab, never on the phone.
 */

type RegisterProps = {
  label: string;
  note?: string;
  aside?: ReactNode;
  shout?: boolean;
  children: ReactNode;
};

function Register({ label, note, aside, shout = false, children }: RegisterProps) {
  return (
    <section className="mt-8">
      <div className="mb-3 flex items-baseline justify-between gap-4 px-1">
        <h2
          className={`text-[11px] font-semibold uppercase tracking-[0.16em] ${
            shout ? "text-amber-soft" : "text-ink-dim"
          }`}
        >
          {label}
          {note && (
            <span className="ml-2 font-normal normal-case tracking-normal text-ink-muted">
              {note}
            </span>
          )}
        </h2>
        {aside}
      </div>
      {children}
    </section>
  );
}

function Empty({ children }: { children: ReactNode }) {
  return <p className="px-1 text-sm text-ink-muted">{children}</p>;
}

function WorkItem({
  title,
  meta,
  onOpen,
}: {
  title: string;
  meta: string;
  onOpen?: () => void;
}) {
  const body = (
    <>
      <span className="text-sm text-ink">{title}</span>
      <span className="mt-1 block text-[11px] uppercase tracking-[0.14em] text-ink-dim">
        {meta}
      </span>
    </>
  );
  if (!onOpen) {
    return <div className="surface rounded-xl px-3 py-2.5">{body}</div>;
  }
  return (
    <button
      type="button"
      onClick={onOpen}
      className="surface w-full rounded-xl px-3 py-2.5 text-left transition hover:border-amber-glow/30"
    >
      {body}
    </button>
  );
}

export function Deck() {
  const navigate = useNavigate();
  const deckVisible = useDeckVisible();
  const reduce = useReducedMotion();
  const [findOpen, setFindOpen] = useState(false);
  const { stack, loading, error, refresh } = useMissionStack(20_000, deckVisible);
  const { open: openDecisions, refresh: refreshOpenDecisions } =
    useOpenDecisions(deckVisible);
  const { plans: pendingPlans, refresh: refreshPendingPlans } =
    usePendingPlans(deckVisible);
  const { thoughts, connected } = useSSE({
    enabled: deckVisible,
    limit: 32,
    onDataVersion: () => {
      void refresh();
      void refreshOpenDecisions();
      void refreshPendingPlans();
    },
  });
  const autoDiscoveryDone = useRef(false);

  const primary = stack?.primary ?? null;
  const supporting = stack?.supporting ?? [];
  const dreams = stack?.dreams ?? [];
  const empty = !loading && !primary && supporting.length === 0;

  const missions = useMemo<Mission[]>(
    () => [primary, ...supporting].filter(Boolean) as Mission[],
    [primary, supporting],
  );

  // ---- the registers -------------------------------------------------------
  const inHand = useMemo(
    () =>
      missions
        .flatMap((m) =>
          m.targets
            .filter((t) => t.status === "in_progress")
            .map((t) => ({ target: t, mission: m })),
        )
        .slice(0, 8),
    [missions],
  );

  const upcoming = useMemo<MissionTarget[]>(
    () =>
      [...(primary?.targets ?? [])]
        .filter((t) => t.status === "not_started")
        .sort((a, b) => a.sequence_number - b.sequence_number)
        .slice(0, 8),
    [primary],
  );

  const struck = useMemo(
    () =>
      missions
        .flatMap((m) =>
          m.targets
            .filter((t) => t.status === "complete")
            .map((t) => ({ target: t, mission: m })),
        )
        .sort((a, b) =>
          String(b.target.completed_at ?? "").localeCompare(
            String(a.target.completed_at ?? ""),
          ),
        )
        .slice(0, 8),
    [missions],
  );

  /**
   * ALIGNED — the purpose check, and the only register Conjunction has no
   * equivalent for.
   *
   * The rule that keeps it honest: it may only count work that traces to the
   * stated purpose. Busy is not evidence.
   *
   * Two traps this register must not fall into, both found by checking the
   * live record rather than trusting the shape of it:
   *
   *   - Work sitting on a supporting mission is NOT untethered. Supporting
   *     missions are part of the stated stack, so they trace by definition.
   *     Only work with no mission at all is untethered, which is why this
   *     counts decisions and plans and never targets.
   *   - Unlinked is NOT untethered. On the live record, plans and decisions
   *     carry no mission link at all — every one of them. Counting those as
   *     "no purpose attached" would be literally true and badly misleading:
   *     they serve the primary mission perfectly well, the record just does
   *     not say so. So the register counts what the record can actually
   *     support, and says plainly when it cannot judge the rest.
   */
  const aligned = useMemo(() => {
    const onPurpose = missions
      .filter((m) => m.id === primary?.id)
      .flatMap((m) =>
        m.targets.filter(
          (t) => t.status === "in_progress" || t.status === "complete",
        ),
      ).length;

    const pending = openDecisions.length + pendingPlans.length;
    const unlinked =
      openDecisions.filter((d) => !d.mission_id).length +
      pendingPlans.filter((p) => !(p.related_mission ?? p.relatedMission)).length;

    // Only judge linkage when the record can support a judgement: if nothing
    // links, the absence is a record gap, not a fact about the work.
    const canJudgeLinkage = pending > 0 && unlinked < pending;

    const idleMust = (primary?.targets ?? []).filter(
      (t) => t.target_type === "essential" && t.status === "not_started",
    );

    return { onPurpose, unlinked, pending, canJudgeLinkage, idleMust };
  }, [missions, primary, openDecisions, pendingPlans]);

  const purpose =
    primary?.statement?.trim() || primary?.purpose?.trim() || primary?.why?.trim() || "";

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

  const openSupporting = useCallback(
    (id: string) => {
      const m = supporting.find((x) => x.id === id);
      navigate(`/mission/${id}`, m ? { state: { mission: m } } : undefined);
    },
    [navigate, supporting],
  );

  return (
    <div className="mx-auto min-h-screen max-w-7xl px-4 pb-20 pt-8 sm:px-6 sm:pt-10">
      <header className="mb-2 flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="font-display text-3xl font-medium tracking-tight text-ink sm:text-4xl">
            Centurion
          </p>
          <p className="mt-1 text-[11px] font-semibold uppercase tracking-[0.18em] text-amber-soft">
            Stillpoint
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
          Stillpoint is paused while another Brain tab is active.
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
            className="mt-8 inline-flex rounded-full bg-accent px-6 py-3 text-sm font-semibold text-[var(--on-accent)] transition hover:brightness-110"
          >
            Begin Discovery
          </Link>
        </motion.div>
      ) : (
        <>
          {/* ---- the still centre: what this whole life is for --------------- */}
          <div className="mt-8">
            {primary ? (
              <PrimaryCard
                hero
                mission={primary}
                latestThought={latestThought}
                onOpen={openPrimary}
                onPrefetch={prefetchMissionChunk}
              />
            ) : (
              <div className="surface rounded-2xl px-5 py-4">
                <p className="text-[11px] font-semibold uppercase tracking-[0.16em] text-amber-soft">
                  Purpose
                </p>
                <p className="mt-2 text-ink-muted">
                  No primary mission crowned yet. Focus cannot tell you whether
                  you are working on the right thing until the right thing is
                  named.
                </p>
              </div>
            )}

            {primary && !purpose && (
              <p className="mt-3 px-1 text-sm text-amber-soft">
                Your purpose is not written yet. Until it is, ALIGNED can only
                report activity, not alignment.
              </p>
            )}
          </div>

          {/* ---- 01 waiting on you: the only register allowed to shout ------ */}
          <Register
            label="Waiting on you"
            note="Proceed starts the work · Discuss opens a thread · Hold keeps it visible"
            shout
          >
            <AttentionBanner
              decisions={openDecisions}
              plans={pendingPlans}
              onResolved={() => {
                void refreshOpenDecisions();
                void refreshPendingPlans();
              }}
            />
          </Register>

          {/* ---- 02 aligned: the purpose check ------------------------------ */}
          <Register label="Aligned" note="does the work trace to your purpose">
            {!primary ? (
              <Empty>No purpose named, so nothing can be measured against it.</Empty>
            ) : !purpose ? (
              <Empty>
                Purpose unwritten. Write it in Discovery and this register starts
                counting.
              </Empty>
            ) : aligned.onPurpose === 0 &&
              aligned.idleMust.length === 0 &&
              aligned.pending === 0 ? (
              <Empty>Nothing is moving yet, so there is nothing to weigh.</Empty>
            ) : (
              <div className="space-y-3">
                <div className="surface rounded-xl px-3 py-2.5">
                  <span className="text-sm text-ink">
                    {aligned.onPurpose === 1
                      ? "1 piece of work on your purpose"
                      : `${aligned.onPurpose} pieces of work on your purpose`}
                  </span>
                  <span className="mt-1 block text-[11px] uppercase tracking-[0.14em] text-ink-dim">
                    moving or delivered, on {primary.title}
                  </span>
                </div>

                {aligned.pending > 0 &&
                  (aligned.canJudgeLinkage ? (
                    <div className="surface rounded-xl px-3 py-2.5">
                      <span className="text-sm text-ink">
                        {aligned.unlinked === 1
                          ? "1 open item carries no mission link"
                          : `${aligned.unlinked} open items carry no mission link`}
                      </span>
                      <span className="mt-1 block text-[11px] uppercase tracking-[0.14em] text-ink-dim">
                        real work the record does not attach to your purpose
                      </span>
                    </div>
                  ) : (
                    <div className="surface rounded-xl px-3 py-2.5">
                      <span className="text-sm text-ink">
                        {aligned.pending === 1
                          ? "1 open item carries no mission link"
                          : `${aligned.pending} open items carry no mission link`}
                      </span>
                      <span className="mt-1 block text-[11px] uppercase tracking-[0.14em] text-ink-dim">
                        unlinked is not untethered — nothing links, so the record
                        cannot say which of these serve your purpose
                      </span>
                    </div>
                  ))}

                {aligned.idleMust.length > 0 && (
                  <div className="surface rounded-xl border-amber-glow/25 px-3 py-2.5">
                    <span className="text-sm text-amber-soft">
                      {aligned.idleMust.length === 1
                        ? "1 Must Do nothing is moving on"
                        : `${aligned.idleMust.length} Must Dos nothing is moving on`}
                    </span>
                    <span className="mt-1 block text-[11px] uppercase tracking-[0.14em] text-ink-dim">
                      {aligned.idleMust
                        .slice(0, 2)
                        .map((t) => t.title)
                        .join(" · ")}
                    </span>
                  </div>
                )}

                {aligned.canJudgeLinkage && aligned.idleMust.length === 0 && (
                  <p className="px-1 text-sm text-ink-muted">
                    Everything moving traces to your purpose.
                  </p>
                )}
              </div>
            )}
          </Register>

          {/* ---- 03 in hand ------------------------------------------------- */}
          <Register
            label="In hand"
            note="what is moving now"
            aside={
              primary ? (
                <span className="text-[11px] uppercase tracking-[0.14em] text-ink-dim">
                  {missionProgress(primary)}% of {primary.title}
                </span>
              ) : undefined
            }
          >
            {inHand.length === 0 ? (
              <Empty>Nothing picked up yet.</Empty>
            ) : (
              <div className="space-y-2">
                {inHand.map(({ target, mission }) => (
                  <WorkItem
                    key={target.id}
                    title={target.title}
                    meta={`${mission.title}`}
                    onOpen={() => openSupporting(mission.id)}
                  />
                ))}
              </div>
            )}
          </Register>

          {/* ---- 04 next: the agreed order, numbered ------------------------ */}
          <Register label="Next" note="the agreed order">
            {upcoming.length === 0 ? (
              <Empty>Nothing queued behind the work in hand.</Empty>
            ) : (
              <ol className="space-y-2">
                {upcoming.map((t) => (
                  <li key={t.id} className="surface rounded-xl px-3 py-2.5">
                    <span className="mr-2 text-[11px] font-semibold uppercase tracking-[0.14em] text-amber-soft">
                      {String(t.sequence_number).padStart(2, "0")}
                    </span>
                    <span className="text-sm text-ink">{t.title}</span>
                    <span className="mt-1 block text-[11px] uppercase tracking-[0.14em] text-ink-dim">
                      {t.target_type === "essential"
                        ? "Must Do"
                        : t.target_type === "shouldHave"
                          ? "Should Do"
                          : "Nice to Do"}
                      {t.sequence_warning ? ` · ${t.sequence_warning}` : ""}
                    </span>
                  </li>
                ))}
              </ol>
            )}
          </Register>

          {/* ---- 05 struck: delivered and verified -------------------------- */}
          <Register label="Struck" note="delivered and verified — a bead seals on work, never on a claim">
            {struck.length === 0 ? (
              <Empty>Nothing sealed yet.</Empty>
            ) : (
              <div className="space-y-2">
                {struck.map(({ target, mission }) => (
                  <WorkItem
                    key={target.id}
                    title={target.title}
                    meta={`${mission.title}${
                      target.completed_at
                        ? ` · ${String(target.completed_at).slice(0, 10)}`
                        : ""
                    }`}
                  />
                ))}
              </div>
            )}
          </Register>

          {/* ---- below the fold: where the purpose comes from --------------- */}
          <SupportingRow
            missions={supporting}
            onOpen={openSupporting}
            onMakePrimary={(id) => void makePrimary(id)}
            onPrefetch={prefetchMissionChunk}
          />

          <DreamList dreams={dreams} onPromote={promoteDream} />

          <DocumentsRow enabled={deckVisible} />

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
          {empty && (
            <Link to="/discovery" className="hover:text-amber-soft">
              Discovery
            </Link>
          )}
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
