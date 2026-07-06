/* ------------------------------------------------------------------ */
/*  Mission Control Project Page — project detail dashboard            */
/*  Displays project info, metrics, targets with linked tasks,         */
/*  inline target creation, and complete/reopen actions.               */
/*  Uses the mission-store data layer (new).                           */
/* ------------------------------------------------------------------ */

'use client'

import {
  useCallback,
  useMemo,
  useState,
} from 'react'
import {
  AlertCircle,
  ArrowLeft,
  CheckCircle2,
  Circle,
  Clock,
  ListChecks,
  Plus,
  Sparkles,
  Target,
  X,
} from 'lucide-react'
import { Badge } from '@centurion-fleet/ui/ui/components/badge'
import { Button } from '@centurion-fleet/ui/ui/components/button'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { cn, isoTimeAgo } from '@/lib/utils'
import { MissionStoreProvider, useMissionStore } from '../../lib/mission-store'
import {
  TARGET_TYPES,
  TARGET_STATUSES,
  type SprintPhase,
  type SwarmTaskStatus,
  type TargetStatus,
} from '../../lib/mission-types'
import type { SwarmTask } from '../../lib/mission-types'

/* ---- Constants ---- */

const SPRINT_LABELS: Record<SprintPhase, string> = {
  brief: 'Kickoff',
  plan: 'Plan',
  execute: 'Execute',
  retrospect: 'Review',
  done: 'Done',
}

const STATUS_BADGE_TONE: Record<string, 'success' | 'warning' | 'secondary'> = {
  active: 'success',
  draft: 'secondary',
  completed: 'warning',
}

function taskStatusIcon(status: SwarmTaskStatus) {
  switch (status) {
    case 'done':
      return <CheckCircle2 className="h-3.5 w-3.5 text-success" />
    case 'running':
      return <Clock className="h-3.5 w-3.5 text-[var(--centurion-gold)]" />
    case 'blocked':
      return <AlertCircle className="h-3.5 w-3.5 text-destructive" />
    default:
      return <Circle className="h-3.5 w-3.5 text-muted-foreground hover:text-foreground" />
  }
}

/* ---- Inline helpers ---- */

function completionPct(tasks: { status: SwarmTaskStatus }[]): number {
  if (tasks.length === 0) return 0
  const done = tasks.filter((t) => t.status === 'done').length
  return Math.round((done / tasks.length) * 100)
}

function taskCounts(tasks: { status: SwarmTaskStatus }[]) {
  const done = tasks.filter((t) => t.status === 'done').length
  return { done, total: tasks.length }
}

function guessTargetType(status: TargetStatus): 'action' | 'major' | 'primary' {
  if (status === 'complete') return 'primary'
  if (status === 'in_progress') return 'major'
  return 'action'
}

/* ---- Props ---- */

interface ProjectPageProps {
  projectId: string
}

/* ---- Page (self-wrapping in provider) ---- */

export default function ProjectPage({ projectId }: ProjectPageProps) {
  return (
    <MissionStoreProvider>
      <ProjectPageInner projectId={projectId} />
    </MissionStoreProvider>
  )
}

/* ---- Page inner (has store access) ---- */

