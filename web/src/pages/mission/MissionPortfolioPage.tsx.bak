/* ------------------------------------------------------------------ */
/*  Mission Control Portfolio Page — new data layer                    */
/*  Uses MissionStoreProvider from ../../lib/mission-store              */
/*  Forest/gold dark theme matching Centurion design system            */
/* ------------------------------------------------------------------ */

'use client'

import { useCallback, useLayoutEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  LayoutDashboard,
  Plus,
  Sparkles,
  Target,
  X,
} from 'lucide-react'
import { Badge } from '@centurion-fleet/ui/ui/components/badge'
import { Button } from '@centurion-fleet/ui/ui/components/button'
import { H2 } from '@/components/NouiTypography'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { usePageHeader } from '@/contexts/usePageHeader'
import { PluginSlot } from '@/plugins'
import { cn, themedBody } from '@/lib/utils'
import { MissionStoreProvider, useMissionStore } from '../../lib/mission-store'
import type { SwarmProject, SwarmTaskStatus, SprintPhase } from '../../lib/mission-types'

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

/* ---- Inline metric helpers ---- */

function taskCompletionPct(tasks: { status: SwarmTaskStatus }[]): number {
  if (tasks.length === 0) return 0
  const done = tasks.filter((t) => t.status === 'done').length
  return Math.round((done / tasks.length) * 100)
}

function taskCounts(tasks: { status: SwarmTaskStatus }[]) {
  const done = tasks.filter((t) => t.status === 'done').length
  const total = tasks.length
  return { done, total }
}

/* ---- Page (wraps itself in provider) ---- */

export default function MissionPortfolioPage() {
  return (
    <MissionStoreProvider>
      <MissionPortfolioPageInner />
    </MissionStoreProvider>
  )
}

/* ---- Page inner (has access to store) ---- */

