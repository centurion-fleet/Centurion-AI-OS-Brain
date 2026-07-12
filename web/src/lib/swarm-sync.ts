/* ------------------------------------------------------------------ */
/*  Swarm / Mission Control sync — bridges dashboard UI to SwarmMcClient */
/* ------------------------------------------------------------------ */

import { fetchJSON } from './api'
import type { SwarmSummary } from './mission-types'
import type {
  MissionProject,
  MissionTarget,
  MissionTask,
  ProjectStatus,
  SprintPhase,
  SwarmTaskStatus,
  TargetStatus,
  TargetType,
} from '../pages/mission/types'
import type { SwarmProject, SwarmTarget, SwarmTask } from './mission-types'

export interface SwarmSyncResponse {
  ok: boolean
  source: 'brain' | 'portal' | 'local'
  message?: string
  project_id?: string
  swarms: SwarmSummary[]
  projects: Record<string, unknown>[]
  targets: Record<string, unknown>[]
  tasks: Record<string, unknown>[]
}

export async function fetchSwarmSync(since?: string): Promise<SwarmSyncResponse> {
  const qs = since ? `?since=${encodeURIComponent(since)}` : ''
  return fetchJSON<SwarmSyncResponse>(`/api/swarm/sync${qs}`)
}

function str(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback
}

function num(value: unknown, fallback = 0): number {
  return typeof value === 'number' ? value : fallback
}

export function normalizeSwarmProjects(rows: Record<string, unknown>[]): SwarmProject[] {
  return rows.map((row) => ({
    id: str(row.id),
    customer_id: str(row.customer_id, 'local'),
    program_id: row.program_id == null ? null : str(row.program_id),
    title: str(row.title, 'Collaboration'),
    purpose: row.purpose == null ? null : str(row.purpose),
    slug: str(row.slug, str(row.id)),
    status: (str(row.status, 'active') as ProjectStatus) || 'active',
    sprint_phase: (str(row.sprint_phase, 'execute') as SprintPhase) || 'execute',
    kanban_board_slug: row.kanban_board_slug == null ? null : str(row.kanban_board_slug),
    workspace_path: row.workspace_path == null ? null : str(row.workspace_path),
    checklist_viable: Boolean(row.checklist_viable),
    checklist_agreed: Boolean(row.checklist_agreed),
    checklist_assigned: Boolean(row.checklist_assigned),
    checklist_understood: Boolean(row.checklist_understood),
    checklist_resourced: Boolean(row.checklist_resourced),
    checklist_coordinated: Boolean(row.checklist_coordinated),
    checklist_supervised: Boolean(row.checklist_supervised),
    checklist_completed: Boolean(row.checklist_completed),
    checklist_reported: Boolean(row.checklist_reported),
    sort_order: num(row.sort_order),
    created_at: str(row.created_at),
    updated_at: str(row.updated_at),
  }))
}

export function normalizeSwarmTargets(rows: Record<string, unknown>[]): SwarmTarget[] {
  return rows.map((row) => ({
    id: str(row.id),
    customer_id: str(row.customer_id, 'local'),
    project_id: str(row.project_id),
    sequence_number: num(row.sequence_number),
    title: str(row.title),
    action: row.action == null ? null : str(row.action),
    target_type: (str(row.target_type, 'action') as TargetType) || 'action',
    status: (str(row.status, 'not_started') as TargetStatus) || 'not_started',
    assignee_install_id: row.assignee_install_id == null ? null : str(row.assignee_install_id),
    due_date: row.due_date == null ? null : str(row.due_date),
    start_date: row.start_date == null ? null : str(row.start_date),
    change_date: row.change_date == null ? null : str(row.change_date),
    stop_date: row.stop_date == null ? null : str(row.stop_date),
    completed_at: row.completed_at == null ? null : str(row.completed_at),
    created_at: str(row.created_at),
    updated_at: str(row.updated_at),
  }))
}

export function normalizeSwarmTasks(rows: Record<string, unknown>[]): SwarmTask[] {
  return rows.map((row) => ({
    id: str(row.id),
    customer_id: str(row.customer_id, 'local'),
    project_id: str(row.project_id),
    target_id: row.target_id == null ? null : str(row.target_id),
    title: str(row.title),
    body: row.body == null ? null : str(row.body),
    status: (str(row.status, 'todo') as SwarmTaskStatus) || 'todo',
    assignee_install_id: row.assignee_install_id == null ? null : str(row.assignee_install_id),
    sort_order: num(row.sort_order),
    result: row.result == null ? null : str(row.result),
    created_at: str(row.created_at),
    updated_at: str(row.updated_at),
  }))
}