function ProjectPageInner({ projectId }: ProjectPageProps) {
  const {
    getProject,
    getTargets,
    getTasks,
    createTarget,
    updateTarget,
    createTask,
    updateTask,
  } = useMissionStore()

  const project = useMemo(() => getProject(projectId), [projectId, getProject])
  const targets = useMemo(() => getTargets(projectId), [projectId, getTargets])
  const allTasks = useMemo(() => getTasks(projectId), [projectId, getTasks])

  // ── New target form state ────────────────────────────────────────
  const [newTargetTitle, setNewTargetTitle] = useState('')
  const [addingTarget, setAddingTarget] = useState(false)
  const [showAddTarget, setShowAddTarget] = useState(false)

  // ── Expanded target (task drill-down) ────────────────────────────
  const [expandedTarget, setExpandedTarget] = useState<string | null>(null)
  const [newTaskTitle, setNewTaskTitle] = useState('')

  // ── Index tasks by target_id ─────────────────────────────────────
  const tasksByTarget = useMemo(() => {
    const map: Record<string, SwarmTask[]> = {}
    for (const task of allTasks) {
      const tid = task.target_id ?? '__unassigned__'
      if (!map[tid]) map[tid] = []
      map[tid].push(task)
    }
    return map
  }, [allTasks])

  // ── Metrics ──────────────────────────────────────────────────────
  const metrics = useMemo(() => {
    const totalTargets = targets.length
    const completeTargets = targets.filter((t) => t.status === 'complete').length
    const targetPct = totalTargets > 0
      ? Math.round((completeTargets / totalTargets) * 100)
      : 0
    const { done, total } = taskCounts(allTasks)
    const pct = completionPct(allTasks)

    return { totalTargets, completeTargets, targetPct, totalTasks: total, doneTasks: done, pct }
  }, [targets, allTasks])

  // ── Handlers ─────────────────────────────────────────────────────

  const handleAddTarget = useCallback(() => {
    const title = newTargetTitle.trim()
    if (!title) return
    setAddingTarget(true)
    try {
      createTarget({
        customer_id: 'local',
        project_id: projectId,
        sequence_number: targets.length + 1,
        title,
        action: null,
        target_type: guessTargetType('not_started'),
        status: 'not_started',
        assignee_install_id: null,
        due_date: null,
        start_date: null,
        change_date: null,
        stop_date: null,
        completed_at: null,
      })
      setNewTargetTitle('')
      setShowAddTarget(false)
    } finally {
      setAddingTarget(false)
    }
  }, [newTargetTitle, projectId, targets.length, createTarget])

  const handleToggleComplete = useCallback(
    (targetId: string, currentStatus: TargetStatus) => {
      const nextStatus: TargetStatus =
        currentStatus === 'complete' ? 'in_progress' : 'complete'
      updateTarget(targetId, {
        status: nextStatus,
        ...(nextStatus === 'complete' ? { completed_at: new Date().toISOString() } : {}),
      })
    },
    [updateTarget],
  )

  const toggleExpand = useCallback(
    (targetId: string) => {
      setExpandedTarget((prev) => (prev === targetId ? null : targetId))
      setNewTaskTitle('')
    },
    [],
  )

  const handleAddTask = useCallback(
    (targetId: string) => {
      if (!newTaskTitle.trim()) return
      const targetTasks = tasksByTarget[targetId] ?? []
      createTask({
        customer_id: 'local',
        project_id: projectId,
        target_id: targetId,
        title: newTaskTitle.trim(),
        body: null,
        status: 'todo',
        assignee_install_id: null,
        sort_order: targetTasks.length,
        result: null,
      })
      setNewTaskTitle('')
    },
    [newTaskTitle, projectId, tasksByTarget, createTask],
  )

  const cycleTaskStatus = useCallback(
    (taskId: string) => {
      const task = allTasks.find((t) => t.id === taskId)
      if (!task) return
      const cycle: Record<SwarmTaskStatus, SwarmTaskStatus> = {
        todo: 'ready',
        ready: 'running',
        running: 'done',
        done: 'todo',
        blocked: 'todo',
      }
      updateTask(taskId, { status: cycle[task.status] ?? 'todo' })
    },
    [allTasks, updateTask],
  )

  // ── 404: project not found ───────────────────────────────────────

  if (!project) {
    return (
      <div className="flex flex-col gap-6">
        <Card>
          <CardContent className="py-12 text-center text-sm text-muted-foreground">
            <p>Project not found.</p>
          </CardContent>
        </Card>
      </div>
    )
  }

  // ── Render ───────────────────────────────────────────────────────

  return (
    <div className="flex flex-col gap-6">

      {/* ── Breadcrumb / Back link ──────────────────────────────── */}
      <a
        href="/mission"
        className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors w-fit"
      >
        <ArrowLeft className="h-3 w-3" />
        Back to Portfolio
      </a>

      {/* ── Project header ──────────────────────────────────────── */}
      <div className="flex flex-col gap-2">
        <p className="font-mondwest text-display text-xs tracking-[0.12em] text-muted-foreground flex items-center gap-2">
          <Sparkles className="h-3 w-3" />
          Mission Control
        </p>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0 flex-1">
            <h1 className="text-xl font-semibold normal-case text-foreground flex items-center gap-2 flex-wrap">
              {project.title}
              <Badge tone={STATUS_BADGE_TONE[project.status] ?? 'secondary'}>
                {project.status}
              </Badge>
              <Badge tone="outline" className="text-[10px]">
                {SPRINT_LABELS[project.sprint_phase]}
              </Badge>
            </h1>
            {project.purpose && (
              <p className="mt-1 max-w-2xl text-sm text-muted-foreground normal-case">
                {project.purpose}
              </p>
            )}
          </div>
        </div>
      </div>

      {/* ── Summary metrics ──────────────────────────────────────── */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {/* Targets */}
        <div className="rounded-lg border border-border bg-card/60 p-4">
          <p className="text-xs font-medium uppercase tracking-wider text-muted-foreground flex items-center gap-1.5">
            <Target className="h-3 w-3" />
            Targets
          </p>
          <p className="mt-1 text-2xl font-semibold tabular-nums">
            {metrics.totalTargets}
          </p>
          {metrics.totalTargets > 0 && (
            <p className="mt-0.5 text-xs text-muted-foreground">
              {metrics.completeTargets} complete ({metrics.targetPct}%)
            </p>
          )}
        </div>

        {/* Tasks done */}
        <div className="rounded-lg border border-border bg-card/60 p-4">
          <p className="text-xs font-medium uppercase tracking-wider text-muted-foreground flex items-center gap-1.5">
            <CheckCircle2 className="h-3 w-3 text-success" />
            Tasks Done
          </p>
          <p className="mt-1 text-2xl font-semibold tabular-nums">
            {metrics.doneTasks}/{metrics.totalTasks}
          </p>
          {metrics.totalTasks > 0 && (
            <p className="mt-0.5 text-xs text-muted-foreground">
              {metrics.pct}% complete
            </p>
          )}
        </div>

        {/* Completion bar */}
        <div className="rounded-lg border border-border bg-card/60 p-4 sm:col-span-2">
          <p className="text-xs font-medium uppercase tracking-wider text-muted-foreground flex items-center gap-1.5">
            <ListChecks className="h-3 w-3" />
            Overall Progress
          </p>
          <div className="mt-2 flex items-center gap-2">
            <div className="flex-1 h-2 rounded-full bg-[color-mix(in_srgb,var(--midground-base)_12%,var(--background-base))] overflow-hidden">
              <div
                className="h-full rounded-full bg-[var(--centurion-gold)] transition-all duration-500"
                style={{ width: `${metrics.pct}%` }}
              />
            </div>
            <span className="tabular-nums text-sm font-semibold text-[var(--centurion-gold)] shrink-0">
              {metrics.pct}%
            </span>
          </div>
        </div>
      </div>

      {/* ── Target list ────────────────────────────────────────── */}
      <div className="flex flex-col gap-2">
        <div className="flex items-center justify-between">
          <h2 className="font-mondwest text-display text-xs tracking-[0.12em] text-muted-foreground flex items-center gap-2">
            <Target className="h-3.5 w-3.5" />
            Target Sequence
            <span className="text-xs font-normal">({targets.length})</span>
          </h2>
          {!showAddTarget && (
            <Button
              ghost
              size="sm"
              className="text-xs uppercase"
              onClick={() => setShowAddTarget(true)}
            >
              <Plus className="h-3 w-3 mr-1" />
              Add Target
            </Button>
          )}
        </div>

        {targets.length === 0 && !showAddTarget ? (
          <Card>
            <CardContent className="py-8 text-center text-sm text-muted-foreground">
              <p>No targets yet. Add your first target to define the mission sequence.</p>
            </CardContent>
          </Card>
        ) : (
          <div className="space-y-3">
            {targets.map((target) => {
              const typeMeta = TARGET_TYPES.find((t) => t.key === target.target_type)
              const statusMeta = TARGET_STATUSES.find((s) => s.key === target.status)
              const targetTasks = tasksByTarget[target.id] ?? []
              const isExpanded = expandedTarget === target.id
              const { done, total } = taskCounts(targetTasks)

              return (
                <div
                  key={target.id}
                  className={cn(
                    'rounded-lg border border-border transition-all bg-card/40',
                    target.status === 'complete' && 'opacity-80',
                    isExpanded && 'ring-1 ring-[var(--centurion-gold)]/20',
                  )}
                >
                  {/* ── Target card header (clickable to expand) ── */}
                  <button
                    onClick={() => toggleExpand(target.id)}
                    className={cn(
                      'w-full flex items-start gap-3 p-4 text-left cursor-pointer',
                      'hover:bg-muted/30 transition-colors',
                      'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--centurion-gold)]',
                    )}
                  >
                    <span className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-muted font-mono text-xs font-medium tabular-nums">
                      {target.sequence_number}
                    </span>

                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <p
                          className={cn(
                            'text-sm font-medium normal-case',
                            target.status === 'complete' && 'text-muted-foreground line-through',
                          )}
                        >
                          {target.title}
                        </p>
                        {typeMeta && (
                          <span className={cn('rounded px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide', typeMeta.color)}>
                            {typeMeta.label}
                          </span>
                        )}
                        {statusMeta && (
                          <span className={cn('rounded px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide', statusMeta.color)}>
                            {statusMeta.label}
                          </span>
                        )}
                        {total > 0 && (
                          <span className="text-[10px] text-muted-foreground tabular-nums">
                            {done}/{total} tasks
                          </span>
                        )}
                      </div>

                      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 mt-1">
                        {target.action && (
                          <p className="text-xs text-muted-foreground normal-case line-clamp-1">
                            {target.action}
                          </p>
                        )}
                        {target.due_date && (
                          <p className="text-[10px] text-muted-foreground tabular-nums flex items-center gap-1">
                            <Clock className="h-2.5 w-2.5" />
                            Due {isoTimeAgo(target.due_date)}
                          </p>
                        )}
                      </div>
                    </div>

                    {/* ── Quick actions ──────────────────────────── */}
                    <div className="shrink-0 flex items-center gap-1" onClick={(e) => e.stopPropagation()}>
                      <Button
                        ghost
                        size="icon"
                        className={cn(
                          'h-7 w-7',
                          target.status === 'complete'
                            ? 'text-muted-foreground'
                            : 'text-success',
                        )}
                        title={target.status === 'complete' ? 'Reopen target' : 'Mark target complete'}
                        onClick={() => handleToggleComplete(target.id, target.status)}
                      >
                        {target.status === 'complete'
                          ? <Clock className="h-3.5 w-3.5" />
                          : <CheckCircle2 className="h-3.5 w-3.5" />
                        }
                      </Button>
                    </div>
                  </button>

                  {/* ── Expanded: tasks inside target ─────────────── */}
                  {isExpanded && (
                    <div className="border-t border-border px-4 py-3 space-y-2">
                      {targetTasks.length === 0 && (
                        <p className="text-xs text-muted-foreground text-center py-2">
                          No tasks yet for this target
                        </p>
                      )}

                      {targetTasks.map((task) => (
                        <div
                          key={task.id}
                          className={cn(
                            'flex items-start gap-2 rounded-md border border-border/50 bg-muted/20 p-2.5 transition-all',
                            task.status === 'done' && 'opacity-60',
                            task.status === 'running' && 'border-[var(--centurion-gold)]/30',
                            task.status === 'blocked' && 'border-destructive/30',
                          )}
                        >
                          <button
                            onClick={() => cycleTaskStatus(task.id)}
                            className="mt-0.5 shrink-0 rounded-full transition-colors"
                            title={`Status: ${task.status}. Click to cycle.`}
                          >
                            {taskStatusIcon(task.status)}
                          </button>

                          <div className="min-w-0 flex-1">
                            <div className="flex items-center gap-2">
                              <span
                                className={cn(
                                  'text-xs',
                                  task.status === 'done' && 'text-muted-foreground line-through',
                                )}
                              >
                                {task.title}
                              </span>
                              <Badge
                                tone={
                                  task.status === 'done'
                                    ? 'success'
                                    : task.status === 'running'
                                      ? 'warning'
                                      : task.status === 'blocked'
                                        ? 'destructive'
                                        : 'outline'
                                }
                                className="text-[9px] px-1 py-0"
                              >
                                {task.status}
                              </Badge>
                            </div>
                            {task.body && (
                              <p className="text-[10px] text-muted-foreground mt-0.5 line-clamp-1">
                                {task.body}
                              </p>
                            )}
                          </div>

                          <button
                            onClick={() => {
                              // Remove task from target by setting target_id to null
                              updateTask(task.id, { target_id: null })
                            }}
                            className="h-6 w-6 shrink-0 flex items-center justify-center text-muted-foreground hover:text-destructive transition-colors rounded"
                            title="Remove from target"
                          >
                            <X className="h-3 w-3" />
                          </button>
                        </div>
                      ))}

                      {/* ── Add task inline ──────────────────────── */}
                      <div className="flex items-center gap-2 pt-1">
                        <Input
                          placeholder="Add a task..."
                          value={newTaskTitle}
                          onChange={(e) => setNewTaskTitle(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter') handleAddTask(target.id)
                          }}
                          className="h-7 text-xs"
                        />
                        <Button
                          ghost
                          size="icon"
                          className="h-7 w-7 shrink-0"
                          onClick={() => handleAddTask(target.id)}
                          disabled={!newTaskTitle.trim()}
                        >
                          <Plus className="h-3.5 w-3.5" />
                        </Button>
                      </div>
                    </div>
                  )}
                </div>
              )
            })}

            {/* ── Inline Add Target form ──────────────────────────── */}
            {showAddTarget && (
              <div className="rounded-lg border border-dashed border-border bg-card/20 p-4 space-y-3">
                <p className="text-xs font-medium text-muted-foreground uppercase tracking-wider">
                  New Target
                </p>
                <Input
                  autoFocus
                  placeholder="Target title..."
                  value={newTargetTitle}
                  onChange={(e) => setNewTargetTitle(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') handleAddTarget()
                    if (e.key === 'Escape') {
                      setShowAddTarget(false)
                      setNewTargetTitle('')
                    }
                  }}
                  className="text-sm"
                />
                <div className="flex items-center gap-2 justify-end">
                  <Button
                    ghost
                    size="sm"
                    className="text-xs"
                    onClick={() => {
                      setShowAddTarget(false)
                      setNewTargetTitle('')
                    }}
                  >
                    Cancel
                  </Button>
                  <Button
                    size="sm"
                    className="text-xs uppercase"
                    onClick={handleAddTarget}
                    disabled={addingTarget || !newTargetTitle.trim()}
                  >
                    {addingTarget ? 'Adding...' : 'Add Target'}
                  </Button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  )
}
