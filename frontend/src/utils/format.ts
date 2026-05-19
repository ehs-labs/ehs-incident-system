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

// Returns the API origin (scheme + host + port) derived from VITE_API_BASE_URL,
// e.g. "http://localhost:3000". Used to turn a relative Rails URL into an
// absolute one the browser at localhost:5173 can fetch (the API itself lives
// on a different port in dev).
export function apiOrigin(): string {
  const base = import.meta.env.VITE_API_BASE_URL ?? "/api/v1";
  try {
    return new URL(base, window.location.origin).origin;
  } catch {
    return "";
  }
}

// Prepends `apiOrigin()` to a relative URL. Pass-through for absolute URLs.
export function absoluteApiUrl(url: string | null | undefined): string {
  if (!url) return "";
  if (/^https?:\/\//i.test(url)) return url;
  return `${apiOrigin()}${url.startsWith("/") ? "" : "/"}${url}`;
}

export function humanizeSeconds(secs: number | null | undefined): string {
  if (secs == null) return "—";
  if (secs < 60) return `${Math.round(secs)}s`;
  if (secs < 3600) return `${Math.round(secs / 60)}m`;
  if (secs < 86400) return `${(secs / 3600).toFixed(1)}h`;
  return `${(secs / 86400).toFixed(1)}d`;
}

// Severity scale follows the architecture brief: S1 is the most critical,
// S5 is the least. Triage SLA windows in core-api/app/models/incident.rb
// (S1/S2 -> 4h, S3 -> 24h, S4/S5 -> 72h) and design/state-machines.md
// ("1 catastrophic ... 5") are the source of truth.
export function severityColor(sev: Severity | number): string {
  return (
    {
      1: "#c62828",
      2: "#e85d2f",
      3: "#f2a93b",
      4: "#7cb342",
      5: "#1f8a44"
    } as Record<number, string>
  )[sev] ?? "#888";
}

export function severityLabel(sev: Severity | number): string {
  return ["?", "Critical", "Major", "Moderate", "Low", "Minor"][sev] ?? `S${sev}`;
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
