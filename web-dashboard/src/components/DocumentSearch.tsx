import { useCallback, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { bridgeCall } from "../hooks/useBridge";
import type { LifeDocument } from "../types/life";

function discussDocument(d: LifeDocument) {
  const w = window as Window & {
    centurionDiscuss?: (p: Record<string, unknown>) => void;
  };
  if (typeof w.centurionDiscuss !== "function") return;
  const excerpt = (d.body_md || d.excerpt || d.summary || "").slice(0, 1200);
  w.centurionDiscuss({
    kind: "document",
    id: d.id,
    title: d.title,
    summary: d.summary || "",
    body_excerpt: excerpt,
    mission_id: d.mission_id,
    mission_title: d.mission_title || undefined,
    doc_type: d.doc_type || "other",
    plan_id: d.plan_id || undefined,
    kickoff: `Let's evolve this document: ${d.title}`,
  });
}

/**
 * Compact global document search on the Focus deck.
 */
export function DocumentSearch({
  enabled = true,
  preferredMissionId,
}: {
  enabled?: boolean;
  /** Fallback mission when path/title match is weak (e.g. Primary). */
  preferredMissionId?: string | null;
}) {
  const [query, setQuery] = useState("");
  const [agentOnly, setAgentOnly] = useState(false);
  const [results, setResults] = useState<LifeDocument[]>([]);
  const [busy, setBusy] = useState(false);
  const [scanning, setScanning] = useState(false);
  const [scanNote, setScanNote] = useState<string | null>(null);
  const [searched, setSearched] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const searchSeq = useRef(0);
  const abortRef = useRef<AbortController | null>(null);

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

  const runScan = useCallback(async () => {
    setScanning(true);
    setScanNote(null);
    setError(null);
    try {
      const res = await bridgeCall<{
        ok: true;
        imported?: number;
        updated?: number;
        skipped?: number;
        scanned_files?: number;
        roots?: string[];
        errors?: string[];
      }>("life_documents_import_scan", {
        mission_id: preferredMissionId || undefined,
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
  }, [preferredMissionId, query, agentOnly, runSearch]);

  useEffect(() => {
    if (!enabled) return;
    const t = window.setTimeout(() => {
      void runSearch(query, agentOnly);
    }, 450);
    return () => {
      window.clearTimeout(t);
      abortRef.current?.abort();
    };
  }, [query, agentOnly, enabled, runSearch]);

  if (!enabled) return null;

  return (
    <section className="mb-6">
      <div className="glass rounded-2xl p-4">
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
            /home/Legio/centurion, plans, and completed task outcomes.
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
            {results.map((d) => (
              <li key={d.id} className="flex items-start gap-3 px-3 py-2.5">
                <div className="min-w-0 flex-1">
                  <Link
                    to={`/mission/${d.mission_id}#documents`}
                    className="text-sm font-medium text-ink hover:text-amber-soft"
                  >
                    {d.title}
                  </Link>
                  <p className="mt-0.5 text-[11px] text-ink-dim">
                    {d.mission_title || "Mission"}
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
                <button
                  type="button"
                  title="Discuss in Chat"
                  aria-label={`Discuss ${d.title}`}
                  onClick={() => discussDocument(d)}
                  className="shrink-0 rounded-full border border-amber-glow/30 bg-amber-muted/60 px-2.5 py-1.5 text-sm font-semibold text-amber-bright transition hover:bg-amber-glow/25"
                >
                  💬
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}
