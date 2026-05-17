import { formatDistanceToNow, format, parseISO } from "date-fns";
import type { IncidentState, Severity, ActionState } from "@/types/api";

export function fmtDate(iso: string | null | undefined): string {
  if (!iso) return "—";
  try {
    return format(parseISO(iso), "yyyy-MM-dd HH:mm");
  } catch {
    return iso;
  }
}

export function fmtRelative(iso: string | null | undefined): string {
  if (!iso) return "—";
  try {
    return formatDistanceToNow(parseISO(iso), { addSuffix: true });
  } catch {
    return iso;
  }
}

export function humanizeSeconds(secs: number | null | undefined): string {
  if (secs == null) return "—";
  if (secs < 60) return `${Math.round(secs)}s`;
  if (secs < 3600) return `${Math.round(secs / 60)}m`;
  if (secs < 86400) return `${(secs / 3600).toFixed(1)}h`;
  return `${(secs / 86400).toFixed(1)}d`;
}

export function severityColor(sev: Severity | number): string {
  return (
    {
      1: "#1f8a44",
      2: "#7cb342",
      3: "#f2a93b",
      4: "#e85d2f",
      5: "#c62828"
    } as Record<number, string>
  )[sev] ?? "#888";
}

export function severityLabel(sev: Severity | number): string {
  return ["?", "Minor", "Low", "Moderate", "Major", "Critical"][sev] ?? `S${sev}`;
}

export function stateTagType(
  s: IncidentState
): "default" | "info" | "success" | "warning" | "error" {
  switch (s) {
    case "draft":
      return "default";
    case "submitted":
      return "info";
    case "investigating":
      return "warning";
    case "pending_closure":
      return "info";
    case "closed":
      return "success";
    default:
      return "default";
  }
}

export function actionStateTagType(
  s: ActionState
): "default" | "info" | "success" | "warning" {
  switch (s) {
    case "open":
      return "default";
    case "in_progress":
      return "info";
    case "done":
      return "warning";
    case "verified":
      return "success";
  }
}
