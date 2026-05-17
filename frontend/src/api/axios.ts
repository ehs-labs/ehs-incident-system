import axios, { AxiosError, type AxiosRequestConfig } from "axios";
import { useAuthStore } from "@/stores/auth";
import { ApiError, type ProblemDetails } from "@/types/api";

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

// ---- Response: 401 → kick to /login; parse RFC 7807 into ApiError ----------
let refreshing: Promise<string | null> | null = null;

api.interceptors.response.use(
  (r) => r,
  async (error: AxiosError) => {
    const original = error.config as
      | (AxiosRequestConfig & { _retried?: boolean })
      | undefined;
    const status = error.response?.status ?? 0;

    if (status === 401 && original && !original._retried) {
      const auth = useAuthStore();
      refreshing ??= auth.tryRefresh();
      const newToken = await refreshing.finally(() => {
        refreshing = null;
      });

      if (newToken) {
        original._retried = true;
        original.headers ??= {};
        (original.headers as Record<string, string>)["Authorization"] =
          `Bearer ${newToken}`;
        return api(original);
      }

      auth.clear();
      if (typeof window !== "undefined" && window.location.pathname !== "/login") {
        const next = encodeURIComponent(
          window.location.pathname + window.location.search
        );
        window.location.assign(`/login?next=${next}`);
      }
    }

    const body = (error.response?.data ?? {}) as ProblemDetails;
    throw new ApiError(status, {
      ...body,
      status,
      title: body.title ?? error.message,
      detail: body.detail ?? body.title ?? error.message
    });
  }
);

// ---- Link header pagination ------------------------------------------------

export interface LinkRels {
  next?: string;
  prev?: string;
  first?: string;
  last?: string;
}

export function parseLinkHeader(header: string | null | undefined): LinkRels {
  if (!header) return {};
  const out: LinkRels = {};
  for (const part of header.split(",")) {
    const match = part.trim().match(/<([^>]+)>;\s*rel="([^"]+)"/);
    if (!match) continue;
    out[match[2] as keyof LinkRels] = match[1];
  }
  return out;
}

export function pageNumberFromUrl(url: string | undefined): number | null {
  if (!url) return null;
  try {
    const p = new URL(url, window.location.origin).searchParams.get("page");
    return p ? Number(p) : null;
  } catch {
    return null;
  }
}
