// Hand-defined backend shapes (Phase 3 will replace via openapi-typescript).

import type { components } from "@/api/schema";

export type Role = "worker" | "investigator" | "admin";

export type IncidentState =
  | "draft"
  | "submitted"
  | "investigating"
  | "pending_closure"
  | "closed";

// Generated schema includes "cancelled"; hand-rolled did not. Keep in sync.
export type ActionState = "open" | "in_progress" | "done" | "verified";

// Must stay in sync with Incident::VALID_TYPES in core-api/app/models/incident.rb.
// (Phase-3 follow-up: surface this list from the backend or share via a generated
// type, so the two can't drift again.)
export type IncidentType =
  | "collision"
  | "slip"
  | "fall"
  | "near_miss"
  | "exposure"
  | "mechanical"
  | "electrical"
  | "fire"
  | "other";

export type Severity = 1 | 2 | 3 | 4 | 5;

// JSON:API envelopes ---------------------------------------------------------

export interface JsonApiResource<T> {
  id: string;
  type: string;
  attributes: T;
  relationships?: Record<string, { data: { id: string; type: string } | null }>;
}

export interface JsonApiSingle<T> {
  data: JsonApiResource<T>;
  included?: JsonApiResource<unknown>[];
  meta?: Record<string, unknown>;
}

export interface JsonApiList<T> {
  data: JsonApiResource<T>[];
  included?: JsonApiResource<unknown>[];
  meta?: Record<string, unknown>;
}

// Domain shapes --------------------------------------------------------------

// Re-exported from generated schema so callers get the server-side attribute
// shape without duplication.
export type UserAttributes = components["schemas"]["UserAttributes"];

// SPA composite: bundles JSON:API `id` (resource-level, not in attributes)
// with the server attributes. Extra SPA-only fields are documented below.
export interface User extends UserAttributes {
  // JSON:API resource id; lives outside the attributes object on the wire.
  id: string;
  // Flattened from organization_id for legacy session storage — equals
  // String(organization_id). Kept until auth store is refactored.
  org_id?: string;
  // Derived by the SPA from locked_at != null; the server exposes locked_at.
  locked?: boolean;
  // The generated schema exposes deleted_at (timestamp); this boolean alias
  // was used in older list views. Prefer checking deleted_at directly.
  deleted?: boolean;
}

export interface Site {
  id: number | string;
  name: string;
  timezone: string;
  organization_id?: number;
}

export interface Organization {
  id: number | string;
  slug: string;
  name: string;
}

export interface MeAttributes {
  email: string;
  name: string;
  role: Role;
  organization: Organization;
  sites: Site[];
}

// Generated schema is the base; intersection adds:
//   - fields the OpenAPI spec omits (served by the backend but not yet in the
//     rswag DSL): organization_id, sla_breached_at, created_at, updated_at,
//     triage_overdue, triage_deadline.
//   - narrowed literal types for state/severity/incident_type that the rswag
//     DSL emits as plain string/number.
export type IncidentAttributes = components["schemas"]["IncidentAttributes"] & {
  // Narrowed types — the generated schema uses string/number for these.
  state: IncidentState;
  incident_type: IncidentType;
  severity: Severity;
  // Fields served by the backend but absent from the rswag spec; add to the
  // spec in a follow-up to make them officially generated.
  organization_id: number;
  sla_breached_at: string | null;
  created_at: string;
  updated_at: string;
  triage_overdue: boolean;
  triage_deadline: string | null;
};

// Generated schema is the base; intersection adds:
//   - state narrowed to the SPA's ActionState (schema also allows "cancelled"
//     which the SPA doesn't surface yet).
//   - Fields served by the backend but absent from the rswag spec: created_at,
//     updated_at, created_by_id, evidence_blob_ids.
export type CorrectiveActionAttributes = components["schemas"]["CorrectiveActionAttributes"] & {
  // Narrowed to the SPA-visible subset; "cancelled" is a valid server state
  // but not yet handled by the SPA's transition UI.
  state: ActionState;
  // Fields absent from the rswag spec; add in a follow-up.
  created_at: string;
  updated_at: string;
  created_by_id: number;
  evidence_blob_ids: string[];
};

export interface WitnessAttributes {
  name: string;
  email: string | null;
  phone: string | null;
  statement: string | null;
  incident_id: number;
  created_at: string;
}

export interface CommentAttributes {
  body: string;
  created_at: string;
  updated_at: string;
  incident_id: number;
  author_id: number;
}

export interface VersionAttributes {
  event: string;
  created_at: string;
  whodunnit_user: { id: number; email: string; name: string } | null;
  changes: Record<string, [unknown, unknown]>;
}

export interface AttachmentAttributes {
  filename: string;
  content_type: string;
  byte_size: number;
  url: string;
  incident_id: number;
  created_at: string;
}

export interface DashboardAttributes {
  open_incidents_by_severity: Record<string, number>;
  incidents_by_state: Record<string, number>;
  overdue_corrective_actions_count: number;
  last_30_day_incidents_trend: { date: string; count: number }[];
  avg_time_to_close_seconds: number | null;
  sla_compliance: {
    on_time?: number;
    breached?: number;
    pending?: number;
    [k: string]: number | undefined;
  };
}

export interface OrgSettingAttributes {
  sla_overrides: Record<string, { triage_seconds: number }>;
  organization_id: number;
  created_at: string;
  updated_at: string;
}

// RFC 7807 problem+json -------------------------------------------------------

// One row in the `errors` array of an RFC 7807 problem+json response. The
// backend sets pointer to "/data/attributes/<field>" or "/data/<relationship>".
export interface ProblemError {
  pointer?: string;
  parameter?: string;
  detail: string;
}

export interface ProblemDetails {
  type?: string;
  title?: string;
  status?: number;
  detail?: string;
  instance?: string;
  errors?: ProblemError[];
}

// Pull "incident_type" out of "/data/attributes/incident_type". Falls back to
// the pointer string itself if it isn't a /data/attributes path.
export function fieldFromPointer(pointer?: string): string | null {
  if (!pointer) return null;
  const m = pointer.match(/\/data\/attributes\/(.+)$/);
  return m ? m[1] : pointer.replace(/^\/data\//, "");
}

export class ApiError extends Error {
  public readonly status: number;
  public readonly problem: ProblemDetails;
  constructor(status: number, problem: ProblemDetails) {
    super(problem.detail || problem.title || `HTTP ${status}`);
    this.status = status;
    this.problem = problem;
  }
}
