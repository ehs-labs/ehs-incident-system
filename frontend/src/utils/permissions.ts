import type { IncidentState, Role, ActionState } from "@/types/api";
import type { IncidentTransition } from "@/api/incidents";

export type IncidentTransitionEvent = IncidentTransition;

/**
 * Client-side gating mirrors the backend's Pundit policy roughly so the user
 * doesn't see useless buttons. The server is still the source of truth — a 403
 * surface as a toast. Conservative when unsure.
 */
export function allowedIncidentTransitions(
  state: IncidentState,
  role: Role,
  isReporter: boolean,
  isAssignee: boolean
): IncidentTransitionEvent[] {
  const result: IncidentTransitionEvent[] = [];
  switch (state) {
    case "draft":
      if (isReporter || role === "admin") result.push("submit");
      if (isReporter || role === "admin") result.push("edit");
      break;
    case "submitted":
      if (role === "investigator" || role === "admin") {
        result.push("triage");
      }
      break;
    case "investigating":
      if (isAssignee || role === "admin") {
        result.push("actions_assigned");
      }
      if (role === "investigator" || role === "admin") {
        result.push("reject");
      }
      break;
    case "pending_closure":
      if (isAssignee || role === "investigator" || role === "admin") {
        result.push("verify");
      }
      break;
    case "closed":
      if (role === "admin" || role === "investigator") result.push("reopen");
      break;
  }
  return result;
}

export function allowedActionTransitions(
  state: ActionState,
  role: Role,
  isAssignee: boolean
): ("start" | "complete" | "verify")[] {
  switch (state) {
    case "open":
      return isAssignee ? ["start"] : [];
    case "in_progress":
      return isAssignee ? ["complete"] : [];
    case "done":
      return role === "investigator" || role === "admin" ? ["verify"] : [];
    case "verified":
      return [];
  }
}

export function canEditIncident(state: IncidentState, role: Role): boolean {
  if (role === "admin") return true;
  if (state === "draft") return true;
  if (role === "investigator" && state !== "closed") return true;
  return false;
}
