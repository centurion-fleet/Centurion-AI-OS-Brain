import { Link, useLocation, useParams, useSearchParams } from "react-router-dom";
import { FocusBackBar } from "../components/FocusBackBar";
import { useEffect, useMemo, useRef, useState } from "react";
import { m as motion } from "framer-motion";
import { TargetSequence } from "../components/TargetSequence";
import { ActivityFeed } from "../components/ActivityFeed";
import { ProgressBar } from "../components/PrimaryCard";
import { PhaseStrip } from "../components/PhaseStrip";
import { useMissionDetail } from "../hooks/useLife";
import { useSSE } from "../hooks/useSSE";
import { useDeckVisible } from "../hooks/useDeckVisible";
import { isOpenDecision, resolveOpenDecision } from "../hooks/useOpenDecisions";
import {
  DOCUMENT_LIBRARY_MISSION_ID,
  missionProgress,
  type Decision,
  type LifeDocument,
  type Mission,
} from "../types/life";
import { bridgeCall } from "../hooks/useBridge";
import {
  missionTypeLabel,
  nextPhase,
  phaseHelp,
  phaseLabel,
} from "../lib/missionPhases";

export function Mission() {
  const { id } = useParams<{ id: string }>();
  const location = useLocation();
  const [searchParams, setSearchParams] = useSearchParams();
  const attentionId = searchParams.get("attention") || "";
  const seed =
    (location.state as { mission?: Mission } | null)?.mission ?? null;
  const attentionTitle =
    (location.state as { attentionTitle?: string } | null)?.attentionTitle ||
    "";
  const deckVisible = useDeckVisible();
  const { mission, decisions, documents, thoughts, loading, error, refresh } =
    useMissionDetail(id, seed && seed.id === id ? seed : null);
  const { thoughts: live } = useSSE({ enabled: deckVisible });
  const decisionsSectionRef = useRef<HTMLElement | null>(null);
  const [primaryBusy, setPrimaryBusy] = useState(false);
  const [phaseBusy, setPhaseBusy] = useState(false);
  const [logOpen, setLogOpen] = useState(false);
  const [logEditingId, setLogEditingId] = useState<string | null>(null);
  const [logTitle, setLogTitle] = useState("");
  const [logChosen, setLogChosen] = useState("");
  const [logContext, setLogContext] = useState("");
  const [logBusy, setLogBusy] = useState(false);
  const [logError, setLogError] = useState<string | null>(null);
  const [docOpen, setDocOpen] = useState(false);
  const [docTitle, setDocTitle] = useState("");
  const [docBody, setDocBody] = useState("");
  const [docBusy, setDocBusy] = useState(false);
  const [docError, setDocError] = useState<string | null>(null);
  const [expandedDocId, setExpandedDocId] = useState<string | null>(null);
  const [attachOpen, setAttachOpen] = useState(false);
  const [libraryDocs, setLibraryDocs] = useState<LifeDocument[]>([]);
  const [attachBusy, setAttachBusy] = useState(false);
  const [attachError, setAttachError] = useState<string | null>(null);
  const [assigningId, setAssigningId] = useState<string | null>(null);
  const [resolveBusyId, setResolveBusyId] = useState<string | null>(null);
  const [resolveError, setResolveError] = useState<string | null>(null);
  const resolveInflight = useRef<string | null>(null);

  useEffect(() => {
    if (loading || !mission) return;
    if (window.location.hash !== "#documents") return;
    const el = document.getElementById("documents");
    if (el) {
      window.requestAnimationFrame(() => {
        el.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    }
  }, [loading, mission, documents.length]);

  const orderedDecisions = useMemo(() => {
    const open = decisions.filter(isOpenDecision);
    const closed = decisions.filter((d) => !isOpenDecision(d));
    if (!attentionId) return [...open, ...closed];
    const spotlight = open.filter((d) => d.id === attentionId);
    const restOpen = open.filter((d) => d.id !== attentionId);
    return [...spotlight, ...restOpen, ...closed];
  }, [decisions, attentionId]);

  const attentionDecision =
    orderedDecisions.find((d) => d.id === attentionId) ||
    orderedDecisions.find(isOpenDecision) ||
    null;

  useEffect(() => {
    if (loading || !mission || !attentionId) return;
    const scroll = () => {
      const row = document.getElementById(`decision-${attentionId}`);
      const section = decisionsSectionRef.current;
      (row || section)?.scrollIntoView({ behavior: "smooth", block: "center" });
    };
    window.requestAnimationFrame(scroll);
  }, [loading, mission, attentionId, orderedDecisions.length]);

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
        <Link
          to="/"
          className="mt-4 inline-flex min-h-11 items-center rounded-full bg-accent px-4 py-2 text-sm font-semibold text-[var(--on-accent)]"
        >
          Back to Focus
        </Link>
      </div>
    );
  }

  const progress = missionProgress(mission);
  const missionId = mission.id;
  const advanceTo = nextPhase(mission.phase);
  const missionSnapshot = mission;

  function openLogForm(decision?: Decision | null) {
    const target = decision && isOpenDecision(decision) ? decision : null;
    setLogError(null);
    setLogOpen(true);
    if (target) {
      setLogEditingId(target.id);
      setLogTitle(target.title || "");
      setLogContext(target.context || "");
      setLogChosen("");
      return;
    }
    setLogEditingId(null);
    setLogTitle("");
    setLogChosen("");
    setLogContext("");
  }

  function closeLogForm() {
    setLogOpen(false);
    setLogEditingId(null);
    setLogTitle("");
    setLogChosen("");
    setLogContext("");
    setLogError(null);
  }

  async function submitDecision() {
    const title = logTitle.trim();
    if (!title) {
      setLogError("Title is required");
      return;
    }
    const chosen = logChosen.trim() || "Done";
    const closeId =
      logEditingId ||
      (attentionDecision && isOpenDecision(attentionDecision)
        ? attentionDecision.id
        : null);
    setLogBusy(true);
    setLogError(null);
    try {
      await bridgeCall("life_decision_log", {
        decision: {
          ...(closeId ? { id: closeId } : {}),
          mission_id: missionId,
          title,
          chosen,
          context: logContext.trim(),
        },
      });
      closeLogForm();
      if (attentionId) {
        setSearchParams({}, { replace: true });
      }
      await refresh();
    } catch (e) {
      setLogError(e instanceof Error ? e.message : "Could not save this choice");
    } finally {
      setLogBusy(false);
    }
  }

  async function markDecisionDone(decisionId: string) {
    if (resolveInflight.current) return;
    resolveInflight.current = decisionId;
    setResolveBusyId(decisionId);
    setResolveError(null);
    try {
      await resolveOpenDecision(decisionId, "Done");
      if (attentionId === decisionId) {
        setSearchParams({}, { replace: true });
      }
      await refresh();
    } catch (e) {
      setResolveError(
        e instanceof Error ? e.message : "Could not mark this decision done.",
      );
    } finally {
      resolveInflight.current = null;
      setResolveBusyId(null);
    }
  }

  async function submitDocument() {
    const title = docTitle.trim();
    if (!title) {
      setDocError("Title is required");
      return;
    }
    setDocBusy(true);
    setDocError(null);
    try {
      await bridgeCall("life_document_put", {
        document: {
          mission_id: missionId,
          title,
          body_md: docBody.trim(),
          source: "user",
          doc_type: "other",
        },
      });
      setDocTitle("");
      setDocBody("");
      setDocOpen(false);
      await refresh();
    } catch (e) {
      setDocError(e instanceof Error ? e.message : "Could not save document");
    } finally {
      setDocBusy(false);
    }
  }

  async function loadLibraryDocs() {
    setAttachBusy(true);
    setAttachError(null);
    try {
      const res = await bridgeCall<{ ok: true; documents: LifeDocument[] }>(
        "life_documents_list",
        { mission_id: DOCUMENT_LIBRARY_MISSION_ID, limit: 40 },
      );
      setLibraryDocs(res.documents || []);
    } catch (e) {
      setLibraryDocs([]);
      setAttachError(
        e instanceof Error ? e.message : "Could not load Document library",
      );
    } finally {
      setAttachBusy(false);
    }
  }

  async function assignLibraryDoc(documentId: string) {
    setAssigningId(documentId);
    setAttachError(null);
    try {
      await bridgeCall("life_document_assign", {
        document_id: documentId,
        mission_id: missionId,
      });
      setLibraryDocs((prev) => prev.filter((d) => d.id !== documentId));
      await refresh();
    } catch (e) {
      setAttachError(
        e instanceof Error ? e.message : "Could not assign document",
      );
    } finally {
      setAssigningId(null);
    }
  }

  async function advancePhase() {
    if (!advanceTo || phaseBusy) return;
    setPhaseBusy(true);
    try {
      // Omit targets — put_mission replaces the target table when targets[] is sent.
      await bridgeCall("life_mission_put", {
        mission: {
          id: missionSnapshot.id,
          subject_id: missionSnapshot.subject_id,
          title: missionSnapshot.title,
          statement: missionSnapshot.statement,
          situation: missionSnapshot.situation,
          why: missionSnapshot.why,
          purpose: missionSnapshot.purpose,
          phase: advanceTo,
          mission_type: missionSnapshot.mission_type,
          impact_rating: missionSnapshot.impact_rating,
          stack_sort_order: missionSnapshot.stack_sort_order,
          status: missionSnapshot.status,
          profile: missionSnapshot.profile,
        },
      });
      await refresh();
    } finally {
      setPhaseBusy(false);
    }
  }

  return (
    <div className="mx-auto min-h-screen max-w-7xl bg-surface/40 px-4 pb-20 pt-0 sm:px-6">
      <FocusBackBar
        eyebrow="Mission"
        title={missionTypeLabel(mission.mission_type)}
      />

      {attentionDecision && (
        <div
          className="mb-6 rounded-2xl border border-amber-glow/40 bg-amber-muted/50 px-4 py-3"
          role="status"
        >
          <p className="text-[11px] font-semibold uppercase tracking-[0.16em] text-amber-soft">
            This is why Focus alerted you
          </p>
          <p className="mt-1 text-sm font-medium text-ink">
            {attentionDecision.title || attentionTitle || "Decisions needed"}
          </p>
          {(attentionDecision.context || "").trim() ? (
            <p className="mt-1 text-xs text-ink-dim">
              {attentionDecision.context}
            </p>
          ) : null}
          <div className="mt-3 flex flex-wrap gap-2">
            {isOpenDecision(attentionDecision) ? (
              <button
                type="button"
                disabled={resolveBusyId === attentionDecision.id}
                className="inline-flex min-h-11 cursor-pointer items-center rounded-full bg-accent px-4 text-xs font-semibold text-[var(--on-accent)] disabled:opacity-50"
                onMouseDown={(e) => {
                  if (e.button !== 0 || resolveBusyId) return;
                  e.preventDefault();
                  void markDecisionDone(attentionDecision.id);
                }}
                onClick={(e) => {
                  e.preventDefault();
                  void markDecisionDone(attentionDecision.id);
                }}
              >
                {resolveBusyId === attentionDecision.id ? "Saving…" : "Done"}
              </button>
            ) : null}
            <button
              type="button"
              className="inline-flex min-h-11 cursor-pointer items-center rounded-full border border-amber-glow/40 px-4 text-xs font-semibold text-amber-bright"
              onClick={() => {
                document
                  .getElementById(`decision-${attentionDecision.id}`)
                  ?.scrollIntoView({ behavior: "smooth", block: "center" });
              }}
            >
              Jump to decision
            </button>
          </div>
        </div>
      )}

      <motion.header
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ type: "spring", stiffness: 160, damping: 22 }}
      >
        <p className="text-[11px] font-semibold uppercase tracking-[0.16em] text-amber-soft">
          {missionTypeLabel(mission.mission_type)} · detail
        </p>
        <h1 className="mt-2 font-display text-3xl font-semibold leading-tight tracking-tight text-ink sm:text-4xl">
          {mission.title}
        </h1>
        {mission.statement && (
          <p className="mt-3 text-lg text-ink-muted">{mission.statement}</p>
        )}
        <PhaseStrip phase={mission.phase} />
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
          {advanceTo && (
            <button
              type="button"
              disabled={phaseBusy}
              onClick={() => void advancePhase()}
              className="rounded-full border border-amber-glow/40 bg-amber-muted/80 px-5 py-2.5 text-sm font-semibold text-amber-bright shadow-amber-sm transition hover:bg-amber-glow/25 disabled:opacity-50"
            >
              {phaseBusy ? "Moving…" : `Move to ${phaseLabel(advanceTo)}`}
            </button>
          )}
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
              className="surface rounded-full border border-ink-dim/30 px-5 py-2.5 text-sm font-semibold text-ink transition hover:border-amber-glow/40 hover:text-amber-bright disabled:opacity-50"
            >
              {primaryBusy ? "Setting…" : "Set as Primary"}
            </button>
          )}
        </div>
        {advanceTo && (
          <p className="mt-3 max-w-xl text-sm text-ink-dim">
            Next: {phaseHelp(advanceTo).replace(/\.$/, "")}. Framing applies on
            the next conversation.
          </p>
        )}
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
          onTargetsChanged={() => void refresh()}
        />
      </section>

      <ActivityFeed thoughts={merged} title="Thought stream" />

      <section className="mt-8 scroll-mt-6" ref={decisionsSectionRef} id="decisions">
        <div className="mb-3 flex items-center justify-between gap-3">
          <h2 className="text-[11px] font-semibold uppercase tracking-[0.16em] text-ink-dim">
            Decisions
            {orderedDecisions.some(isOpenDecision) ? (
              <span className="ml-2 text-amber-soft">
                · {orderedDecisions.filter(isOpenDecision).length} decisions needed
              </span>
            ) : orderedDecisions.length > 0 ? (
              <span className="ml-2 text-ink-dim">
                · {orderedDecisions.length} recorded
              </span>
            ) : null}
          </h2>
          <button
            type="button"
            onClick={() =>
              logOpen
                ? closeLogForm()
                : openLogForm(
                    attentionDecision && isOpenDecision(attentionDecision)
                      ? attentionDecision
                      : orderedDecisions.find(isOpenDecision) || null,
                  )
            }
            className="rounded-full border border-amber-glow/30 bg-amber-muted/50 px-3 py-1 text-[11px] font-semibold text-amber-bright transition hover:bg-amber-glow/25"
          >
            {logOpen ? "Cancel" : logEditingId || orderedDecisions.some(isOpenDecision) ? "Record your choice" : "Log a decision"}
          </button>
        </div>

        {logOpen && (
          <div className="surface mb-3 space-y-3 rounded-2xl p-4">
            {logEditingId ? (
              <p className="text-xs text-ink-dim">
                This records your choice on the item that was waiting. It leaves
                Decisions needed and stays on this mission so you can look back.
              </p>
            ) : (
              <p className="text-xs text-ink-dim">
                Saved choices stay on this mission. Over time this is the record
                of what you decided.
              </p>
            )}
            <input
              value={logTitle}
              onChange={(e) => setLogTitle(e.target.value)}
              placeholder="Decision title"
              className="w-full rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-sm text-ink outline-none placeholder:text-ink-dim focus:border-amber-glow/40"
            />
            <input
              value={logChosen}
              onChange={(e) => setLogChosen(e.target.value)}
              placeholder="What you chose"
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
              onMouseDown={(e) => {
                if (e.button !== 0 || logBusy) return;
                e.preventDefault();
                void submitDecision();
              }}
              onClick={(e) => {
                e.preventDefault();
                void submitDecision();
              }}
              className="inline-flex min-h-11 cursor-pointer items-center rounded-full bg-accent px-5 text-sm font-semibold text-[var(--on-accent)] disabled:opacity-50"
            >
              {logBusy ? "Saving…" : "Save choice"}
            </button>
          </div>
        )}

        {resolveError && (
          <p className="mb-3 text-sm text-amber-soft">{resolveError}</p>
        )}
        <div className="surface rounded-2xl divide-y divide-white/5 overflow-hidden">
          {orderedDecisions.length === 0 ? (
            <p className="px-4 py-8 text-center text-sm text-ink-dim">
              No decisions recorded yet.
            </p>
          ) : (
            orderedDecisions.map((d) => {
              const open = isOpenDecision(d);
              const spotlight = attentionId === d.id;
              const when = (d.created_at || "").slice(0, 10);
              return (
                <div
                  key={d.id}
                  id={`decision-${d.id}`}
                  className={
                    spotlight
                      ? "flex items-start gap-3 scroll-mt-28 border-l-2 border-amber-glow bg-amber-muted/35 px-4 py-3"
                      : open
                        ? "flex items-start gap-3 scroll-mt-28 bg-amber-muted/15 px-4 py-3"
                        : "flex items-start gap-3 px-4 py-3"
                  }
                >
                  <div className="min-w-0 flex-1">
                    {open ? (
                      <p className="mb-1 text-[10px] font-semibold uppercase tracking-[0.14em] text-amber-soft">
                        Decisions needed
                      </p>
                    ) : (
                      <p className="mb-1 text-[10px] font-semibold uppercase tracking-[0.14em] text-ink-dim">
                        Decided{when ? ` · ${when}` : ""}
                      </p>
                    )}
                    <p className="text-sm font-medium text-ink">{d.title}</p>
                    {!open && d.chosen ? (
                      <p className="mt-1 text-sm text-amber-soft">
                        You chose: {d.chosen}
                      </p>
                    ) : null}
                    {d.context && (
                      <p className="mt-1 text-xs text-ink-dim">{d.context}</p>
                    )}
                  </div>
                  <div className="flex shrink-0 items-center gap-2">
                    {open ? (
                      <>
                        <button
                          type="button"
                          onClick={() => openLogForm(d)}
                          className="shrink-0 rounded-full border border-amber-glow/40 px-3 py-1.5 text-xs font-semibold text-amber-bright"
                        >
                          Record
                        </button>
                        <button
                          type="button"
                          disabled={resolveBusyId === d.id}
                          onMouseDown={(e) => {
                            if (e.button !== 0 || resolveBusyId) return;
                            e.preventDefault();
                            void markDecisionDone(d.id);
                          }}
                          onClick={(e) => {
                            e.preventDefault();
                            void markDecisionDone(d.id);
                          }}
                          className="inline-flex min-h-11 shrink-0 cursor-pointer items-center rounded-full bg-accent px-3 text-xs font-semibold text-[var(--on-accent)] disabled:opacity-50"
                        >
                          {resolveBusyId === d.id ? "Saving…" : "Done"}
                        </button>
                      </>
                    ) : null}
                  </div>
                </div>
              );
            })
          )}
        </div>
      </section>

      <section id="documents" className="mt-8 scroll-mt-6">
        <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-[11px] font-semibold uppercase tracking-[0.16em] text-ink-dim">
            Documents
          </h2>
          <div className="flex flex-wrap items-center gap-2">
            {mission.id !== DOCUMENT_LIBRARY_MISSION_ID && (
              <button
                type="button"
                onClick={() => {
                  setDocOpen(false);
                  setAttachOpen((o) => {
                    const next = !o;
                    if (next) void loadLibraryDocs();
                    return next;
                  });
                }}
                className="rounded-full border border-amber-glow/30 bg-amber-muted/50 px-3 py-1 text-[11px] font-semibold text-amber-bright transition hover:bg-amber-glow/25"
              >
                {attachOpen ? "Close library" : "Attach from library"}
              </button>
            )}
            <button
              type="button"
              onClick={() => {
                setAttachOpen(false);
                setDocOpen((o) => !o);
              }}
              className="rounded-full border border-amber-glow/30 bg-amber-muted/50 px-3 py-1 text-[11px] font-semibold text-amber-bright transition hover:bg-amber-glow/25"
            >
              {docOpen ? "Cancel" : "New document"}
            </button>
          </div>
        </div>

        {attachOpen && mission.id !== DOCUMENT_LIBRARY_MISSION_ID && (
          <div className="surface mb-3 space-y-3 rounded-2xl p-4">
            <p className="text-xs text-ink-dim">
              Unassigned Scan imports live in Document library. Assign one to
              this mission — or use Find documents on Focus.
            </p>
            {attachBusy && (
              <p className="text-xs text-ink-dim">Loading library…</p>
            )}
            {attachError && (
              <p className="text-sm text-amber-soft">{attachError}</p>
            )}
            {!attachBusy && !attachError && libraryDocs.length === 0 && (
              <p className="text-sm text-ink-dim">
                Library is empty. Scan this machine from Find documents on
                Focus.
              </p>
            )}
            {libraryDocs.length > 0 && (
              <ul className="divide-y divide-white/5 overflow-hidden rounded-xl border border-white/5">
                {libraryDocs.map((d) => (
                  <li
                    key={d.id}
                    className="flex items-start gap-3 px-3 py-2.5"
                  >
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-medium text-ink">{d.title}</p>
                      {(d.summary || d.excerpt) && (
                        <p className="mt-1 line-clamp-2 text-xs text-ink-muted">
                          {d.summary || d.excerpt}
                        </p>
                      )}
                    </div>
                    <button
                      type="button"
                      disabled={assigningId === d.id}
                      onClick={() => void assignLibraryDoc(d.id)}
                      className="shrink-0 rounded-full border border-amber-glow/30 bg-amber-muted/60 px-2.5 py-1 text-[11px] font-semibold text-amber-bright transition hover:bg-amber-glow/25 disabled:opacity-50"
                    >
                      {assigningId === d.id
                        ? "Assigning…"
                        : "Assign to this mission"}
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}

        {docOpen && (
          <div className="surface mb-3 space-y-3 rounded-2xl p-4">
            <input
              value={docTitle}
              onChange={(e) => setDocTitle(e.target.value)}
              placeholder="Document title"
              className="w-full rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-sm text-ink outline-none placeholder:text-ink-dim focus:border-amber-glow/40"
            />
            <textarea
              value={docBody}
              onChange={(e) => setDocBody(e.target.value)}
              placeholder="Body (markdown, optional)"
              rows={4}
              className="w-full resize-none rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-sm text-ink outline-none placeholder:text-ink-dim focus:border-amber-glow/40"
            />
            {docError && <p className="text-sm text-amber-soft">{docError}</p>}
            <button
              type="button"
              disabled={docBusy}
              onClick={() => void submitDocument()}
              className="rounded-full bg-accent px-5 py-2 text-sm font-semibold text-[var(--on-accent)] disabled:opacity-50"
            >
              {docBusy ? "Saving…" : "Save document"}
            </button>
          </div>
        )}

        <div className="surface overflow-hidden rounded-2xl divide-y divide-white/5">
          {documents.length === 0 ? (
            <p className="px-4 py-8 text-center text-sm text-ink-dim">
              Documents Centurion writes for this mission will land here.
            </p>
          ) : (
            documents.map((d) => {
              const open = expandedDocId === d.id;
              return (
                <div key={d.id} className="px-4 py-3">
                  <div className="flex items-start gap-3">
                    <button
                      type="button"
                      className="min-w-0 flex-1 text-left"
                      onClick={() =>
                        setExpandedDocId((cur) => (cur === d.id ? null : d.id))
                      }
                    >
                      <div className="flex flex-wrap items-center gap-2">
                        <p className="text-sm font-medium text-ink">{d.title}</p>
                        <span className="rounded-full border border-white/10 px-2 py-0.5 text-[10px] uppercase tracking-wide text-ink-dim">
                          {d.doc_type || "other"}
                        </span>
                      </div>
                      {d.summary && (
                        <p className="mt-1 text-xs text-ink-dim">{d.summary}</p>
                      )}
                      {d.updated_at && (
                        <p className="mt-1 text-[10px] text-ink-dim/80">
                          Updated {d.updated_at.replace("T", " ").slice(0, 16)}
                        </p>
                      )}
                    </button>
                  </div>
                  {open && d.body_md && (
                    <pre className="mt-3 max-h-64 overflow-auto whitespace-pre-wrap rounded-xl border border-white/5 bg-black/20 p-3 text-xs leading-relaxed text-ink-muted">
                      {d.body_md}
                    </pre>
                  )}
                </div>
              );
            })
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
