import { api, parseLinkHeader, pageNumberFromUrl } from "./axios";
import type {
  JsonApiList,
  JsonApiSingle,
  IncidentAttributes,
  CorrectiveActionAttributes,
  CommentAttributes,
  WitnessAttributes,
  VersionAttributes,
  AttachmentAttributes,
  IncidentState,
  Severity,
  IncidentType
} from "@/types/api";

export interface IncidentListParams {
  state?: IncidentState[];
  severity?: Severity[];
  site_id?: number | string;
  q?: string;
  page?: number;
  per_page?: number;
}

export interface IncidentListResult {
  data: JsonApiList<IncidentAttributes>;
  total: number;
  nextPage: number | null;
  prevPage: number | null;
  lastPage: number | null;
}

export async function listIncidents(
  params: IncidentListParams = {}
): Promise<IncidentListResult> {
  const search = new URLSearchParams();
  params.state?.forEach((s) => search.append("state[]", s));
  params.severity?.forEach((s) => search.append("severity[]", String(s)));
  if (params.site_id) search.set("site_id", String(params.site_id));
  if (params.q) search.set("q", params.q);
  if (params.page) search.set("page", String(params.page));
  if (params.per_page) search.set("per_page", String(params.per_page));

  const res = await api.get<JsonApiList<IncidentAttributes>>(
    `/incidents?${search.toString()}`
  );
  const link = parseLinkHeader(res.headers["link"] as string | undefined);
  return {
    data: res.data,
    total: Number(res.headers["x-total-count"] ?? res.data.data.length),
    nextPage: pageNumberFromUrl(link.next),
    prevPage: pageNumberFromUrl(link.prev),
    lastPage: pageNumberFromUrl(link.last)
  };
}

export async function getIncident(id: string | number) {
  const res = await api.get<JsonApiSingle<IncidentAttributes>>(
    `/incidents/${id}`
  );
  return res.data;
}

export interface IncidentCreatePayload {
  site_id: number | string;
  incident_type: IncidentType;
  severity: Severity;
  occurred_at: string;
  location: string;
  summary: string;
  description: string;
}

export async function createIncident(payload: IncidentCreatePayload) {
  const res = await api.post<JsonApiSingle<IncidentAttributes>>("/incidents", {
    incident: payload
  });
  return res.data;
}

export async function updateIncident(
  id: string | number,
  payload: Partial<IncidentCreatePayload & { assignee_id: number | null }>
) {
  const res = await api.patch<JsonApiSingle<IncidentAttributes>>(
    `/incidents/${id}`,
    { incident: payload }
  );
  return res.data;
}

export type IncidentTransition =
  | "submit"
  | "triage"
  | "reject"
  | "actions_assigned"
  | "verify"
  | "reopen"
  | "edit";

export async function transitionIncident(
  id: string | number,
  event: IncidentTransition
) {
  const res = await api.post<JsonApiSingle<IncidentAttributes>>(
    `/incidents/${id}/transitions`,
    { event }
  );
  return res.data;
}

// Witnesses, comments, versions, attachments --------------------------------

export async function listWitnesses(incidentId: string | number) {
  const res = await api.get<JsonApiList<WitnessAttributes>>(
    `/incidents/${incidentId}/witnesses`
  );
  return res.data;
}

export async function addWitness(
  incidentId: string | number,
  payload: { name: string; email?: string; phone?: string; statement?: string }
) {
  const res = await api.post<JsonApiSingle<WitnessAttributes>>(
    `/incidents/${incidentId}/witnesses`,
    { witness: payload }
  );
  return res.data;
}

export async function listComments(incidentId: string | number) {
  const res = await api.get<JsonApiList<CommentAttributes>>(
    `/incidents/${incidentId}/comments`
  );
  return res.data;
}

export async function addComment(
  incidentId: string | number,
  body: string
) {
  const res = await api.post<JsonApiSingle<CommentAttributes>>(
    `/incidents/${incidentId}/comments`,
    { comment: { body } }
  );
  return res.data;
}

export async function listVersions(incidentId: string | number) {
  const res = await api.get<JsonApiList<VersionAttributes>>(
    `/incidents/${incidentId}/versions`
  );
  return res.data;
}

export async function listAttachments(incidentId: string | number) {
  const res = await api.get<JsonApiList<AttachmentAttributes>>(
    `/incidents/${incidentId}/attachments`
  );
  return res.data;
}

export async function uploadAttachment(
  incidentId: string | number,
  file: File
) {
  const form = new FormData();
  form.append("attachment[file]", file);
  const res = await api.post<JsonApiSingle<AttachmentAttributes>>(
    `/incidents/${incidentId}/attachments`,
    form,
    { headers: { "Content-Type": "multipart/form-data" } }
  );
  return res.data;
}

// Corrective actions (nested + flat) ----------------------------------------

export async function listIncidentActions(incidentId: string | number) {
  const res = await api.get<JsonApiList<CorrectiveActionAttributes>>(
    `/incidents/${incidentId}/corrective_actions`
  );
  return res.data;
}

export async function createIncidentAction(
  incidentId: string | number,
  payload: {
    title: string;
    description?: string;
    due_date: string;
    assignee_id: number;
    note?: string;
  }
) {
  const res = await api.post<JsonApiSingle<CorrectiveActionAttributes>>(
    `/incidents/${incidentId}/corrective_actions`,
    { corrective_action: payload }
  );
  return res.data;
}
