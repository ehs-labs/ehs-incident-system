import { describe, it, expect, beforeEach } from "vitest";
import { setActivePinia, createPinia } from "pinia";
import { useAuthStore } from "@/stores/auth";

describe("auth store", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it("starts unauthenticated", () => {
    const auth = useAuthStore();
    expect(auth.isAuthenticated).toBe(false);
  });

  it("stores token + user after setSession", () => {
    const auth = useAuthStore();
    auth.setSession("jwt-here", {
      id: "u-1",
      email: "a@b.com",
      name: "Alice",
      role: "worker",
      org_id: "org-1"
    });
    expect(auth.isAuthenticated).toBe(true);
    expect(auth.user?.email).toBe("a@b.com");
  });

  it("clear() wipes the session", () => {
    const auth = useAuthStore();
    auth.setSession("t", { id: "x", email: "x@y.com", name: "X", role: "admin", org_id: "o" });
    auth.clear();
    expect(auth.isAuthenticated).toBe(false);
    expect(auth.accessToken).toBeNull();
  });
});
