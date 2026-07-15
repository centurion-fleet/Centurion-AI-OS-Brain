/* ------------------------------------------------------------------ */
/*  Mission Control — React context + provider for local state         */
/*  Uses localStorage for persistence. No Supabase.                    */
/*  Ported from mission/context.tsx patterns.                           */
/* ------------------------------------------------------------------ */

import {
  createContext,
  useContext,
  useCallback,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import type {
  SwarmProject,
  SwarmTarget,
  SwarmTask,
  SwarmSummary,
} from './mission-types'
import {
  fetchSwarmSync,
  normalizeSwarmProjects,
  normalizeSwarmTargets,
  normalizeSwarmTasks,
  swarmsFromSwarmProjects,
} from './swarm-sync'

/* ---- Storage key ---- */

const STORAGE_KEY = 'centurion-mission-data'

/* ---- Stored shape ---- */

interface StoredData {
  projects: SwarmProject[]
  targets: SwarmTarget[]
  tasks: SwarmTask[]
  swarms: SwarmSummary[]
  syncSource: 'brain' | 'portal' | 'local'
}

/* ---- Context value shape ---- */

interface MissionStoreValue {
  projects: SwarmProject[]
  targets: SwarmTarget[]
  tasks: SwarmTask[]
  swarms: SwarmSummary[]
  syncSource: 'brain' | 'portal' | 'local'
  syncError: string | null
  isSyncing: boolean
  refreshSync: () => Promise<void>

  // Projects
  createProject: (project: Omit<SwarmProject, 'id' | 'created_at' | 'updated_at'>) => SwarmProject
  getProjects: () => SwarmProject[]
  getProject: (id: string) => SwarmProject | undefined
  updateProject: (id: string, patch: Partial<SwarmProject>) => void
  deleteProject: (id: string) => void

  // Targets
  createTarget: (target: Omit<SwarmTarget, 'id' | 'created_at' | 'updated_at'>) => SwarmTarget
  getTargets: (projectId?: string) => SwarmTarget[]
  updateTarget: (id: string, patch: Partial<SwarmTarget>) => void
  reorderTargets: (projectId: string, orderedIds: string[]) => void

  // Tasks
  createTask: (task: Omit<SwarmTask, 'id' | 'created_at' | 'updated_at'>) => SwarmTask
  getTasks: (projectId?: string, targetId?: string) => SwarmTask[]
  updateTask: (id: string, patch: Partial<SwarmTask>) => void
  reorderTasks: (projectId: string, orderedIds: string[]) => void
}

const MissionStoreContext = createContext<MissionStoreValue | null>(null)

/* ---- Helpers ---- */

function generateId(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`
}

function nowISO(): string {
  return new Date().toISOString()
}

/* ---- Default / seed state (empty by default) ---- */

const EMPTY_DATA: StoredData = {
  projects: [],
  targets: [],
  tasks: [],
  swarms: [],
  syncSource: 'local',
}

/* ---- Provider ---- */

export function MissionStoreProvider({ children }: { children: ReactNode }) {
  const [data, setData] = useState<StoredData>(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      if (stored) {
        const parsed = JSON.parse(stored) as StoredData
        if (parsed.projects?.length || parsed.targets?.length || parsed.tasks?.length) {
          return {
            projects: parsed.projects ?? [],
            targets: parsed.targets ?? [],
            tasks: parsed.tasks ?? [],
            swarms: parsed.swarms ?? swarmsFromSwarmProjects(parsed.projects ?? [], parsed.tasks ?? []),
            syncSource: parsed.syncSource ?? 'local',
          }
        }
      }
    } catch {
      // ignore parse / localStorage errors
    }
    return EMPTY_DATA
  })
  const [syncError, setSyncError] = useState<string | null>(null)
  const [isSyncing, setIsSyncing] = useState(false)

  const refreshSync = useCallback(async () => {
    setIsSyncing(true)
    try {
      const payload = await fetchSwarmSync()
      setSyncError(payload.ok ? null : payload.message ?? 'Mission Control not connected')
      if (payload.ok && (payload.projects.length > 0 || payload.swarms.length > 0)) {
        const projects = normalizeSwarmProjects(payload.projects)
        const targets = normalizeSwarmTargets(payload.targets)
        const tasks = normalizeSwarmTasks(payload.tasks)
        const swarms =
          payload.swarms.length > 0
            ? payload.swarms
            : swarmsFromSwarmProjects(projects, tasks)
        setData({ projects, targets, tasks, swarms, syncSource: payload.source === 'local' ? 'local' : 'brain' })
      }
    } catch (err) {
      setSyncError(err instanceof Error ? err.message : 'Sync failed')
    } finally {
      setIsSyncing(false)
    }
  }, [])

  useEffect(() => {
    void refreshSync()
  }, [refreshSync])

  // Persist to localStorage on every change
  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(data))
    } catch {
      // localStorage full or unavailable — silently continue
    }
  }, [data])

  const { projects, targets, tasks, swarms, syncSource } = data

  // ── Projects ────────────────────────────────────────────────────

  const createProject = useCallback(
    (project: Omit<SwarmProject, 'id' | 'created_at' | 'updated_at'>): SwarmProject => {
      const now = nowISO()
      const entry: SwarmProject = {
        ...project,
        id: generateId(),
        created_at: now,
        updated_at: now,
      }
      setData((prev) => ({ ...prev, projects: [...prev.projects, entry] }))
      return entry
    },
    [],
  )

  const getProjects = useCallback((): SwarmProject[] => {
    return projects
  }, [projects])

  const getProject = useCallback(
    (id: string): SwarmProject | undefined => {
      return projects.find((p) => p.id === id)
    },
    [projects],
  )

  const updateProject = useCallback((id: string, patch: Partial<SwarmProject>) => {
    setData((prev) => ({
      ...prev,
      projects: prev.projects.map((p) =>
        p.id === id ? { ...p, ...patch, updated_at: nowISO() } : p,
      ),
    }))
  }, [])

  const deleteProject = useCallback((id: string) => {
    setData((prev) => ({
      ...prev,
      projects: prev.projects.filter((p) => p.id !== id),
      targets: prev.targets.filter((t) => t.project_id !== id),
      tasks: prev.tasks.filter((t) => t.project_id !== id),
    }))
  }, [])

  // ── Targets ─────────────────────────────────────────────────────

  const createTarget = useCallback(
    (target: Omit<SwarmTarget, 'id' | 'created_at' | 'updated_at'>): SwarmTarget => {
      const now = nowISO()
      const entry: SwarmTarget = {
        ...target,
        id: generateId(),
        created_at: now,
        updated_at: now,
      }
      setData((prev) => ({ ...prev, targets: [...prev.targets, entry] }))
      return entry
    },
    [],
  )

  const getTargets = useCallback(
    (projectId?: string): SwarmTarget[] => {
      let filtered = targets
      if (projectId) {
        filtered = filtered.filter((t) => t.project_id === projectId)
      }
      return [...filtered].sort((a, b) => a.sequence_number - b.sequence_number)
    },
    [targets],
  )

  const updateTarget = useCallback((id: string, patch: Partial<SwarmTarget>) => {
    setData((prev) => ({
      ...prev,
      targets: prev.targets.map((t) =>
        t.id === id ? { ...t, ...patch, updated_at: nowISO() } : t,
      ),
    }))
  }, [])

  const reorderTargets = useCallback((projectId: string, orderedIds: string[]) => {
    setData((prev) => {
      const projectTargets = prev.targets.filter((t) => t.project_id === projectId)
      const otherTargets = prev.targets.filter((t) => t.project_id !== projectId)
      const idToIndex = new Map(orderedIds.map((id, i) => [id, i]))
      const reordered = projectTargets
        .filter((t) => idToIndex.has(t.id))
        .sort((a, b) => (idToIndex.get(a.id) ?? 0) - (idToIndex.get(b.id) ?? 0))
        .map((t, i) => ({ ...t, sequence_number: i + 1, updated_at: nowISO() }))
      return {
        ...prev,
        targets: [...otherTargets, ...reordered],
      }
    })
  }, [])

  // ── Tasks ───────────────────────────────────────────────────────

  const createTask = useCallback(
    (task: Omit<SwarmTask, 'id' | 'created_at' | 'updated_at'>): SwarmTask => {
      const now = nowISO()
      const entry: SwarmTask = {
        ...task,
        id: generateId(),
        created_at: now,
        updated_at: now,
      }
      setData((prev) => ({ ...prev, tasks: [...prev.tasks, entry] }))
      return entry
    },
    [],
  )

  const getTasks = useCallback(
    (projectId?: string, targetId?: string): SwarmTask[] => {
      let filtered = tasks
      if (projectId) {
        filtered = filtered.filter((t) => t.project_id === projectId)
      }
      if (targetId) {
        filtered = filtered.filter((t) => t.target_id === targetId)
      }
      return [...filtered].sort((a, b) => a.sort_order - b.sort_order)
    },
    [tasks],
  )

  const updateTask = useCallback((id: string, patch: Partial<SwarmTask>) => {
    setData((prev) => ({
      ...prev,
      tasks: prev.tasks.map((t) =>
        t.id === id ? { ...t, ...patch, updated_at: nowISO() } : t,
      ),
    }))
  }, [])

  const reorderTasks = useCallback((projectId: string, orderedIds: string[]) => {
    setData((prev) => {
      const projectTasks = prev.tasks.filter((t) => t.project_id === projectId)
      const otherTasks = prev.tasks.filter((t) => t.project_id !== projectId)
      const idToIndex = new Map(orderedIds.map((id, i) => [id, i]))
      const reordered = projectTasks
        .filter((t) => idToIndex.has(t.id))
        .sort((a, b) => (idToIndex.get(a.id) ?? 0) - (idToIndex.get(b.id) ?? 0))
        .map((t, i) => ({ ...t, sort_order: i + 1, updated_at: nowISO() }))
      return {
        ...prev,
        tasks: [...otherTasks, ...reordered],
      }
    })
  }, [])

  // ── Memoised context value ──────────────────────────────────────

  const value = useMemo<MissionStoreValue>(
    () => ({
      projects,
      targets,
      tasks,
      swarms,
      syncSource,
      syncError,
      isSyncing,
      refreshSync,

      createProject,
      getProjects,
      getProject,
      updateProject,
      deleteProject,

      createTarget,
      getTargets,
      updateTarget,
      reorderTargets,

      createTask,
      getTasks,
      updateTask,
      reorderTasks,
    }),
    [
      projects,
      targets,
      tasks,
      swarms,
      syncSource,
      syncError,
      isSyncing,
      refreshSync,

      createProject,
      getProjects,
      getProject,
      updateProject,
      deleteProject,

      createTarget,
      getTargets,
      updateTarget,
      reorderTargets,

      createTask,
      getTasks,
      updateTask,
      reorderTasks,
    ],
  )

  return (
    <MissionStoreContext.Provider value={value}>
      {children}
    </MissionStoreContext.Provider>
  )
}

/* ---- Hook ---- */

export function useMissionStore(): MissionStoreValue {
  const ctx = useContext(MissionStoreContext)
  if (!ctx) {
    throw new Error('useMissionStore must be used within <MissionStoreProvider>')
  }
  return ctx
}
