/* ------------------------------------------------------------------ */
/*  Mission Control — full Swarm type definitions                      */
/*  Ported from Centurion-website-v3/lib/swarm/types.ts                */
/*  No Supabase — purely local state.                                  */
/* ------------------------------------------------------------------ */

// ── Type aliases (union types) ──────────────────────────────────────

export type ProgramPhase =
  | 'situation'
  | 'why'
  | 'program'
  | 'project'
  | 'execute'
  | 'complete'
  | 'report'

export type ProjectStatus = 'draft' | 'active' | 'completed'

/** Time-free sprint lifecycle for a project (Centurion-operated). */
export type SprintPhase = 'brief' | 'plan' | 'execute' | 'retrospect' | 'done'

export type CeremonyType = 'brief' | 'plan' | 'retrospect' | 'welcome'

export type CeremonyStatus = 'open' | 'closed'

export type CeremonyEntryKind = 'centurion' | 'human' | 'system'

export type CeremonyEntryType = 'topic' | 'decision' | 'action' | 'note' | 'question'

export type SwarmTaskStatus = 'todo' | 'ready' | 'running' | 'blocked' | 'done'

export type TargetType =
  | 'action'
  | 'data'
  | 'major'
  | 'primary'
  | 'vital'
  | 'conditional'
  | 'operating'
  | 'production'

export type TargetStatus = 'not_started' | 'in_progress' | 'complete' | 'blocked'

/** Orb animation state — shared with iOS SwarmSummary.pulse */
export type SwarmPulse =
  | 'idle'
  | 'active'
  | 'attention'
  | 'waiting'
  | 'blocked'
  | 'complete'
  | 'forming'

export type SwarmFormationSource = 'chat' | 'meeting' | 'manual'

export interface SwarmParticipant {
  id: string
  name: string
  kind: 'centurion' | 'human'
  role: 'owner' | 'operator' | 'observer'
  is_active?: boolean
}

/** Slim cross-platform Swarm card model for constellation UI */
export interface SwarmSummary {
  id: string
  mission_id?: string | null
  display_name: string
  objective: string
  status: string
  pulse: SwarmPulse
  formation_source: SwarmFormationSource
  participants: SwarmParticipant[]
  pending_signal_count: number
  updated_at: string
  attention_score?: number
}

export type ActivityType =
  | 'thought'
  | 'tool_start'
  | 'tool_result'
  | 'task_update'
  | 'target_update'
  | 'artifact'
  | 'handoff'
  | 'decision'
  | 'ceremony'

export type CenturionTokenType = 'inst' | 'proj' | 'link' | 'primary'

export type DeletionEntityType = 'program' | 'project' | 'task'
export type DeletionInitiator = 'human' | 'centurion'
export type DeletionRequestStatus = 'pending' | 'completed' | 'cancelled'

// ── Interfaces ──────────────────────────────────────────────────────

export interface SwarmProgram {
  id: string
  customer_id: string
  title: string
  purpose: string | null
  situation: string | null
  why: string | null
  current_phase: ProgramPhase
  status: 'active' | 'completed' | 'inactive'
  sort_order: number
  created_at: string
  updated_at: string
}

export interface SwarmProject {
  id: string
  customer_id: string
  program_id: string | null
  title: string
  purpose: string | null
  slug: string
  status: ProjectStatus
  sprint_phase: SprintPhase
  kanban_board_slug: string | null
  workspace_path: string | null
  checklist_viable: boolean
  checklist_agreed: boolean
  checklist_assigned: boolean
  checklist_understood: boolean
  checklist_resourced: boolean
  checklist_coordinated: boolean
  checklist_supervised: boolean
  checklist_completed: boolean
  checklist_reported: boolean
  sort_order: number
  created_at: string
  updated_at: string
}

export interface SwarmDeletionRequest {
  id: string
  customer_id: string
  entity_type: DeletionEntityType
  entity_id: string
  reason: string | null
  status: DeletionRequestStatus
  initiated_by: DeletionInitiator
  human_approved_at: string | null
  human_approved_by: string | null
  centurion_approved_at: string | null
  centurion_install_id: string | null
  centurion_id: string | null
  created_at: string
  completed_at: string | null
  cancelled_at: string | null
  expires_at: string
}

