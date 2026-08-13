/** Life Missions types — mirrors centurion_cli/life_missions.py */

export type MissionPhase =
  | "briefing"
  | "discovery"
  | "planning"
  | "executing"
  | "verifying"
  | "done";

export type MissionType = "primary" | "supporting" | "dream";

export type TargetType = "essential" | "shouldHave" | "niceToHave";

export type TargetStatus =
  | "not_started"
  | "in_progress"
  | "complete"
  | "blocked";

export type ThoughtActivityType =
  | "thought"
  | "tool_start"
  | "tool_result"
  | "target_update"
  | "artifact"
  | "decision"
  | "handoff";

export interface Subject {
  id: string;
  name: string;
  icon: string;
  sort_order: number;
  created_at?: string;
  updated_at?: string;
}

export interface MissionTarget {
  id: string;
  mission_id: string;
  sequence_number: number;
  title: string;
  description: string;
  target_type: TargetType;
  status: TargetStatus;
  focus_target: number;
  sequence_warning: string | null;
  started_at?: string | null;
  completed_at?: string | null;
  created_at?: string;
  updated_at?: string;
}

export interface MissionState {
  mission_id: string;
  focus_target_id: string | null;
  completed_target_ids: string[];
  last_activity_at?: string | null;
  last_decision_id?: string | null;
  checkpoint?: string | null;
  updated_at?: string;
}

export interface Mission {
  id: string;
  subject_id: string | null;
  title: string;
  statement: string;
  situation: string;
  why: string;
  purpose: string;
  phase: MissionPhase;
  mission_type: MissionType;
  impact_rating: "high" | "medium" | "low";
  stack_sort_order: number;
  status: string;
  profile: Record<string, unknown>;
  created_at?: string;
  updated_at?: string;
  targets: MissionTarget[];
  completed_target_count: number;
  target_count: number;
  state: MissionState | null;
}

export interface Dream {
  id: string;
  title: string;
  description: string;
  sort_order: number;
  promoted_to_mission_id: string | null;
  created_at?: string;
}

export interface MissionStack {
  primary: Mission | null;
  supporting: Mission[];
  dreams: Dream[];
  primary_mission_id: string | null;
}

export interface Decision {
  id: string;
  mission_id: string | null;
  target_id: string | null;
  title: string;
  context: string;
  options: string[];
  chosen: string;
  human_said: string;
  ai_recommendation: string;
  created_at?: string;
}

export type DocType =
  | "research"
  | "analysis"
  | "content"
  | "report"
  | "plan"
  | "other";

/** Hidden system mission for unmatched Scan imports (not null orphans). */
export const DOCUMENT_LIBRARY_MISSION_ID = "mission:document-library";

export interface LifeDocument {
  id: string;
  mission_id: string;
  target_id: string | null;
  title: string;
  doc_type: DocType | string;
  summary: string;
  body_md: string;
  plan_id: string | null;
  source: string;
  created_at?: string;
  updated_at?: string;
  /** Present on search results */
  mission_title?: string | null;
  excerpt?: string;
  body_truncated?: boolean;
}

export interface Thought {
  id: string;
  mission_id: string | null;
  target_id: string | null;
  activity_type: ThoughtActivityType;
  summary: string;
  detail: string;
  progress: number | null;
  created_at: string;
}

export interface BridgeOk {
  id?: string;
  ok: true;
  action?: string;
  [key: string]: unknown;
}

export interface BridgeErr {
  id?: string;
  ok: false;
  error?: string;
  message?: string;
  code?: string;
}

export type BridgeResponse = BridgeOk | BridgeErr;

export const TARGET_LABELS: Record<TargetType, string> = {
  essential: "Must Do",
  shouldHave: "Should Do",
  niceToHave: "Nice to Do",
};

export function missionProgress(mission: Mission | null | undefined): number {
  if (!mission || !mission.target_count) return 0;
  return Math.round(
    (100 * (mission.completed_target_count || 0)) / mission.target_count,
  );
}
