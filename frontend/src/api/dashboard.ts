import { api } from "./axios";
import type { JsonApiSingle, DashboardAttributes } from "@/types/api";

export async function getDashboard() {
  const res = await api.get<JsonApiSingle<DashboardAttributes>>("/dashboard");
  return res.data;
}
