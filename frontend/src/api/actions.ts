import { api } from "./axios";
import type {
  JsonApiList,
  JsonApiSingle,
  CorrectiveActionAttributes,
  CorrectiveActionEventAttributes,
  ActionState
} from "@/types/api";

export interface ActionListParams {
  state?: ActionState[];
  assignee_id?: number | string;
  overdue?: boolean;
}

export async function listActions(params: ActionListParams = {}) {
  const search = new URLSearchParams();
  params.state?.forEach((s) => search.append("state[]", s));
  if (params.assignee_id) search.set("assignee_id", String(params.assignee_id));
  if (params.overdue) search.set("overdue", "true");
  const qs = search.toString();
  const res = await api.get<JsonApiList<CorrectiveActionAttributes>>(
    `/corrective_actions${qs ? `?${qs}` : ""}`
  );
  return res.data;
}

export type ActionTransition = "start" | "complete" | "verify" | "cancel";

export async function transitionAction(
  id: string | number,
  event: ActionTransition,
  note?: string
) {
  const res = await api.post<JsonApiSingle<CorrectiveActionAttributes>>(
    `/corrective_actions/${id}/transitions`,
    { event, note }
  );
  return res.data;
}

export async function listActionEvents(id: string | number) {
  const res = await api.get<JsonApiList<CorrectiveActionEventAttributes>>(
    `/corrective_actions/${id}/events`
  );
  return res.data;
}

export async function updateAction(
  id: string | number,
  payload: Partial<{ title: string; description: string; due_date: string; assignee_id: number }>
) {
  const res = await api.patch<JsonApiSingle<CorrectiveActionAttributes>>(
    `/corrective_actions/${id}`,
    { corrective_action: payload }
  );
  return res.data;
}
