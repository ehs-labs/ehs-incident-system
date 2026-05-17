import { test, expect } from "@playwright/test";

// Smoke test — proves the SPA boots and the login page renders.
// More substantive flows live in incident.spec.ts (TBD).
test("login page renders", async ({ page }) => {
  await page.goto("/login");
  await expect(page.locator("h1")).toContainText(/login/i);
});
