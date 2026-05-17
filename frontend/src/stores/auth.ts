import { defineStore } from "pinia";
import axios from "axios";

interface User {
  id: string;
  email: string;
  name: string;
  role: "worker" | "investigator" | "admin";
  org_id: string;
}

interface AuthState {
  accessToken: string | null;
  user: User | null;
}

export const useAuthStore = defineStore("auth", {
  state: (): AuthState => ({
    accessToken: null,
    user: null
  }),
  getters: {
    isAuthenticated: (s) => !!s.accessToken && !!s.user
  },
  actions: {
    async login(email: string, password: string) {
      const { data, headers } = await axios.post(
        `${import.meta.env.VITE_API_BASE_URL ?? "/api/v1"}/auth/login`,
        { user: { email, password } },
        { withCredentials: true }
      );
      this.setSession(headers.authorization?.replace(/^Bearer /, "") ?? data.access_token, data.user);
    },

    async tryRefresh(): Promise<string | null> {
      try {
        const { data, headers } = await axios.post(
          `${import.meta.env.VITE_API_BASE_URL ?? "/api/v1"}/auth/refresh`,
          {},
          { withCredentials: true }
        );
        const newToken = headers.authorization?.replace(/^Bearer /, "") ?? data.access_token;
        this.setSession(newToken, data.user);
        return newToken;
      } catch {
        this.clear();
        return null;
      }
    },

    async logout() {
      try {
        await axios.delete(
          `${import.meta.env.VITE_API_BASE_URL ?? "/api/v1"}/auth/logout`,
          { headers: { Authorization: `Bearer ${this.accessToken}` }, withCredentials: true }
        );
      } finally {
        this.clear();
      }
    },

    setSession(token: string, user: User) {
      this.accessToken = token;
      this.user = user;
    },

    clear() {
      this.accessToken = null;
      this.user = null;
    }
  }
});
