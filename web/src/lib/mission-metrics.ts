/* ------------------------------------------------------------------ */
/*  Mission Control — metrics computation                              */
/*  Ported from Centurion-website-v3/lib/swarm/metrics.ts              */
/*  No Supabase — purely local state.                                  */
/* ------------------------------------------------------------------ */

import { PROJECT_CHECKLIST_ITEMS } from './mission-types'
import type { SwarmActivity, SwarmProject, SwarmProjectMember, SwarmTarget, SwarmTask } from './mission-types'

export interface FleetInstallSnapshot {
  install_id: string
  last_seen_at: string | null
}

export interface ProjectMetrics {
  totalTasks: number
  doneTasks: number
  runningTasks: number
  blockedTasks: number
  completionPct: number
  totalTargets: number
  completeTargets: number
  targetCompletionPct: number
  checklistPct: number
  activeCenturions: number
  activityLast24h: number
  lastActivityAt: string | null
  isLive: boolean
}

const LIVE_THRESHOLD_MS = 5 * 60 * 1000
const ACTIVE_INSTALL_MS = 15 * 60 * 1000

export function computeProjectMetrics(params: {
  project: SwarmProject
  tasks: SwarmTask[]
  targets?: SwarmTarget[]
  members: SwarmProjectMember[]
  recentActivity: SwarmActivity[]
  fleetInstalls?: FleetInstallSnapshot[]
}): ProjectMetrics {
  const { project, tasks, targets = [], members, recentActivity, fleetInstalls = [] } = params

  const totalTasks = tasks.length
  const doneTasks = tasks.filter((t) => t.status === 'done').length
  const runningTasks = tasks.filter((t) => t.status === 'running').length
  const blockedTasks = tasks.filter((t) => t.status === 'blocked').length
  const completionPct = totalTasks > 0 ? Math.round((doneTasks / totalTasks) * 100) : 0

  const totalTargets = targets.length
  const completeTargets = targets.filter((t) => t.status === 'complete').length
  const targetCompletionPct =
    totalTargets > 0 ? Math.round((completeTargets / totalTargets) * 100) : 0

  const checklistDone = PROJECT_CHECKLIST_ITEMS.filter((item) => project[item.key]).length
  const checklistPct = Math.round((checklistDone / PROJECT_CHECKLIST_ITEMS.length) * 100)

  const now = Date.now()
  const dayAgo = now - 24 * 60 * 60 * 1000
  const activityLast24h = recentActivity.filter(
    (a) => new Date(a.created_at).getTime() >= dayAgo,
  ).length

  const lastActivityAt =
    recentActivity.length > 0
      ? recentActivity.reduce((latest, a) =>
          new Date(a.created_at) > new Date(latest) ? a.created_at : latest,
        recentActivity[0].created_at)
      : null

  const isLive = lastActivityAt
    ? now - new Date(lastActivityAt).getTime() < LIVE_THRESHOLD_MS
    : false

  const fleetByInstall = new Map(fleetInstalls.map((f) => [f.install_id, f]))
  const activeCenturions = members.filter((m) => {
    const fleet = fleetByInstall.get(m.install_id)
    if (!fleet?.last_seen_at) return false
    return now - new Date(fleet.last_seen_at).getTime() < ACTIVE_INSTALL_MS
  }).length

  return {
    totalTasks,
    doneTasks,
    runningTasks,
    blockedTasks,
    completionPct,
    totalTargets,
    completeTargets,
    targetCompletionPct,
    checklistPct,
    activeCenturions,
    activityLast24h,
    lastActivityAt,
    isLive,
  }
}

export function computePortfolioCardMetrics(params: {
  project: SwarmProject
  tasks: SwarmTask[]
  recentActivity: SwarmActivity[]
}): Pick<ProjectMetrics, 'totalTasks' | 'doneTasks' | 'completionPct' | 'checklistPct' | 'lastActivityAt' | 'isLive'> {
  const full = computeProjectMetrics({
    project: params.project,
    tasks: params.tasks,
    members: [],
    recentActivity: params.recentActivity,
  })
  return {
    totalTasks: full.totalTasks,
    doneTasks: full.doneTasks,
    completionPct: full.completionPct,
    checklistPct: full.checklistPct,
    lastActivityAt: full.lastActivityAt,
    isLive: full.isLive,
  }
}