/** Map portal snake_case project rows into dashboard MissionProject shape. */
export function normalizeMissionProjects(rows: Record<string, unknown>[]): MissionProject[] {
  return rows.map((row) => ({
    id: str(row.id),
    title: str(row.title, 'Collaboration'),
    purpose: row.purpose == null ? null : str(row.purpose),
    slug: str(row.slug, str(row.id)),
    status: (str(row.status, 'active') as ProjectStatus) || 'active',
    sprint_phase: (str(row.sprint_phase, 'execute') as SprintPhase) || 'execute',
    sort_order: num(row.sort_order),
    createdAt: str(row.created_at, row.createdAt),
    updatedAt: str(row.updated_at, row.updatedAt),
  }))
}

export function normalizeMissionTargets(rows: Record<string, unknown>[]): MissionTarget[] {
  return rows.map((row) => ({
    id: str(row.id),
    projectId: str(row.project_id, row.projectId),
    sequenceNumber: num(row.sequence_number) || num(row.sequenceNumber),
    title: str(row.title),
    action: row.action == null ? null : str(row.action),
    targetType: (str(row.target_type) || str(row.targetType) || 'action') as TargetType,
    status: (str(row.status, 'not_started') as TargetStatus) || 'not_started',
    assignee: row.assignee_install_id != null
      ? str(row.assignee_install_id)
      : row.assignee != null
        ? str(row.assignee)
        : null,
    dueDate: row.due_date != null ? str(row.due_date) : row.dueDate != null ? str(row.dueDate) : null,
    createdAt: str(row.created_at, row.createdAt),
    updatedAt: str(row.updated_at, row.updatedAt),
  }))
}

export function normalizeMissionTasks(rows: Record<string, unknown>[]): MissionTask[] {
  return rows.map((row) => ({
    id: str(row.id),
    projectId: str(row.project_id, row.projectId),
    targetId: row.target_id != null ? str(row.target_id) : row.targetId != null ? str(row.targetId) : null,
    title: str(row.title),
    body: row.body == null ? null : str(row.body),
    status: (str(row.status, 'todo') as SwarmTaskStatus) || 'todo',
    assignee: row.assignee_install_id != null
      ? str(row.assignee_install_id)
      : row.assignee != null
        ? str(row.assignee)
        : null,
    sortOrder: num(row.sort_order) || num(row.sortOrder),
    result: row.result == null ? null : str(row.result),
    createdAt: str(row.created_at, row.createdAt),
    updatedAt: str(row.updated_at, row.updatedAt),
  }))
}

/** Build constellation cards from portal SwarmProject rows. */
export function swarmsFromSwarmProjects(
  projects: SwarmProject[],
  tasks: SwarmTask[],
): SwarmSummary[] {
  const missionShape = projects.map((p) => ({
    id: p.id,
    title: p.title,
    purpose: p.purpose,
    updatedAt: p.updated_at,
    status: p.status,
    sprint_phase: p.sprint_phase,
  }))
  const taskShape = tasks.map((t) => ({
    projectId: t.project_id,
    status: t.status,
  }))
  return swarmsFromProjects(
    missionShape.map((p) => ({
      id: p.id,
      title: p.title,
      purpose: p.purpose,
      slug: p.id,
      status: p.status,
      sprint_phase: p.sprint_phase,
      sort_order: 0,
      createdAt: p.updatedAt,
      updatedAt: p.updatedAt,
    })),
    taskShape.map((t) => ({
      id: t.projectId,
      projectId: t.projectId,
      targetId: null,
      title: '',
      body: null,
      status: t.status,
      assignee: null,
      sortOrder: 0,
      result: null,
      createdAt: '',
      updatedAt: '',
    })),
  )
}

/** Build constellation cards from portal projects when API omits swarms[]. */
export function swarmsFromProjects(
  projects: MissionProject[],
  tasks: MissionTask[],
): SwarmSummary[] {
  return projects.map((project) => {
    const projectTasks = tasks.filter((t) => t.projectId === project.id)
    const blocked = projectTasks.filter((t) => t.status === 'blocked').length
    let pulse: SwarmSummary['pulse'] = 'idle'
    if (blocked > 0) pulse = 'blocked'
    else if (project.status === 'completed') pulse = 'complete'
    else if (project.sprint_phase === 'execute' || project.sprint_phase === 'plan') pulse = 'active'

    return {
      id: project.id,
      mission_id: null,
      display_name: project.title,
      objective: project.purpose ?? '',
      status: project.status === 'active' ? 'running' : project.status,
      pulse,
      formation_source: 'manual',
      participants: [],
      pending_signal_count: blocked,
      updated_at: project.updatedAt,
      attention_score: pulse === 'active' ? 50 : 20,
    }
  })
}
