import { useCallback, useEffect, useRef, useState } from "react";
import { bridgeCall } from "./useBridge";
import type {
  Decision,
  LifeDocument,
  Mission,
  MissionStack,
  Thought,
} from "../types/life";

function stableJson(value: unknown): string {
  try {
    return JSON.stringify(value);
  } catch {
    return "";
  }
}

export function useMissionStack(pollMs = 20000, enabled = true) {
  const [stack, setStack] = useState<MissionStack | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const stackFp = useRef<string>("");

  const refresh = useCallback(async () => {
    try {
      const stackRes = await bridgeCall<{ ok: true; stack: MissionStack }>(
        "life_stack_get",
      );
      const next = stackRes.stack;
      const fp = stableJson(next);
      if (fp !== stackFp.current) {
        stackFp.current = fp;
        setStack(next);
      }
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

export function useMissionDetail(missionId: string | undefined) {
  const [mission, setMission] = useState<Mission | null>(null);
  const [decisions, setDecisions] = useState<Decision[]>([]);
  const [documents, setDocuments] = useState<LifeDocument[]>([]);
  const [thoughts, setThoughts] = useState<Thought[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!missionId) return;
    setLoading(true);
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
          ? docSettled.value.documents || []
          : [],
      );
      const thoughtsRaw =
        tSettled.status === "fulfilled" ? tSettled.value.thoughts || [] : [];
      setThoughts(
        thoughtsRaw.filter((t) => !t.mission_id || t.mission_id === missionId),
      );
      setError(null);
    } catch (e) {
      setMission(null);
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
      const docs = res.documents || [];
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
