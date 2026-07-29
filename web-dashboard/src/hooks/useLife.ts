import { useCallback, useEffect, useState } from "react";
import { bridgeCall } from "./useBridge";
import type {
  Decision,
  Mission,
  MissionStack,
  Subject,
  Thought,
} from "../types/life";

export function useMissionStack(pollMs = 8000) {
  const [stack, setStack] = useState<MissionStack | null>(null);
  const [subjects, setSubjects] = useState<Subject[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const [stackRes, subjectsRes] = await Promise.all([
        bridgeCall<{ ok: true; stack: MissionStack }>("life_stack_get"),
        bridgeCall<{ ok: true; subjects: Subject[] }>("life_subjects_list"),
      ]);
      setStack(stackRes.stack);
      setSubjects(subjectsRes.subjects || []);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
    const id = setInterval(() => void refresh(), pollMs);
    return () => clearInterval(id);
  }, [refresh, pollMs]);

  return { stack, subjects, loading, error, refresh };
}

export function useMissionDetail(missionId: string | undefined) {
  const [mission, setMission] = useState<Mission | null>(null);
  const [decisions, setDecisions] = useState<Decision[]>([]);
  const [thoughts, setThoughts] = useState<Thought[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!missionId) return;
    setLoading(true);
    try {
      const [mRes, dRes, tRes] = await Promise.all([
        bridgeCall<{ ok: true; mission: Mission }>("life_mission_get", {
          mission_id: missionId,
        }),
        bridgeCall<{ ok: true; decisions: Decision[] }>("life_decisions_list", {
          mission_id: missionId,
          limit: 40,
        }),
        bridgeCall<{ ok: true; thoughts: Thought[] }>("life_thoughts_list", {
          limit: 40,
        }),
      ]);
      setMission(mRes.mission);
      setDecisions(dRes.decisions || []);
      const filtered = (tRes.thoughts || []).filter(
        (t) => !t.mission_id || t.mission_id === missionId,
      );
      setThoughts(filtered);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [missionId]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  return { mission, decisions, thoughts, loading, error, refresh };
}
