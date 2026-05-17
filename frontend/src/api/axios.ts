import axios, { AxiosError } from "axios";
import { useAuthStore } from "@/stores/auth";

export const api = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL ?? "/api/v1",
  withCredentials: true,
  timeout: 30_000
});

// ---- Request: attach JWT ----------------------------------------------------
api.interceptors.request.use((config) => {
  const token = useAuthStore().accessToken;
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// ---- Response: 401 → try refresh once, then retry ---------------------------
let refreshing: Promise<string | null> | null = null;

api.interceptors.response.use(
  (r) => r,
  async (error: AxiosError) => {
    const original = error.config as (typeof error.config & { _retried?: boolean });
    if (error.response?.status !== 401 || !original || original._retried) {
      return Promise.reject(error);
    }

    refreshing ??= useAuthStore().tryRefresh();
    const newToken = await refreshing.finally(() => {
      refreshing = null;
    });

    if (!newToken) return Promise.reject(error);

    original._retried = true;
    original.headers!.Authorization = `Bearer ${newToken}`;
    return api(original);
  }
);