export interface SwarmProjectMember {
  id: string
  customer_id: string
  project_id: string
  install_id: string
  centurion_id: string
  role: 'owner' | 'operator' | 'observer'
  joined_at: string
}

export interface SwarmTask {
  id: string
  customer_id: string
  project_id: string
  target_id?: string | null
  title: string
  body: string | null
  status: SwarmTaskStatus
  assignee_install_id: string | null
  sort_order: number
  result: string | null
  created_at: string
  updated_at: string
}

export interface SwarmTarget {
  id: string
  customer_id: string
  project_id: string
  sequence_number: number
  title: string
  action: string | null
  target_type: TargetType
  status: TargetStatus
  assignee_install_id: string | null
  due_date: string | null
  start_date: string | null
  change_date: string | null
  stop_date: string | null
  completed_at: string | null
  created_at: string
  updated_at: string
}

export interface SwarmActivity {
  id: string
  customer_id: string
  project_id: string
  install_id: string
  centurion_id: string | null
  activity_type: ActivityType
  summary: string
  body: string | null
  metadata: Record<string, unknown>
  created_at: string
}

export interface SwarmArtifact {
  id: string
  customer_id: string
  project_id: string
  path: string
  title: string | null
  content_type: string | null
  task_id: string | null
  published_to_program: boolean
  latest_version_id: string | null
  created_at: string
  updated_at: string
}

export interface SwarmCeremony {
  id: string
  customer_id: string
  project_id: string
  ceremony_type: CeremonyType
  status: CeremonyStatus
  title: string | null
  summary: string | null
  opened_by_install_id: string | null
  opened_at: string
  closed_at: string | null
  created_at: string
  updated_at: string
}

export interface SwarmCeremonyEntry {
  id: string
  ceremony_id: string
  customer_id: string
  project_id: string
  author_kind: CeremonyEntryKind
  author_install_id: string | null
  author_customer_id: string | null
  author_label: string | null
  body: string
  entry_type: CeremonyEntryType
  created_at: string
}

// ── Constants ───────────────────────────────────────────────────────

export const SPRINT_PHASES: {
  key: SprintPhase
  label: string
  description: string
  ceremonyType: CeremonyType | null
}[] = [
  {
    key: 'brief',
    label: 'Kickoff',
    description: 'Align with the project sponsor on goals and constraints',
    ceremonyType: 'brief',
  },
  {
    key: 'plan',
    label: 'Planning',
    description: 'Break work into targets and tasks with the team',
    ceremonyType: 'plan',
  },
  {
    key: 'execute',
    label: 'Execute',
    description: 'Run the project — Centurions operate Mission Control',
    ceremonyType: null,
  },
  {
    key: 'retrospect',
    label: 'Review',
    description: 'Review outcomes with the sponsor and capture learnings',
    ceremonyType: 'retrospect',
  },
  {
    key: 'done',
    label: 'Done',
    description: 'Project complete',
    ceremonyType: null,
  },
]

export const CEREMONY_TYPES: { key: CeremonyType; label: string; sponsorInvited: boolean }[] = [
  { key: 'brief', label: 'Kickoff', sponsorInvited: true },
  { key: 'plan', label: 'Planning', sponsorInvited: true },
  { key: 'retrospect', label: 'Review', sponsorInvited: true },
]

export const PROGRAM_PHASES: { key: ProgramPhase; label: string; description: string }[] = [
  { key: 'situation', label: 'Situation', description: 'Analyze the existing scene' },
  { key: 'why', label: 'WHY', description: 'Establish why it needs handling' },
  { key: 'program', label: 'Program', description: 'Develop the overall program' },
  { key: 'project', label: 'Project', description: 'Break down into specific projects' },
  { key: 'execute', label: 'Execute', description: 'Carry out targets in sequence' },
  { key: 'complete', label: 'Complete', description: 'Finish and verify completion' },
  { key: 'report', label: 'Report', description: 'Document results and submit report' },
]

