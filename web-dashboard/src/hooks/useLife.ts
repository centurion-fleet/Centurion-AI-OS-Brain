import { useCallback, useEffect, useRef, useState } from "react";
import { bridgeCall } from "./useBridge";
import type {
  Decision,
  LifeDocument,
  Mission,
  MissionStack,
  Thought,
} from "../types/life";

const DECK_CACHE_KEY = "centurion_deck_snapshot_v1";

function stableJson(value: unknown): string {
  try {
    return JSON.stringify(value);
  } catch {
    return "";
  }
}

function readCachedStack(): MissionStack | null {
  try {
    const raw = sessionStorage.getItem(DECK_CACHE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as { stack?: MissionStack };
    return parsed.stack ?? null;
  } catch {
    return null;
  }
}

function writeCachedSnapshot(payload: {
  stack: MissionStack;
  thoughts?: Thought[];
  primary_documents?: LifeDocument[];
}) {
  try {
    sessionStorage.setItem(DECK_CACHE_KEY, JSON.stringify(payload));
  } catch {
    /* quota / private mode */
  }
}

export function useMissionStack(pollMs = 20000, enabled = true) {
  const cached = useRef(readCachedStack());
  const [stack, setStack] = useState<MissionStack | null>(cached.current);
  const [loading, setLoading] = useState(!cached.current);
  const [error, setError] = useState<string | null>(null);
  const stackFp = useRef<string>(
    cached.current ? stableJson(cached.current) : "",
  );

  const refresh = useCallback(async () => {
    try {
      // Prefer one-shot hydration; fall back to stack-only on older bridges.
      let next: MissionStack | null = null;
      let thoughts: Thought[] | undefined;
      let docs: LifeDocument[] | undefined;
      try {
        const snap = await bridgeCall<{
          ok: true;
          stack: MissionStack;
          thoughts?: Thought[];
          primary_documents?: LifeDocument[];
        }>("life_deck_snapshot", {
          thought_limit: 32,
          document_limit: 5,
        });
        next = snap.stack;
        thoughts = snap.thoughts;
        docs = snap.primary_documents;
      } catch {
        const stackRes = await bridgeCall<{ ok: true; stack: MissionStack }>(
          "life_stack_get",
        );
        next = stackRes.stack;
      }
      if (!next) return;
      const fp = stableJson(next);
      if (fp !== stackFp.current) {
        stackFp.current = fp;
        setStack(next);
      }
      writeCachedSnapshot({
        stack: next,
        thoughts,
        primary_documents: docs,
      });
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!enabled) {
      // Avoid infinite "Opening your deck…" while the Brain Chat tab is active.
      setLoading(false);
      return;
    }
    // Don't flash the loading panel when we already have a cached stack.
    if (!stackFp.current) {
      setLoading(true);
    }
    void refresh();
    const id = setInterval(() => void refresh(), pollMs);
    return () => clearInterval(id);
  }, [refresh, pollMs, enabled]);

  return { stack, loading, error, refresh };
}

export function useMissionDetail(
  missionId: string | undefined,
  seed?: Mission | null,
) {
  const [mission, setMission] = useState<Mission | null>(
    seed && seed.id === missionId ? seed : null,
  );
  const [decisions, setDecisions] = useState<Decision[]>([]);
  const [documents, setDocuments] = useState<LifeDocument[]>([]);
  const [thoughts, setThoughts] = useState<Thought[]>([]);
  const [loading, setLoading] = useState(!(seed && seed.id === missionId));
  const [error, setError] = useState<string | null>(null);
  const missionRef = useRef(mission);
  missionRef.current = mission;

  useEffect(() => {
    if (seed && seed.id === missionId) {
      setMission(seed);
      setLoading(false);
    }
  }, [seed, missionId]);

  const refresh = useCallback(async () => {
    if (!missionId) return;
    // Keep seeded header visible; only show full loading when we have nothing.
    const current = missionRef.current;
    if (!current || current.id !== missionId) {
      setLoading(true);
    }
    try {
      // Mission + decisions are required. Documents/thoughts are best-effort so a
      // newer deck against an older bridge (or missing table) still opens detail.
      const mRes = await bridgeCall<{ ok: true; mission: Mission }>(
        "life_mission_get",
        { mission_id: missionId },
      );
      setMission(mRes.mission);

      const [dSettled, docSettled, tSettled] = await Promise.allSettled([
        bridgeCall<{ ok: true; decisions: Decision[] }>("life_decisions_list", {
          mission_id: missionId,
          limit: 40,
        }),
        bridgeCall<{ ok: true; documents: LifeDocument[] }>(
          "life_documents_list",
          {
            mission_id: missionId,
            limit: 40,
          },
        ),
        bridgeCall<{ ok: true; thoughts: Thought[] }>("life_thoughts_list", {
          limit: 40,
        }),
      ]);

      setDecisions(
        dSettled.status === "fulfilled" ? dSettled.value.decisions || [] : [],
      );
      setDocuments(
        docSettled.status === "fulfilled"
          ? (docSettled.value.documents || []).filter(
              (d) => d.mission_id === missionId,
            )
          : [],
      );
      const thoughtsRaw =
        tSettled.status === "fulfilled" ? tSettled.value.thoughts || [] : [];
      setThoughts(
        thoughtsRaw.filter((t) => !t.mission_id || t.mission_id === missionId),
      );
      setError(null);
    } catch (e) {
      const current = missionRef.current;
      if (!current || current.id !== missionId) {
        setMission(null);
      }
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [missionId]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  return { mission, decisions, documents, thoughts, loading, error, refresh };
}

/** Latest documents for the Primary mission (Focus card teaser). */
export function usePrimaryDocuments(
  missionId: string | undefined,
  enabled = true,
  pollMs = 60000,
) {
  const [documents, setDocuments] = useState<LifeDocument[]>([]);
  const [count, setCount] = useState(0);
  const docsFp = useRef<string>("");

  // Seed from deck snapshot cache when available.
  useEffect(() => {
    if (!missionId) return;
    try {
      const raw = sessionStorage.getItem(DECK_CACHE_KEY);
      if (!raw) return;
      const parsed = JSON.parse(raw) as {
        primary_documents?: LifeDocument[];
      };
      const docs = (parsed.primary_documents || []).filter(
        (d) => d.mission_id === missionId,
      );
      if (docs.length) {
        docsFp.current = stableJson(docs);
        setDocuments(docs);
        setCount(docs.length);
      }
    } catch {
      /* ignore */
    }
  }, [missionId]);

  const refresh = useCallback(async () => {
    if (!missionId || !enabled) {
      setDocuments([]);
      setCount(0);
      docsFp.current = "";
      return;
    }
    try {
      const res = await bridgeCall<{ ok: true; documents: LifeDocument[] }>(
        "life_documents_list",
        { mission_id: missionId, limit: 5 },
      );
      const docs = (res.documents || []).filter(
        (d) => d.mission_id === missionId,
      );
      const fp = stableJson(docs);
      if (fp !== docsFp.current) {
        docsFp.current = fp;
        setDocuments(docs);
        setCount(docs.length);
      }
    } catch {
      setDocuments([]);
      setCount(0);
      docsFp.current = "";
    }
  }, [missionId, enabled]);

  useEffect(() => {
    if (!enabled || !missionId) {
      setDocuments([]);
      setCount(0);
      docsFp.current = "";
      return;
    }
    void refresh();
    const id = setInterval(() => void refresh(), pollMs);
    return () => clearInterval(id);
  }, [refresh, pollMs, enabled, missionId]);

  return { documents, count, refresh };
}
