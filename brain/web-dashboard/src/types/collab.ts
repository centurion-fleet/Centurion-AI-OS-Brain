import type { BridgeOk } from "./life";

export type CollabColumn = "ready" | "doing" | "blocked" | "done";

export interface CollabCard {
  id: string;
  title: string;
  assignee: string;
  status: string;
  column: CollabColumn;
  role: string;
  body: string;
}

export interface CollabSwarm {
  id: string;
  display_name: string;
  objective: string;
  pulse: string;
  status: string;
  root_id?: string;
  pending_signal_count?: number;
  workers?: { title: string; assignee: string; status: string; role: string }[];
  blackboard?: Record<string, unknown>;
  cards?: CollabCard[];
  kanban_board_slug?: string;
  mission_id?: string | null;
}

export type CollabSnapshot = BridgeOk & {
  swarms: CollabSwarm[];
  message?: string | null;
  portal?: { ok?: boolean; message?: string; connected?: boolean };
};

export const COLUMNS: { id: CollabColumn; label: string }[] = [
  { id: "ready", label: "Ready" },
  { id: "doing", label: "Doing" },
  { id: "blocked", label: "Blocked" },
  { id: "done", label: "Done" },
];
