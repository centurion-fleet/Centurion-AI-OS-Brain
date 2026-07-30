import type { MissionPhase } from "../types/life";

export const PHASE_ORDER: MissionPhase[] = [
  "briefing",
  "discovery",
  "planning",
  "executing",
  "verifying",
  "done",
];

export type PhaseCopy = {
  label: string;
  help: string;
};

/** Title Case labels + one-line help for each mission lifecycle phase. */
export const PHASE_COPY: Record<MissionPhase, PhaseCopy> = {
  briefing: {
    label: "Briefing",
    help: "Shape the mission: title, statement, and why it matters.",
  },
  discovery: {
    label: "Discovery",
    help: "Explore the situation and options before locking a plan.",
  },
  planning: {
    label: "Planning",
    help: "Lock the approach and target sequence.",
  },
  executing: {
    label: "Executing",
    help: "Do the work against your targets.",
  },
  verifying: {
    label: "Verifying",
    help: "Check outcomes against targets and purpose before calling it done.",
  },
  done: {
    label: "Done",
    help: "This mission is finished.",
  },
};

export function nextPhase(current: MissionPhase): MissionPhase | null {
  const i = PHASE_ORDER.indexOf(current);
  if (i < 0 || i >= PHASE_ORDER.length - 1) return null;
  return PHASE_ORDER[i + 1];
}

export function phaseLabel(phase: MissionPhase): string {
  return PHASE_COPY[phase]?.label ?? phase;
}

export function phaseHelp(phase: MissionPhase): string {
  return PHASE_COPY[phase]?.help ?? "";
}

export function missionTypeLabel(missionType: string): string {
  if (!missionType) return "Mission";
  return missionType.charAt(0).toUpperCase() + missionType.slice(1);
}
