import { useCallback, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { bridgeCall } from "../hooks/useBridge";
import {
  DOCUMENT_LIBRARY_MISSION_ID,
  type LifeDocument,
  type Mission,
} from "../types/life";

function isAssignableMission(m: Mission): boolean {
  if (m.id === DOCUMENT_LIBRARY_MISSION_ID) return false;
  const profile = m.profile;
  if (profile && typeof profile === "object") {
    if (profile.hidden_from_stack || profile.system) return false;
  }
  return m.mission_type !== "dream";
}

/**
 * Global document search on the Focus deck (Find documents).
 * Mission pages list only that mission’s documents — this searches all.
 */
export function DocumentSearch({
  enabled = true,
  defaultOpen = false,
  hideToggle = false,
  onClose,
}: {
  enabled?: boolean;
  /** Start expanded (parent nav owns the Find documents link). */
  defaultOpen?: boolean;
  /** When true, skip the collapsed link — parent renders it (e.g. next to Discovery). */
  hideToggle?: boolean;
  onClose?: () => void;
}) {
  const [open, setOpen] = useState(defaultOpen);
  const [query, setQuery] = useState("");
  const [agentOnly, setAgentOnly] = useState(false);
  const [results, setResults] = useState<LifeDocument[]>([]);
  const [busy, setBusy] = useState(false);
  const [scanning, setScanning] = useState(false);
  const [scanNote, setScanNote] = useState<string | null>(null);
  const [searched, setSearched] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [assignDocId, setAssignDocId] = useState<string | null>(null);
  const [assignMissions, setAssignMissions] = useState<Mission[]>([]);
  const [assignBusy, setAssignBusy] = useState(false);
  const searchSeq = useRef(0);
  const abortRef = useRef<AbortController | null>(null);

  useEffect(() => {
    setOpen(defaultOpen);
  }, [defaultOpen]);

  const close = useCallback(() => {
    setOpen(false);
    setAssignDocId(null);
    onClose?.();
  }, [onClose]);

  const runSearch = useCallback(async (q: string, agent: boolean) => {
    const trimmed = q.trim();
    if (!trimmed || trimmed.length < 2) {
      setResults([]);
      setSearched(false);
      setError(null);
      setBusy(false);
      return;
    }
    abortRef.current?.abort();
    const ac = new AbortController();
    abortRef.current = ac;
    const seq = ++searchSeq.current;
    setBusy(true);
    setError(null);
    try {
      const res = await bridgeCall<{ ok: true; documents: LifeDocument[] }>(
        "life_documents_search",
        {
          query: trimmed,
          source: agent ? "agent" : undefined,
          limit: 20,
        },
      );
      if (ac.signal.aborted || seq !== searchSeq.current) return;
      setResults(res.documents || []);
      setSearched(true);
    } catch (e) {
      if (ac.signal.aborted || seq !== searchSeq.current) return;
      setResults([]);
      setSearched(true);
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      if (!ac.signal.aborted && seq === searchSeq.current) {
        setBusy(false);
      }
    }
  }, []);

  const openAssign = useCallback(async (documentId: string) => {
    setAssignDocId(documentId);
    setError(null);
    try {
      const res = await bridgeCall<{ ok: true; missions: Mission[] }>(
        "life_missions_list",
      );
      setAssignMissions((res.missions || []).filter(isAssignableMission));
    } catch (e) {
      setAssignMissions([]);
      setError(
        e instanceof Error ? e.message : "Could not load missions for assign",
      );
    }
  }, []);

  const assignToMission = useCallback(
    async (documentId: string, missionId: string) => {
      setAssignBusy(true);
      setError(null);
      try {
        const res = await bridgeCall<{ ok: true; document: LifeDocument }>(
          "life_document_assign",
          { document_id: documentId, mission_id: missionId },
        );
        const updated = res.document;
        setResults((prev) =>
          prev.map((d) =>
            d.id === documentId
              ? {
                  ...d,
                  ...updated,
                  mission_title:
                    assignMissions.find((m) => m.id === missionId)?.title ||
                    d.mission_title,
                }
              : d,
          ),
        );
        setAssignDocId(null);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Could not assign document");
      } finally {
        setAssignBusy(false);
      }
    },
    [assignMissions],
  );

  const runScan = useCallback(async () => {
    setScanning(true);
    setScanNote(null);
    setError(null);
    try {
      // Do not pass mission_id — unmatched imports go to Document library so
      // Primary / supporting mission Documents stay scoped to that mission.
      const res = await bridgeCall<{
        ok: true;
        imported?: number;
        updated?: number;
        skipped?: number;
        scanned_files?: number;
        roots?: string[];
        errors?: string[];
      }>("life_documents_import_scan", {
        include_plans: true,
        include_outcomes: true,
      });
      const imported = Number(res.imported || 0);
      const updated = Number(res.updated || 0);
      const skipped = Number(res.skipped || 0);
      const scanned = Number(res.scanned_files || 0);
      const errs = Array.isArray(res.errors) ? res.errors : [];
      let note = `Imported ${imported} · updated ${updated} · skipped ${skipped} · scanned ${scanned} files`;
      if (errs.length) {
        note += ` — ${errs[0]}`;
      }
      setScanNote(note);
      if (imported + updated === 0 && scanned === 0 && !errs.length) {
        setScanNote(
          `${note}. No text files found under Documents/Desktop — try centurion life import-docs --path /path/to/memos`,
        );
      }
      if (query.trim().length >= 2) {
        await runSearch(query, agentOnly);
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      if (/unsupported bridge action/i.test(msg)) {
        setError(
          "Scan needs a Brain restart after update — quit and reopen Sovereign AI Brain, then try Scan again.",
        );
      } else {
        setError(msg);
      }
    } finally {
      setScanning(false);
    }
  }, [query, agentOnly, runSearch]);

  useEffect(() => {
    if (!enabled || !open) return;
    const t = window.setTimeout(() => {
      void runSearch(query, agentOnly);
    }, 450);
    return () => {
      window.clearTimeout(t);
      abortRef.current?.abort();
    };
  }, [query, agentOnly, enabled, open, runSearch]);

  if (!enabled) return null;

  if (!open) {
    if (hideToggle) return null;
    return (
      <section className="mt-4 mb-2">
        <button
          type="button"
          onClick={() => setOpen(true)}
          className="text-sm text-ink-dim transition hover:text-amber-soft"
        >
          Find documents
        </button>
      </section>
    );
  }

  return (
    <section className="mb-2 w-full">
      <div className="surface rounded-2xl p-4">
        <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
          <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-ink-dim">
            Find documents
          </p>
          <div className="flex flex-wrap items-center gap-3">
            <label className="flex cursor-pointer items-center gap-2 text-[11px] text-ink-dim">
              <input
                type="checkbox"
                checked={agentOnly}
                onChange={(e) => setAgentOnly(e.target.checked)}
                className="rounded border-white/20 bg-white/5"
              />
              Created by Centurion
            </label>
            <button
              type="button"
              disabled={scanning}
              onClick={() => void runScan()}
              className="rounded-full border border-amber-glow/40 bg-amber-muted/70 px-3 py-1 text-[11px] font-semibold text-amber-bright transition hover:bg-amber-glow/25 disabled:opacity-50"
            >
              {scanning ? "Scanning…" : "Scan this machine"}
            </button>
            <button
              type="button"
              onClick={close}
              className="text-[11px] text-ink-dim hover:text-ink-muted"
            >
              Hide
            </button>
          </div>
        </div>
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search all mission documents…"
          className="w-full rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-sm text-ink outline-none placeholder:text-ink-dim focus:border-amber-glow/40"
        />
        {!query.trim() && (
          <p className="mt-2 text-xs text-ink-dim">
            Search covers every mission’s current documents. Use{" "}
            <span className="text-ink-muted">Scan this machine</span> to pull in
            older write-ups from Documents/Desktop, ~/centurion,
            /home/Legio/centurion, plans, and completed task outcomes. Unmatched
            imports land in Document library — not on your Primary mission.
            Assign library hits to a mission from the result row.
          </p>
        )}
        {scanNote && (
          <p className="mt-2 text-xs text-amber-soft">{scanNote}</p>
        )}
        {busy && <p className="mt-2 text-xs text-ink-dim">Searching…</p>}
        {error && <p className="mt-2 text-xs text-amber-soft">{error}</p>}
        {searched && !busy && !error && results.length === 0 && query.trim() && (
          <p className="mt-2 text-xs text-ink-dim">No documents matched.</p>
        )}
        {results.length > 0 && (
          <ul className="mt-3 divide-y divide-white/5 overflow-hidden rounded-xl border border-white/5">
            {results.map((d) => {
              const isLibrary = d.mission_id === DOCUMENT_LIBRARY_MISSION_ID;
              const assigning = assignDocId === d.id;
              return (
                <li key={d.id} className="px-3 py-2.5">
                  <div className="flex items-start gap-3">
                    <div className="min-w-0 flex-1">
                      <Link
                        to={`/mission/${d.mission_id}#documents`}
                        className="text-sm font-medium text-ink hover:text-amber-soft"
                      >
                        {d.title}
                      </Link>
                      <p className="mt-0.5 text-[11px] text-ink-dim">
                        {isLibrary
                          ? "Document library"
                          : d.mission_title || "Mission"}
                        {d.doc_type ? ` · ${d.doc_type}` : ""}
                        {d.updated_at
                          ? ` · ${d.updated_at.replace("T", " ").slice(0, 16)}`
                          : ""}
                      </p>
                      {(d.excerpt || d.summary) && (
                        <p className="mt-1 line-clamp-2 text-xs text-ink-muted">
                          {d.excerpt || d.summary}
                        </p>
                      )}
                    </div>
                    <div className="flex shrink-0 flex-col items-end gap-1">
                      {isLibrary && (
                        <button
                          type="button"
                          disabled={assignBusy}
                          onClick={() =>
                            assigning
                              ? setAssignDocId(null)
                              : void openAssign(d.id)
                          }
                          className="rounded-full border border-amber-glow/30 bg-amber-muted/60 px-2.5 py-1 text-[11px] font-semibold text-amber-bright transition hover:bg-amber-glow/25 disabled:opacity-50"
                        >
                          {assigning ? "Cancel" : "Assign…"}
                        </button>
                      )}
                    </div>
                  </div>
                  {assigning && (
                    <div className="mt-2 rounded-xl border border-white/5 bg-black/20 p-2">
                      {assignMissions.length === 0 ? (
                        <p className="text-xs text-ink-dim">
                          No missions available to assign.
                        </p>
                      ) : (
                        <ul className="max-h-40 space-y-1 overflow-auto">
                          {assignMissions.map((m) => (
                            <li key={m.id}>
                              <button
                                type="button"
                                disabled={assignBusy}
                                onClick={() =>
                                  void assignToMission(d.id, m.id)
                                }
                                className="w-full rounded-lg px-2 py-1.5 text-left text-xs text-ink transition hover:bg-amber-muted/40 disabled:opacity-50"
                              >
                                {m.title}
                                <span className="ml-2 text-ink-dim">
                                  {m.mission_type}
                                </span>
                              </button>
                            </li>
                          ))}
                        </ul>
                      )}
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </section>
  );
}
