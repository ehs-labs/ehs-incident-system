import { test, expect } from "@playwright/test";

// Smoke test — proves the SPA boots and the login page renders.
// Login.vue uses Naive UI NCard with a title attribute, which is rendered as
// a div[role="heading"] rather than an <h1> tag.
test("login page renders", async ({ page }) => {
  await page.goto("/login");
  // Naive UI NCard produces two heading elements for the card title; take the first.
  await expect(page.getByRole("heading", { name: /sign in/i }).first()).toBeVisible();
});
