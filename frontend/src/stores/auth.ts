import { defineStore } from "pinia";
import axios from "axios";
import type { Role, Site, Organization } from "@/types/api";

interface User {
  id: string;
  email: string;
  name: string;
  role: Role;
  org_id: string;
}

interface AuthState {
  accessToken: string | null;
  user: User | null;
  sites: Site[];
  organization: Organization | null;
}

const TOKEN_KEY = "ehs.jwt";
const USER_KEY = "ehs.user";
const ORG_KEY = "ehs.org";
const SITES_KEY = "ehs.sites";

const apiBase = (): string =>
  import.meta.env.VITE_API_BASE_URL ?? "/api/v1";

// Backend returns the user inside a jsonapi envelope: { data: { id, attributes: {...} } }
function normalizeUser(payload: unknown): User {
  // Two shapes seen: `{ data: { id, attributes: {...} } }` (login) and a flat user dict.
  const root = payload as Record<string, unknown>;
  const inner = (root.data ?? root) as Record<string, unknown>;
  const attrs = (inner.attributes ?? inner) as Record<string, unknown>;
  return {
    id: String(inner.id ?? attrs.id ?? ""),
    email: String(attrs.email ?? ""),
    name: String(attrs.name ?? ""),
    role: (attrs.role as Role) ?? "worker",
    org_id: String(attrs.organization_id ?? attrs.org_id ?? "")
  };
}

export const useAuthStore = defineStore("auth", {
  state: (): AuthState => ({
    accessToken: localStorage.getItem(TOKEN_KEY),
    user: JSON.parse(localStorage.getItem(USER_KEY) ?? "null"),
    sites: JSON.parse(localStorage.getItem(SITES_KEY) ?? "[]"),
    organization: JSON.parse(localStorage.getItem(ORG_KEY) ?? "null")
  }),
  getters: {
    isAuthenticated: (s) => !!s.accessToken && !!s.user,
    isAdmin: (s) => s.user?.role === "admin",
    isInvestigator: (s) => s.user?.role === "investigator" || s.user?.role === "admin"
  },
  actions: {
    async login(email: string, password: string) {
      const { data, headers } = await axios.post(
        `${apiBase()}/auth/login`,
        { user: { email, password } },
        { withCredentials: true }
      );
      const headerToken = (headers.authorization as string | undefined)?.replace(/^Bearer /, "");
      const token = headerToken ?? data.access_token;
      const user = normalizeUser(data.user);
      this.setSession(token, user);
      await this.fetchMe();
    },

    async signup(name: string, email: string, password: string, password_confirmation: string) {
      const { data, headers } = await axios.post(
        `${apiBase()}/auth/signup`,
        { user: { name, email, password, password_confirmation } },
        { withCredentials: true }
      );
      const headerToken = (headers.authorization as string | undefined)?.replace(/^Bearer /, "");
      const token = headerToken ?? data.access_token;
      const user = normalizeUser(data.user);
      this.setSession(token, user);
      await this.fetchMe();
    },

    async fetchMe() {
      if (!this.accessToken) return;
      try {
        const { data } = await axios.get(`${apiBase()}/me`, {
          headers: { Authorization: `Bearer ${this.accessToken}` }
        });
        const attrs = data.data?.attributes ?? {};
        this.sites = (attrs.sites ?? []) as Site[];
        this.organization = (attrs.organization ?? null) as Organization | null;
        // Patch in any missing user fields
        if (this.user) {
          this.user = {
            ...this.user,
            email: attrs.email ?? this.user.email,
            name: attrs.name ?? this.user.name,
            role: attrs.role ?? this.user.role
          };
        }
        this.persist();
      } catch {
        /* fetchMe is best-effort; do not blow up the session */
      }
    },

    async tryRefresh(): Promise<string | null> {
      try {
        const { data, headers } = await axios.post(
          `${apiBase()}/auth/refresh`,
          {},
          { withCredentials: true }
        );
        const headerToken = (headers.authorization as string | undefined)?.replace(/^Bearer /, "");
        const newToken = headerToken ?? data.access_token;
        if (!newToken) {
          this.clear();
          return null;
        }
        const user = normalizeUser(data.user ?? data);
        this.setSession(newToken, user);
        await this.fetchMe();
        return newToken;
      } catch {
        this.clear();
        return null;
      }
    },

    async logout() {
      try {
        if (this.accessToken) {
          await axios.delete(`${apiBase()}/auth/logout`, {
            headers: { Authorization: `Bearer ${this.accessToken}` },
            withCredentials: true
          });
        }
      } finally {
        this.clear();
      }
    },

    setSession(token: string, user: User) {
      this.accessToken = token;
      this.user = user;
      this.persist();
    },

    persist() {
      if (this.accessToken) localStorage.setItem(TOKEN_KEY, this.accessToken);
      if (this.user) localStorage.setItem(USER_KEY, JSON.stringify(this.user));
      if (this.organization) localStorage.setItem(ORG_KEY, JSON.stringify(this.organization));
      localStorage.setItem(SITES_KEY, JSON.stringify(this.sites));
    },

    clear() {
      this.accessToken = null;
      this.user = null;
      this.sites = [];
      this.organization = null;
      localStorage.removeItem(TOKEN_KEY);
      localStorage.removeItem(USER_KEY);
      localStorage.removeItem(ORG_KEY);
      localStorage.removeItem(SITES_KEY);
    }
  }
});
