import { Link } from "react-router-dom";
import { useCallback, useEffect, useState } from "react";
import { bridgeCall } from "../hooks/useBridge";
import type { LifeDocument } from "../types/life";

/** All mission documents on Focus home — mission pages stay scoped to one mission. */
export function DocumentsRow({ enabled }: { enabled: boolean }) {
  const [docs, setDocs] = useState<LifeDocument[]>([]);

  const refresh = useCallback(async () => {
    if (!enabled) return;
    try {
      const res = await bridgeCall<{ ok: true; documents: LifeDocument[] }>(
        "life_documents_list",
        { limit: 40 },
      );
      setDocs(res.documents || []);
    } catch {
      setDocs([]);
    }
  }, [enabled]);

  useEffect(() => {
    if (!enabled) {
      setDocs([]);
      return;
    }
    void refresh();
  }, [enabled, refresh]);

  if (!enabled || docs.length === 0) return null;

  return (
    <section className="mt-10">
      <div className="mb-3 flex items-center justify-between gap-3">
        <h2 className="text-[11px] font-semibold uppercase tracking-[0.16em] text-ink-dim">
          Documents · {docs.length}
        </h2>
        <p className="text-[11px] text-ink-dim">Every mission</p>
      </div>
      <ul className="surface divide-y divide-white/5 overflow-hidden rounded-2xl">
        {docs.map((d) => (
          <li key={d.id}>
            <Link
              to={d.mission_id ? `/mission/${d.mission_id}#documents` : "/"}
              className="flex min-h-11 items-start justify-between gap-3 px-4 py-3"
            >
              <div className="min-w-0">
                <p className="text-sm font-medium text-ink">{d.title}</p>
                {d.mission_title ? (
                  <p className="mt-0.5 text-xs text-ink-dim">{d.mission_title}</p>
                ) : null}
                {d.summary ? (
                  <p className="mt-1 line-clamp-2 text-xs text-ink-muted">
                    {d.summary}
                  </p>
                ) : null}
              </div>
              <span className="shrink-0 text-[10px] uppercase tracking-wide text-ink-dim">
                {d.doc_type || "other"}
              </span>
            </Link>
          </li>
        ))}
      </ul>
    </section>
  );
}