function MissionPortfolioPageInner() {
  const navigate = useNavigate()
  const { setEnd } = usePageHeader()

  const { projects, targets, tasks, createProject } = useMissionStore()

  const [showCreate, setShowCreate] = useState(false)
  const [newTitle, setNewTitle] = useState('')
  const [newPurpose, setNewPurpose] = useState('')
  const [creating, setCreating] = useState(false)
  const closeCreate = useCallback(() => setShowCreate(false), [])

  // "New Project" button in the page header
  useLayoutEffect(() => {
    setEnd(
      <Button
        className="uppercase"
        size="sm"
        onClick={() => setShowCreate(true)}
        aria-label="New Project"
      >
        <Plus className="h-3.5 w-3.5 mr-1" />
        New Project
      </Button>,
    )
    return () => setEnd(null)
  }, [setEnd])

  // Index tasks by project id for efficient lookup
  const tasksByProject = useMemo(() => {
    const map: Record<string, { status: SwarmTaskStatus }[]> = {}
    for (const task of tasks) {
      if (!map[task.project_id]) map[task.project_id] = []
      map[task.project_id].push(task)
    }
    return map
  }, [tasks])

  // Index targets by project id
  const targetCountByProject = useMemo(() => {
    const map: Record<string, number> = {}
    for (const tgt of targets) {
      map[tgt.project_id] = (map[tgt.project_id] || 0) + 1
    }
    return map
  }, [targets])

  const handleCreate = useCallback(async () => {
    const title = newTitle.trim()
    if (!title) return
    setCreating(true)
    try {
      const project: Omit<SwarmProject, 'id' | 'created_at' | 'updated_at'> = {
        customer_id: 'local',
        program_id: null,
        title,
        purpose: newPurpose.trim() || null,
        slug: title.toLowerCase().replace(/\s+/g, '-'),
        status: 'draft',
        sprint_phase: 'brief',
        kanban_board_slug: null,
        workspace_path: null,
        checklist_viable: false,
        checklist_agreed: false,
        checklist_assigned: false,
        checklist_understood: false,
        checklist_resourced: false,
        checklist_coordinated: false,
        checklist_supervised: false,
        checklist_completed: false,
        checklist_reported: false,
        sort_order: projects.length,
      }
      createProject(project)
      setNewTitle('')
      setNewPurpose('')
      setShowCreate(false)
    } finally {
      setCreating(false)
    }
  }, [newTitle, newPurpose, createProject, projects.length])

  return (
    <div className="flex flex-col gap-6">
      <PluginSlot name="mission:top" />

      {/* ── Create Project Modal ────────────────────────────────── */}
      {showCreate && (
        <div
          className="fixed inset-0 z-[100] flex items-center justify-center bg-background/85 backdrop-blur-sm p-4"
          onClick={(e) => e.target === e.currentTarget && setShowCreate(false)}
          role="dialog"
          aria-modal="true"
          aria-labelledby="create-mission-title"
        >
          <div
            className={cn(
              themedBody,
              'relative w-full max-w-lg border border-border bg-card shadow-2xl flex flex-col',
            )}
          >
            <Button
              ghost
              size="icon"
              onClick={closeCreate}
              className="absolute right-2 top-2 text-muted-foreground hover:text-foreground"
              aria-label="Close"
            >
              <X />
            </Button>
            <header className="p-5 pb-3 border-b border-border">
              <h2
                id="create-mission-title"
                className="font-mondwest text-display text-base tracking-wider"
              >
                New Mission
              </h2>
            </header>
            <div className="p-5 grid gap-4">
              <div className="grid gap-2">
                <Label htmlFor="project-title">Title</Label>
                <Input
                  id="project-title"
                  autoFocus
                  placeholder="e.g. Portal Redesign"
                  value={newTitle}
                  onChange={(e) => setNewTitle(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') handleCreate()
                  }}
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="project-purpose">Purpose (optional)</Label>
                <textarea
                  id="project-purpose"
                  className="flex min-h-[80px] w-full border border-border bg-background/40 px-3 py-2 text-sm font-courier shadow-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-foreground/30 focus-visible:border-foreground/25"
                  placeholder="What is this project about?"
                  value={newPurpose}
                  onChange={(e) => setNewPurpose(e.target.value)}
                />
              </div>
              <div className="flex justify-end">
                <Button
                  className="uppercase"
                  size="sm"
                  onClick={handleCreate}
                  disabled={creating || !newTitle.trim()}
                >
                  {creating ? 'Creating...' : 'Create'}
                </Button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ── Portfolio header ─────────────────────────────────────── */}
      <div className="flex flex-col gap-2">
        <p className="font-mondwest text-display text-xs tracking-[0.12em] text-muted-foreground flex items-center gap-2">
          <Sparkles className="h-3 w-3" />
          Mission Control
        </p>
        <H2 variant="sm" className="flex items-center gap-2 text-foreground">
          <LayoutDashboard className="h-5 w-5" />
          Portfolio ({projects.length})
        </H2>
      </div>

      {/* ── Empty state / Project grid ───────────────────────────── */}
      {projects.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center text-sm text-muted-foreground">
            <p>No projects yet. Create your first mission to get started.</p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {projects.map((project) => {
            const projectTasks = tasksByProject[project.id] ?? []
            const { done, total } = taskCounts(projectTasks)
            const pct = taskCompletionPct(projectTasks)
            const tgtCount = targetCountByProject[project.id] ?? 0

            return (
              <button
                key={project.id}
                onClick={() => navigate(`/mission/${project.id}`)}
                className={cn(
                  'text-left w-full rounded-lg border border-border bg-card/80 p-5 transition-all',
                  'hover:ring-1 hover:ring-[var(--centurion-gold)]/40 hover:bg-card',
                  'cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--centurion-gold)]',
                )}
              >
                {/* Title row + status */}
                <div className="flex items-start justify-between gap-2">
                  <h3 className="font-semibold text-sm normal-case text-foreground truncate">
                    {project.title}
                  </h3>
                  <Badge tone={STATUS_BADGE_TONE[project.status] ?? 'secondary'}>
                    {project.status}
                  </Badge>
                </div>

                {/* Purpose */}
                {project.purpose && (
                  <p className="mt-1 line-clamp-2 text-xs text-muted-foreground normal-case">
                    {project.purpose}
                  </p>
                )}

                {/* Metrics row */}
                <div className="mt-3 flex flex-col gap-2">
                  {/* Sprint phase badge + target count */}
                  <div className="flex items-center gap-3 text-xs text-muted-foreground">
                    <Badge tone="outline">{SPRINT_LABELS[project.sprint_phase]}</Badge>
                    <span className="tabular-nums flex items-center gap-1">
                      <Target className="h-3 w-3" />
                      {tgtCount} target{tgtCount !== 1 ? 's' : ''}
                    </span>
                  </div>

                  {/* Task completion bar */}
                  {total > 0 && (
                    <div className="flex items-center gap-2">
                      <div className="flex-1 h-1.5 rounded-full bg-[color-mix(in_srgb,var(--midground-base)_12%,var(--background-base))] overflow-hidden">
                        <div
                          className="h-full rounded-full bg-[var(--centurion-gold)] transition-all duration-300"
                          style={{ width: `${pct}%` }}
                        />
                      </div>
                      <span className="tabular-nums text-[11px] text-muted-foreground shrink-0">
                        {done}/{total}
                      </span>
                    </div>
                  )}
                </div>
              </button>
            )
          })}
        </div>
      )}

      <PluginSlot name="mission:bottom" />
    </div>
  )
}