export const PROJECT_CHECKLIST_ITEMS: {
  key: keyof Pick<
    SwarmProject,
    | 'checklist_viable'
    | 'checklist_agreed'
    | 'checklist_assigned'
    | 'checklist_understood'
    | 'checklist_resourced'
    | 'checklist_coordinated'
    | 'checklist_supervised'
    | 'checklist_completed'
    | 'checklist_reported'
  >
  label: string
  description: string
}[] = [
  { key: 'checklist_viable', label: 'Viable', description: 'The project is actually doable and worthwhile' },
  { key: 'checklist_agreed', label: 'Agreed Upon', description: 'All parties have agreed to the project' },
  { key: 'checklist_assigned', label: 'Assigned', description: 'Specific personnel have been assigned' },
  { key: 'checklist_understood', label: 'Understood', description: 'Those assigned fully understand the project' },
  { key: 'checklist_resourced', label: 'Resourced', description: 'Adequate resources are allocated' },
  { key: 'checklist_coordinated', label: 'Coordinated', description: 'Actions are coordinated with other areas' },
  { key: 'checklist_supervised', label: 'Supervised', description: 'Proper supervision is in place' },
  { key: 'checklist_completed', label: 'Completed', description: 'The project has been completed' },
  { key: 'checklist_reported', label: 'Reported', description: 'Completion has been properly reported' },
]

export const KANBAN_COLUMNS: { id: SwarmTaskStatus; label: string }[] = [
  { id: 'todo', label: 'To Do' },
  { id: 'ready', label: 'Ready' },
  { id: 'running', label: 'Running' },
  { id: 'blocked', label: 'Blocked' },
  { id: 'done', label: 'Done' },
]

/** Forest-palette badges — no generic blue/cyan (see README Theme & UI). */
export const TARGET_TYPES: { key: TargetType; label: string; color: string }[] = [
  { key: 'action', label: 'Action', color: 'bg-[var(--centurion-forest-lime)] text-[var(--centurion-forest)]' },
  { key: 'data', label: 'Data', color: 'bg-[var(--centurion-forest-muted)] text-[var(--centurion-forest-lime)]' },
  { key: 'major', label: 'Major', color: 'bg-[color-mix(in_srgb,#ef4444_35%,var(--centurion-forest))] text-[#fca5a5]' },
  { key: 'primary', label: 'Primary', color: 'bg-[var(--centurion-gold)] text-[var(--centurion-forest)]' },
  { key: 'vital', label: 'Vital', color: 'bg-[color-mix(in_srgb,var(--centurion-gold)_70%,var(--centurion-forest-lime))] text-[var(--centurion-forest)]' },
  { key: 'conditional', label: 'Conditional', color: 'bg-[var(--centurion-forest-olive)] text-[var(--centurion-forest-lime)]' },
  { key: 'operating', label: 'Operating', color: 'bg-[color-mix(in_srgb,var(--centurion-forest-lime)_40%,var(--centurion-forest-muted))] text-[var(--centurion-forest-lime)]' },
  { key: 'production', label: 'Production', color: 'bg-[var(--centurion-forest-border)] text-[var(--midground-base)]' },
]

export const TARGET_STATUSES: { key: TargetStatus; label: string; color: string }[] = [
  { key: 'not_started', label: 'Not started', color: 'bg-muted text-muted-foreground' },
  { key: 'in_progress', label: 'In progress', color: 'bg-[color-mix(in_srgb,var(--centurion-gold)_25%,var(--centurion-forest))] text-[var(--centurion-gold)]' },
  { key: 'complete', label: 'Complete', color: 'bg-[var(--centurion-forest-olive)] text-[var(--centurion-forest-lime)]' },
  { key: 'blocked', label: 'Blocked', color: 'bg-[color-mix(in_srgb,#ef4444_30%,var(--centurion-forest))] text-[#fca5a5]' },
]
