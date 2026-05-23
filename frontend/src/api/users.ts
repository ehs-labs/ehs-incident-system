import { api } from "./axios";
import type { JsonApiList, User } from "@/types/api";

export async function listAssignableUsers(params?: { q?: string }) {
  const res = await api.get<JsonApiList<User>>("/assignable_users", { params });
  return res.data;
}
