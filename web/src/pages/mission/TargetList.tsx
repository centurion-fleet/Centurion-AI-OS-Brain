/* ------------------------------------------------------------------ */
/*  Target List — displays project targets with their tasks            */
/*  Ported from Centurion-website-v3/components/swarm/target-list.tsx  */
/*  and target-card.tsx                                                */
/* ------------------------------------------------------------------ */

import { useCallback, useState } from "react";
import {
  CheckCircle2,
  Circle,
  Clock,
  Plus,
  X,
  AlertCircle,
} from "lucide-react";
import { Badge } from "@centurion-fleet/ui/ui/components/badge";
import { Button } from "@centurion-fleet/ui/ui/components/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";
import { useMission } from "./context";
import {
  TARGET_TYPES,
  TARGET_STATUSES,
  type MissionTarget,
  type MissionTask,
} from "./types";

interface TargetListProps {
  projectId: string;
  targets: MissionTarget[];
  tasks: MissionTask[];
}

export function TargetList({ projectId, targets, tasks }: TargetListProps) {
  const { updateTarget, deleteTarget, addTask, updateTask, deleteTask } = useMission();
  const [expandedTarget, setExpandedTarget] = useState<string | null>(null);
  const [newTaskTitle, setNewTaskTitle] = useState("");

  const toggleExpand = useCallback(
    (targetId: string) => {
      setExpandedTarget((prev) => (prev === targetId ? null : targetId));
      setNewTaskTitle("");
    },
    [],
  );

  const handleAddTask = useCallback(
    (targetId: string) => {
      if (!newTaskTitle.trim()) return;
      const targetTasks = tasks.filter((t) => t.targetId === targetId);
      addTask({
        projectId,
        targetId,
        title: newTaskTitle.trim(),
        body: null,
        status: "todo",
        assignee: null,
        sortOrder: targetTasks.length,
        result: null,
      });
      setNewTaskTitle("");
    },
    [newTaskTitle, projectId, tasks, addTask],
  );

  const cycleTaskStatus = useCallback(
    (taskId: string) => {
      const task = tasks.find((t) => t.id === taskId);
      if (!task) return;
      const nextStatus =
        task.status === "todo"
          ? "ready"
          : task.status === "ready"
            ? "running"
            : task.status === "running"
              ? "done"
              : "todo";
      updateTask(taskId, { status: nextStatus });
    },
    [tasks, updateTask],
  );

  if (targets.length === 0) {
    return (
      <Card>
        <CardContent className="py-8 text-center text-sm text-muted-foreground">
          <p>No targets yet. Create your first target to define the mission sequence.</p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <h3 className="text-sm font-medium text-foreground flex items-center gap-2">
        <Circle className="h-3.5 w-3.5 text-muted-foreground" />
        Target Sequence
        <span className="text-xs text-muted-foreground font-normal">
          ({targets.length})
        </span>
      </h3>

      {targets.map((target, index) => {
        const typeMeta = TARGET_TYPES.find((t) => t.key === target.targetType);
        const statusMeta = TARGET_STATUSES.find((s) => s.key === target.status);
        const targetTasks = tasks.filter((t) => t.targetId === target.id);
        const isExpanded = expandedTarget === target.id;

        return (
          <div
            key={target.id}
            className={cn(
              "rounded-lg border border-border transition-all",
              target.status === "complete" && "opacity-80",
              isExpanded && "ring-1 ring-[var(--centurion-gold)]/20",
            )}
          >
            {/* Target card header */}
            <button
              onClick={() => toggleExpand(target.id)}
              className={cn(
                "w-full flex items-start gap-3 p-4 text-left cursor-pointer",
                "hover:bg-muted/30 transition-colors",
                "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--centurion-gold)]",
              )}
            >
              <span className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-muted font-mono text-xs font-medium tabular-nums">
                {target.sequenceNumber}
              </span>

              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <p
                    className={cn(
                      "text-sm font-medium normal-case",
                      target.status === "complete" && "text-muted-foreground line-through",
                    )}
                  >
                    {target.title}
                  </p>
                  {typeMeta && (
                    <span className={cn("rounded px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide", typeMeta.color)}>
                      {typeMeta.label}
                    </span>
                  )}
                  {statusMeta && (
                    <span className={cn("rounded px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide", statusMeta.color)}>
                      {statusMeta.label}
                    </span>
                  )}
                  {targetTasks.length > 0 && (
                    <span className="text-[10px] text-muted-foreground tabular-nums">
                      {targetTasks.filter((t) => t.status === "done").length}/{targetTasks.length} tasks
                    </span>
                  )}
                </div>
                {target.action && (
                  <p className="mt-1 text-xs text-muted-foreground normal-case line-clamp-2">
                    {target.action}
                  </p>
                )}
              </div>

              {/* Quick status toggle */}
              <div className="shrink-0 flex items-center gap-1" onClick={(e) => e.stopPropagation()}>
                {target.status !== "complete" && (
                  <Button
                    ghost
                    size="icon"
                    className="h-7 w-7 text-success"
                    title="Mark complete"
                    onClick={() => updateTarget(target.id, { status: "complete" })}
                  >
                    <CheckCircle2 className="h-3.5 w-3.5" />
                  </Button>
                )}
                {target.status === "complete" && (
                  <Button
                    ghost
                    size="icon"
                    className="h-7 w-7 text-muted-foreground"
                    title="Reopen"
                    onClick={() => updateTarget(target.id, { status: "in_progress" })}
                  >
                    <Clock className="h-3.5 w-3.5" />
                  </Button>
                )}
                <Button
                  ghost
                  size="icon"
                  className="h-7 w-7 text-destructive"
                  title="Delete target"
                  onClick={() => deleteTarget(target.id)}
                >
                  <X className="h-3 w-3" />
                </Button>
              </div>
            </button>

            {/* Expanded: task list */}
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
                      "flex items-start gap-2 rounded-md border border-border/50 bg-muted/20 p-2.5 transition-all",
                      task.status === "done" && "opacity-60",
                      task.status === "running" && "border-[var(--centurion-gold)]/30",
                      task.status === "blocked" && "border-destructive/30",
                    )}
                  >
                    <button
                      onClick={() => cycleTaskStatus(task.id)}
                      className={cn(
                        "mt-0.5 shrink-0 rounded-full transition-colors",
                        task.status === "done"
                          ? "text-success"
                          : task.status === "running"
                            ? "text-[var(--centurion-gold)]"
                            : task.status === "blocked"
                              ? "text-destructive"
                              : "text-muted-foreground hover:text-foreground",
                      )}
                      title={`Status: ${task.status}. Click to cycle.`}
                    >
                      {task.status === "done" ? (
                        <CheckCircle2 className="h-3.5 w-3.5" />
                      ) : task.status === "running" ? (
                        <Clock className="h-3.5 w-3.5" />
                      ) : task.status === "blocked" ? (
                        <AlertCircle className="h-3.5 w-3.5" />
                      ) : (
                        <Circle className="h-3.5 w-3.5" />
                      )}
                    </button>

                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <span
                          className={cn(
                            "text-xs",
                            task.status === "done" && "text-muted-foreground line-through",
                          )}
                        >
                          {task.title}
                        </span>
                        <Badge
                          tone={
                            task.status === "done"
                              ? "success"
                              : task.status === "running"
                                ? "warning"
                                : task.status === "blocked"
                                  ? "destructive"
                                  : "outline"
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

                    <Button
                      ghost
                      size="icon"
                      className="h-6 w-6 text-muted-foreground hover:text-destructive shrink-0"
                      title="Delete task"
                      onClick={() => deleteTask(task.id)}
                    >
                      <X className="h-3 w-3" />
                    </Button>
                  </div>
                ))}

                {/* Add task inline */}
                <div className="flex items-center gap-2 pt-1">
                  <Input
                    placeholder="Add a task..."
                    value={newTaskTitle}
                    onChange={(e) => setNewTaskTitle(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") handleAddTask(target.id);
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
        );
      })}
    </div>
  );
}
