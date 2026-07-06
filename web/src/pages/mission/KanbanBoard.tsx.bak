/* ------------------------------------------------------------------ */
/*  Kanban Board — simple task kanban with drag-free column view       */
/*  Ported from Centurion-website-v3/components/swarm/kanban-board.tsx */
/* ------------------------------------------------------------------ */

import { useState, useCallback } from "react";
import { Circle, CheckCircle2, Clock, AlertCircle, Plus, X } from "lucide-react";
import { Badge } from "@centurion-fleet/ui/ui/components/badge";
import { Button } from "@centurion-fleet/ui/ui/components/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { useMission } from "./context";
import { KANBAN_COLUMNS, type MissionTask, type SwarmTaskStatus } from "./types";

interface KanbanBoardProps {
  projectId: string;
  tasks: MissionTask[];
}

export function KanbanBoard({ projectId, tasks }: KanbanBoardProps) {
  const { addTask, updateTask, deleteTask } = useMission();
  const [addingToColumn, setAddingToColumn] = useState<SwarmTaskStatus | null>(null);
  const [newTitle, setNewTitle] = useState("");

  const handleAddTask = useCallback(
    (status: SwarmTaskStatus) => {
      if (!newTitle.trim()) return;
      const columnTasks = tasks.filter((t) => t.status === status);
      addTask({
        projectId,
        targetId: null,
        title: newTitle.trim(),
        body: null,
        status,
        assignee: null,
        sortOrder: columnTasks.length,
        result: null,
      });
      setNewTitle("");
      setAddingToColumn(null);
    },
    [newTitle, projectId, tasks, addTask],
  );

  const cycleStatus = useCallback(
    (task: MissionTask) => {
      const statuses: SwarmTaskStatus[] = ["todo", "ready", "running", "blocked", "done"];
      const idx = statuses.indexOf(task.status);
      const next = statuses[(idx + 1) % statuses.length];
      updateTask(task.id, { status: next });
    },
    [updateTask],
  );

  const getStatusIcon = (status: SwarmTaskStatus) => {
    switch (status) {
      case "done":
        return <CheckCircle2 className="h-3 w-3 text-success" />;
      case "running":
        return <Clock className="h-3 w-3 text-[var(--centurion-gold)]" />;
      case "blocked":
        return <AlertCircle className="h-3 w-3 text-destructive" />;
      default:
        return <Circle className="h-3 w-3 text-muted-foreground" />;
    }
  };

  return (
    <div className="flex flex-col gap-3">
      <h3 className="text-sm font-medium text-foreground flex items-center gap-2">
        <Clock className="h-3.5 w-3.5 text-muted-foreground" />
        Task Board
        <span className="text-xs text-muted-foreground font-normal">
          ({tasks.length} tasks)
        </span>
      </h3>

      <div className="flex gap-3 overflow-x-auto pb-2 lg:grid lg:grid-cols-5 lg:overflow-visible">
        {KANBAN_COLUMNS.map((col) => {
          const columnTasks = tasks
            .filter((t) => t.status === col.id)
            .sort((a, b) => a.sortOrder - b.sortOrder);
          const isRunning = col.id === "running" && columnTasks.length > 0;

          return (
            <div
              key={col.id}
              className={cn(
                "min-w-[220px] flex-1 rounded-lg border border-border bg-card/40 p-3 lg:min-w-0",
                isRunning && "ring-1 ring-[var(--centurion-gold)]/20",
              )}
            >
              {/* Column header */}
              <div className="mb-3 flex items-center justify-between">
                <h3
                  className={cn(
                    "text-xs font-medium uppercase tracking-wider text-foreground",
                    isRunning && "text-[var(--centurion-gold)]",
                  )}
                >
                  {col.label}
                </h3>
                <div className="flex items-center gap-1">
                  <span
                    className={cn(
                      "rounded-full px-2 py-0.5 text-xs tabular-nums",
                      columnTasks.length > 0
                        ? "bg-[var(--centurion-gold)]/15 text-[var(--centurion-gold)]"
                        : "text-muted-foreground",
                    )}
                  >
                    {columnTasks.length}
                  </span>
                  <Button
                    ghost
                    size="icon"
                    className="h-6 w-6 text-muted-foreground hover:text-foreground"
                    onClick={() => {
                      setAddingToColumn(col.id);
                      setNewTitle("");
                    }}
                  >
                    <Plus className="h-3 w-3" />
                  </Button>
                </div>
              </div>

              {/* Cards */}
              <div className="space-y-2">
                {columnTasks.length === 0 && addingToColumn !== col.id && (
                  <p className="py-4 text-center text-xs text-muted-foreground">—</p>
                )}

                {columnTasks.map((task) => (
                  <div
                    key={task.id}
                    className={cn(
                      "rounded-md border border-border/60 bg-card p-2.5 text-sm text-foreground transition-all group",
                      task.status === "done" && "opacity-70",
                      task.status === "running" && "border-[var(--centurion-gold)]/30",
                      task.status === "blocked" && "border-destructive/30",
                    )}
                  >
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-1.5">
                          {getStatusIcon(task.status)}
                          <span
                            className={cn(
                              "text-xs font-medium",
                              task.status === "done" && "text-muted-foreground line-through",
                            )}
                          >
                            {task.title}
                          </span>
                        </div>
                        {task.body && (
                          <p className="mt-1 text-[10px] text-muted-foreground line-clamp-2">
                            {task.body}
                          </p>
                        )}
                      </div>
                    </div>

                    {/* Actions row */}
                    <div className="mt-2 flex items-center justify-between opacity-0 group-hover:opacity-100 transition-opacity">
                      <div className="flex items-center gap-0.5">
                        {task.status !== "done" && (
                          <button
                            onClick={() => cycleStatus(task)}
                            className="text-[9px] text-muted-foreground hover:text-foreground px-1 py-0.5 rounded"
                            title="Cycle status"
                          >
                            Advance
                          </button>
                        )}
                      </div>
                      <button
                        onClick={() => deleteTask(task.id)}
                        className="text-[9px] text-muted-foreground hover:text-destructive px-1 py-0.5 rounded"
                        title="Delete task"
                      >
                        Delete
                      </button>
                    </div>
                  </div>
                ))}

                {/* Inline add form */}
                {addingToColumn === col.id && (
                  <div className="flex items-center gap-1">
                    <Input
                      autoFocus
                      placeholder="Task title..."
                      value={newTitle}
                      onChange={(e) => setNewTitle(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") handleAddTask(col.id);
                        if (e.key === "Escape") setAddingToColumn(null);
                      }}
                      className="h-7 text-xs flex-1"
                    />
                    <Button
                      ghost
                      size="icon"
                      className="h-7 w-7 shrink-0"
                      onClick={() => setAddingToColumn(null)}
                    >
                      <X className="h-3 w-3" />
                    </Button>
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
