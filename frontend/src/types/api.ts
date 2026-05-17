// Hand-defined backend shapes (Phase 3 will replace via openapi-typescript).

export type Role = "worker" | "investigator" | "admin";

export type IncidentState =
  | "draft"
  | "submitted"
  | "investigating"
  | "pending_closure"
  | "closed";

export type ActionState = "open" | "in_progress" | "done" | "verified";

export type IncidentType =
  | "slip"
  | "trip"
  | "fall"
  | "chemical"
  | "near_miss"
  | "equipment"
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

export interface User {
  id: string;
  email: string;
  name: string;
  role: Role;
  org_id?: string;
  organization_id?: number;
  confirmed_at?: string | null;
  locked_at?: string | null;
  locked?: boolean;
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
  telegram_linked: boolean;
}

export interface IncidentAttributes {
  state: IncidentState;
  incident_type: IncidentType;
  severity: Severity;
  occurred_at: string;
  location: string;
  summary: string;
  description: string;
  root_cause: string | null;
  submitted_at: string | null;
  triaged_at: string | null;
  closed_at: string | null;
  sla_breached_at: string | null;
  created_at: string;
  updated_at: string;
  site_id: number;
  reporter_id: number;
  assignee_id: number | null;
  organization_id: number;
  triage_overdue: boolean;
  triage_deadline: string | null;
}

export interface CorrectiveActionAttributes {
  title: string;
  description: string;
  state: ActionState;
  due_date: string;
  completed_at: string | null;
  verified_at: string | null;
  created_at: string;
  updated_at: string;
  incident_id: number;
  assignee_id: number;
  created_by_id: number;
  overdue: boolean;
  evidence_blob_ids: string[];
}

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

export interface ProblemDetails {
  type?: string;
  title?: string;
  status?: number;
  detail?: string;
  instance?: string;
  errors?: Record<string, string[]>;
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
