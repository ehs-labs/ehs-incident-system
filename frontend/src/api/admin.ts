import { api } from "./axios";
import type {
  JsonApiList,
  JsonApiSingle,
  User,
  Site,
  OrgSettingAttributes,
  Role
} from "@/types/api";

// Users ----------------------------------------------------------------------

export async function listOrgUsers() {
  // Admin endpoint: returns all org users with metadata. Used for assignee pickers too.
  const res = await api.get<JsonApiList<User>>("/admin/users");
  return res.data;
}

export async function inviteUser(payload: {
  email: string;
  name: string;
  role: Role;
}) {
  const res = await api.post<JsonApiSingle<User>>("/admin/users", {
    user: payload
  });
  return res.data;
}

export async function updateUser(
  id: string,
  payload: Partial<{ name: string; role: Role }>
) {
  const res = await api.patch<JsonApiSingle<User>>(`/admin/users/${id}`, {
    user: payload
  });
  return res.data;
}

export async function lockUser(id: string) {
  const res = await api.post<JsonApiSingle<User>>(`/admin/users/${id}/lock`);
  return res.data;
}

export async function unlockUser(id: string) {
  const res = await api.post<JsonApiSingle<User>>(`/admin/users/${id}/unlock`);
  return res.data;
}

export async function deleteUser(id: string) {
  await api.delete(`/admin/users/${id}`);
}

// Sites ----------------------------------------------------------------------

export async function listAdminSites() {
  const res = await api.get<JsonApiList<Site>>("/admin/sites");
  return res.data;
}

export async function createSite(payload: { name: string; timezone: string }) {
  const res = await api.post<JsonApiSingle<Site>>("/admin/sites", {
    site: payload
  });
  return res.data;
}

export async function updateSite(
  id: string,
  payload: Partial<{ name: string; timezone: string }>
) {
  const res = await api.patch<JsonApiSingle<Site>>(`/admin/sites/${id}`, {
    site: payload
  });
  return res.data;
}

export async function deleteSite(id: string) {
  await api.delete(`/admin/sites/${id}`);
}

// Settings -------------------------------------------------------------------

export async function getSettings() {
  const res = await api.get<JsonApiSingle<OrgSettingAttributes>>(
    "/admin/settings"
  );
  return res.data;
}

export async function updateSettings(
  sla_overrides: Record<string, { triage_seconds: number }>
) {
  const res = await api.patch<JsonApiSingle<OrgSettingAttributes>>(
    "/admin/settings",
    { organization_setting: { sla_overrides } }
  );
  return res.data;
}
