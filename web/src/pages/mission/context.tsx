/* ------------------------------------------------------------------ */
/*  Mission Control — local React context for state management        */
/*  No Supabase. Local state only — persisted to localStorage.        */
/* ------------------------------------------------------------------ */

import {
  createContext,
  useContext,
  useCallback,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import type {
  MissionProject,
  MissionTarget,
  MissionTask,
  SwarmTaskStatus,
  TargetType,
  TargetStatus,
} from "./types";

/* ---- Seed data ---- */

const SEED_PROJECTS: MissionProject[] = [
  {
    id: "proj-1",
    title: "Centurion Portal Redesign",
    purpose: "Modernize the user-facing portal with an improved layout and accessibility",
    slug: "centurion-portal-redesign",
    status: "active",
    sprint_phase: "execute",
    sort_order: 0,
    createdAt: "2026-06-01T00:00:00Z",
    updatedAt: "2026-07-01T00:00:00Z",
  },
  {
    id: "proj-2",
    title: "Plugin SDK v2",
    purpose: "Build the second generation of the plugin development kit",
    slug: "plugin-sdk-v2",
    status: "active",
    sprint_phase: "plan",
    sort_order: 1,
    createdAt: "2026-06-15T00:00:00Z",
    updatedAt: "2026-07-02T00:00:00Z",
  },
  {
    id: "proj-3",
    title: "Documentation Overhaul",
    purpose: "Rewrite and reorganize all developer documentation",
    slug: "docs-overhaul",
    status: "draft",
    sprint_phase: "brief",
    sort_order: 2,
    createdAt: "2026-06-20T00:00:00Z",
    updatedAt: "2026-06-20T00:00:00Z",
  },
];

const SEED_TARGETS: MissionTarget[] = [
  { id: "tgt-1", projectId: "proj-1", sequenceNumber: 1, title: "Define new component library", action: "Audit existing components and design new spec", targetType: "primary", status: "complete", assignee: null, dueDate: null, createdAt: "2026-06-01T00:00:00Z", updatedAt: "2026-06-10T00:00:00Z" },
  { id: "tgt-2", projectId: "proj-1", sequenceNumber: 2, title: "Implement core layout shell", action: "Build the app shell with sidebar, header, and content area", targetType: "action", status: "in_progress", assignee: null, dueDate: null, createdAt: "2026-06-05T00:00:00Z", updatedAt: "2026-06-15T00:00:00Z" },
  { id: "tgt-3", projectId: "proj-1", sequenceNumber: 3, title: "Accessibility audit pass", action: "Run axe-core scans on all pages", targetType: "data", status: "not_started", assignee: null, dueDate: null, createdAt: "2026-06-10T00:00:00Z", updatedAt: "2026-06-10T00:00:00Z" },
  { id: "tgt-4", projectId: "proj-2", sequenceNumber: 1, title: "Design plugin manifest schema", action: "Define the v2 manifest YAML spec", targetType: "primary", status: "in_progress", assignee: null, dueDate: null, createdAt: "2026-06-15T00:00:00Z", updatedAt: "2026-06-20T00:00:00Z" },
  { id: "tgt-5", projectId: "proj-2", sequenceNumber: 2, title: "Build plugin loader", action: "Implement the runtime plugin loader", targetType: "major", status: "not_started", assignee: null, dueDate: null, createdAt: "2026-06-20T00:00:00Z", updatedAt: "2026-06-20T00:00:00Z" },
  { id: "tgt-6", projectId: "proj-3", sequenceNumber: 1, title: "Content audit", action: "Catalog all existing docs", targetType: "data", status: "not_started", assignee: null, dueDate: null, createdAt: "2026-06-20T00:00:00Z", updatedAt: "2026-06-20T00:00:00Z" },
];

const SEED_TASKS: MissionTask[] = [
  { id: "task-1", projectId: "proj-1", targetId: "tgt-1", title: "Audit existing components", body: "Review all current UI components", status: "done", assignee: null, sortOrder: 0, result: null, createdAt: "2026-06-01T00:00:00Z", updatedAt: "2026-06-05T00:00:00Z" },
  { id: "task-2", projectId: "proj-1", targetId: "tgt-1", title: "Write design spec", body: "Document the new component library spec", status: "done", assignee: null, sortOrder: 1, result: null, createdAt: "2026-06-05T00:00:00Z", updatedAt: "2026-06-10T00:00:00Z" },
  { id: "task-3", projectId: "proj-1", targetId: "tgt-2", title: "Create app shell layout", body: "Sidebar + header + main content", status: "running", assignee: null, sortOrder: 0, result: null, createdAt: "2026-06-10T00:00:00Z", updatedAt: "2026-06-15T00:00:00Z" },
  { id: "task-4", projectId: "proj-1", targetId: "tgt-2", title: "Wire up navigation routing", body: "React Router integration", status: "todo", assignee: null, sortOrder: 1, result: null, createdAt: "2026-06-12T00:00:00Z", updatedAt: "2026-06-12T00:00:00Z" },
  { id: "task-5", projectId: "proj-1", targetId: null, title: "Fix header z-index bug", body: "Header overlapping sidebar on mobile", status: "ready", assignee: null, sortOrder: 2, result: null, createdAt: "2026-06-14T00:00:00Z", updatedAt: "2026-06-14T00:00:00Z" },
  { id: "task-6", projectId: "proj-1", targetId: "tgt-2", title: "Responsive breakpoints", body: "Ensure layout works at all viewports", status: "blocked", assignee: null, sortOrder: 3, result: null, createdAt: "2026-06-15T00:00:00Z", updatedAt: "2026-06-16T00:00:00Z" },
  { id: "task-7", projectId: "proj-2", targetId: "tgt-4", title: "Define manifest fields", body: "List all required and optional fields", status: "running", assignee: null, sortOrder: 0, result: null, createdAt: "2026-06-16T00:00:00Z", updatedAt: "2026-06-18T00:00:00Z" },
  { id: "task-8", projectId: "proj-2", targetId: "tgt-4", title: "Write YAML schema validator", body: "JSON schema for v2 manifests", status: "todo", assignee: null, sortOrder: 1, result: null, createdAt: "2026-06-18T00:00:00Z", updatedAt: "2026-06-18T00:00:00Z" },
  { id: "task-9", projectId: "proj-2", targetId: "tgt-5", title: "Implement PluginLoader class", body: "Core loading logic", status: "todo", assignee: null, sortOrder: 0, result: null, createdAt: "2026-06-20T00:00:00Z", updatedAt: "2026-06-20T00:00:00Z" },
  { id: "task-10", projectId: "proj-3", targetId: "tgt-6", title: "Scan docs directory", body: "List all .md files", status: "todo", assignee: null, sortOrder: 0, result: null, createdAt: "2026-06-20T00:00:00Z", updatedAt: "2026-06-20T00:00:00Z" },
];

/* ---- Storage key ---- */

const STORAGE_KEY = "centurion_mission_control";

interface StoredData {
  projects: MissionProject[];
  targets: MissionTarget[];
  tasks: MissionTask[];
}

/* ---- Context ---- */

interface MissionContextValue {
  projects: MissionProject[];
  targets: MissionTarget[];
  tasks: MissionTask[];

  // Projects
  addProject: (project: Omit<MissionProject, "id" | "createdAt" | "updatedAt">) => void;
  updateProject: (id: string, patch: Partial<MissionProject>) => void;
  deleteProject: (id: string) => void;

  // Targets
  getTargetsByProject: (projectId: string) => MissionTarget[];
  addTarget: (target: Omit<MissionTarget, "id" | "createdAt" | "updatedAt">) => void;
  updateTarget: (id: string, patch: Partial<MissionTarget>) => void;
  deleteTarget: (id: string) => void;

  // Tasks
  getTasksByProject: (projectId: string) => MissionTask[];
  getTasksByTarget: (targetId: string) => MissionTask[];
  addTask: (task: Omit<MissionTask, "id" | "createdAt" | "updatedAt">) => void;
  updateTask: (id: string, patch: Partial<MissionTask>) => void;
  deleteTask: (id: string) => void;
}

const MissionContext = createContext<MissionContextValue | null>(null);

function generateId(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
}

export function MissionProvider({ children }: { children: ReactNode }) {
  const [data, setData] = useState<StoredData>(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored) {
        const parsed = JSON.parse(stored) as StoredData;
        if (parsed.projects?.length) return parsed;
      }
    } catch {
      // ignore
    }
    return { projects: SEED_PROJECTS, targets: SEED_TARGETS, tasks: SEED_TASKS };
  });

  // Persist to localStorage on every change
  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
    } catch {
      // localStorage full or unavailable — silently continue
    }
  }, [data]);

  const { projects, targets, tasks } = data;

  // -- Projects --
  const addProject = useCallback(
    (project: Omit<MissionProject, "id" | "createdAt" | "updatedAt">) => {
      const now = new Date().toISOString();
      const entry: MissionProject = {
        ...project,
        id: generateId(),
        createdAt: now,
        updatedAt: now,
      };
      setData((prev) => ({ ...prev, projects: [...prev.projects, entry] }));
    },
    [],
  );

  const updateProject = useCallback((id: string, patch: Partial<MissionProject>) => {
    setData((prev) => ({
      ...prev,
      projects: prev.projects.map((p) =>
        p.id === id ? { ...p, ...patch, updatedAt: new Date().toISOString() } : p,
      ),
    }));
  }, []);

  const deleteProject = useCallback((id: string) => {
    setData((prev) => ({
      projects: prev.projects.filter((p) => p.id !== id),
      targets: prev.targets.filter((t) => t.projectId !== id),
      tasks: prev.tasks.filter((t) => t.projectId !== id),
    }));
  }, []);

  // -- Targets --
  const getTargetsByProject = useCallback(
    (projectId: string) => targets.filter((t) => t.projectId === projectId).sort((a, b) => a.sequenceNumber - b.sequenceNumber),
    [targets],
  );

  const addTarget = useCallback(
    (target: Omit<MissionTarget, "id" | "createdAt" | "updatedAt">) => {
      const now = new Date().toISOString();
      const entry: MissionTarget = {
        ...target,
        id: generateId(),
        createdAt: now,
        updatedAt: now,
      };
      setData((prev) => ({ ...prev, targets: [...prev.targets, entry] }));
    },
    [],
  );

  const updateTarget = useCallback((id: string, patch: Partial<MissionTarget>) => {
    setData((prev) => ({
      ...prev,
      targets: prev.targets.map((t) =>
        t.id === id ? { ...t, ...patch, updatedAt: new Date().toISOString() } : t,
      ),
    }));
  }, []);

  const deleteTarget = useCallback((id: string) => {
    setData((prev) => ({
      ...prev,
      targets: prev.targets.filter((t) => t.id !== id),
      tasks: prev.tasks.filter((t) => t.targetId !== id),
    }));
  }, []);

  // -- Tasks --
  const getTasksByProject = useCallback(
    (projectId: string) =>
      tasks.filter((t) => t.projectId === projectId).sort((a, b) => a.sortOrder - b.sortOrder),
    [tasks],
  );

  const getTasksByTarget = useCallback(
    (targetId: string) =>
      tasks.filter((t) => t.targetId === targetId).sort((a, b) => a.sortOrder - b.sortOrder),
    [tasks],
  );

  const addTask = useCallback(
    (task: Omit<MissionTask, "id" | "createdAt" | "updatedAt">) => {
      const now = new Date().toISOString();
      const entry: MissionTask = {
        ...task,
        id: generateId(),
        createdAt: now,
        updatedAt: now,
      };
      setData((prev) => ({ ...prev, tasks: [...prev.tasks, entry] }));
    },
    [],
  );

  const updateTask = useCallback((id: string, patch: Partial<MissionTask>) => {
    setData((prev) => ({
      ...prev,
      tasks: prev.tasks.map((t) =>
        t.id === id ? { ...t, ...patch, updatedAt: new Date().toISOString() } : t,
      ),
    }));
  }, []);

  const deleteTask = useCallback((id: string) => {
    setData((prev) => ({
      ...prev,
      tasks: prev.tasks.filter((t) => t.id !== id),
    }));
  }, []);

  const value = useMemo<MissionContextValue>(
    () => ({
      projects,
      targets,
      tasks,
      addProject,
      updateProject,
      deleteProject,
      getTargetsByProject,
      addTarget,
      updateTarget,
      deleteTarget,
      getTasksByProject,
      getTasksByTarget,
      addTask,
      updateTask,
      deleteTask,
    }),
    [
      projects,
      targets,
      tasks,
      addProject,
      updateProject,
      deleteProject,
      getTargetsByProject,
      addTarget,
      updateTarget,
      deleteTarget,
      getTasksByProject,
      getTasksByTarget,
      addTask,
      updateTask,
      deleteTask,
    ],
  );

  return <MissionContext.Provider value={value}>{children}</MissionContext.Provider>;
}

export function useMission(): MissionContextValue {
  const ctx = useContext(MissionContext);
  if (!ctx) throw new Error("useMission must be used within <MissionProvider>");
  return ctx;
}
