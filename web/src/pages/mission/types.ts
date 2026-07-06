/* ------------------------------------------------------------------ */
/*  Mission Control type definitions                                  */
/*  Ported from Centurion-website-v3/lib/swarm/types.ts              */
/*  No Supabase — purely local state.                                */
/* ------------------------------------------------------------------ */

export type ProjectStatus = "draft" | "active" | "completed";

export type SprintPhase = "brief" | "plan" | "execute" | "retrospect" | "done";

export type SwarmTaskStatus = "todo" | "ready" | "running" | "blocked" | "done";

export type TargetType =
  | "action"
  | "data"
  | "major"
  | "primary"
  | "vital"
  | "conditional"
  | "operating"
  | "production";

export type TargetStatus = "not_started" | "in_progress" | "complete" | "blocked";

export interface MissionProject {
  id: string;
  title: string;
  purpose: string | null;
  slug: string;
  status: ProjectStatus;
  sprint_phase: SprintPhase;
  sort_order: number;
  createdAt: string;
  updatedAt: string;
}

export interface MissionTask {
  id: string;
  projectId: string;
  targetId?: string | null;
  title: string;
  body: string | null;
  status: SwarmTaskStatus;
  assignee: string | null;
  sortOrder: number;
  result: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface MissionTarget {
  id: string;
  projectId: string;
  sequenceNumber: number;
  title: string;
  action: string | null;
  targetType: TargetType;
  status: TargetStatus;
  assignee: string | null;
  dueDate: string | null;
  createdAt: string;
  updatedAt: string;
}

/* ---- Constants ---- */

export const SPRINT_PHASES: { key: SprintPhase; label: string; description: string }[] = [
  { key: "brief", label: "Kickoff", description: "Align with the project sponsor on goals and constraints" },
  { key: "plan", label: "Planning", description: "Break work into targets and tasks with the team" },
  { key: "execute", label: "Execute", description: "Run the project — Centurions operate Mission Control" },
  { key: "retrospect", label: "Review", description: "Review outcomes with the sponsor and capture learnings" },
  { key: "done", label: "Done", description: "Project complete" },
];

export const KANBAN_COLUMNS: { id: SwarmTaskStatus; label: string }[] = [
  { id: "todo", label: "To Do" },
  { id: "ready", label: "Ready" },
  { id: "running", label: "Running" },
  { id: "blocked", label: "Blocked" },
  { id: "done", label: "Done" },
];

export const TARGET_TYPES: { key: TargetType; label: string; color: string }[] = [
  { key: "action", label: "Action", color: "bg-[var(--centurion-forest-lime)] text-[var(--centurion-forest)]" },
  { key: "data", label: "Data", color: "bg-[var(--centurion-forest-muted)] text-[var(--centurion-forest-lime)]" },
  { key: "major", label: "Major", color: "bg-[color-mix(in_srgb,#ef4444_35%,var(--centurion-forest))] text-[#fca5a5]" },
  { key: "primary", label: "Primary", color: "bg-[var(--centurion-gold)] text-[var(--centurion-forest)]" },
  { key: "vital", label: "Vital", color: "bg-[color-mix(in_srgb,var(--centurion-gold)_70%,var(--centurion-forest-lime))] text-[var(--centurion-forest)]" },
  { key: "conditional", label: "Conditional", color: "bg-[var(--centurion-forest-olive)] text-[var(--centurion-forest-lime)]" },
  { key: "operating", label: "Operating", color: "bg-[color-mix(in_srgb,var(--centurion-forest-lime)_40%,var(--centurion-forest-muted))] text-[var(--centurion-forest-lime)]" },
  { key: "production", label: "Production", color: "bg-[var(--centurion-forest-border)] text-[var(--midground-base)]" },
];

export const TARGET_STATUSES: { key: TargetStatus; label: string; color: string }[] = [
  { key: "not_started", label: "Not started", color: "bg-muted text-muted-foreground" },
  { key: "in_progress", label: "In progress", color: "bg-[color-mix(in_srgb,var(--centurion-gold)_25%,var(--centurion-forest))] text-[var(--centurion-gold)]" },
  { key: "complete", label: "Complete", color: "bg-[var(--centurion-forest-olive)] text-[var(--centurion-forest-lime)]" },
  { key: "blocked", label: "Blocked", color: "bg-[color-mix(in_srgb,#ef4444_30%,var(--centurion-forest))] text-[#fca5a5]" },
];
