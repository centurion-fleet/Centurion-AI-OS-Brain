import { useCallback, useEffect, useState } from "react";
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
export function DocumentSearch({ enabled = true }: { enabled?: boolean }) {
  const [query, setQuery] = useState("");
  const [agentOnly, setAgentOnly] = useState(false);
  const [results, setResults] = useState<LifeDocument[]>([]);
  const [busy, setBusy] = useState(false);
  const [searched, setSearched] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const runSearch = useCallback(async (q: string, agent: boolean) => {
    const trimmed = q.trim();
    if (!trimmed) {
      setResults([]);
      setSearched(false);
      setError(null);
      return;
    }
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
      setResults(res.documents || []);
      setSearched(true);
    } catch (e) {
      setResults([]);
      setSearched(true);
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    if (!enabled) return;
    const t = window.setTimeout(() => {
      void runSearch(query, agentOnly);
    }, 280);
    return () => window.clearTimeout(t);
  }, [query, agentOnly, enabled, runSearch]);

  if (!enabled) return null;

  return (
    <section className="mb-6">
      <div className="glass rounded-2xl p-4">
        <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
          <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-ink-dim">
            Find documents
          </p>
          <label className="flex cursor-pointer items-center gap-2 text-[11px] text-ink-dim">
            <input
              type="checkbox"
              checked={agentOnly}
              onChange={(e) => setAgentOnly(e.target.checked)}
              className="rounded border-white/20 bg-white/5"
            />
            Created by Centurion
          </label>
        </div>
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search all mission documents…"
          className="w-full rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-sm text-ink outline-none placeholder:text-ink-dim focus:border-amber-glow/40"
        />
        {!query.trim() && (
          <p className="mt-2 text-xs text-ink-dim">
            Search covers every mission’s current documents (title, summary, and
            body).
          </p>
        )}
        {busy && (
          <p className="mt-2 text-xs text-ink-dim">Searching…</p>
        )}
        {error && (
          <p className="mt-2 text-xs text-amber-soft">{error}</p>
        )}
        {searched && !busy && !error && results.length === 0 && query.trim() && (
          <p className="mt-2 text-xs text-ink-dim">No documents matched.</p>
        )}
        {results.length > 0 && (
          <ul className="mt-3 divide-y divide-white/5 overflow-hidden rounded-xl border border-white/5">
            {results.map((d) => (
              <li
                key={d.id}
                className="flex items-start gap-3 px-3 py-2.5"
              >
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
