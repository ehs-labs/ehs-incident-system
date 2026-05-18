import { type Page } from "@playwright/test";

/**
 * Login via the UI login form and wait for the dashboard to be reachable.
 * Returns after the redirect to /dashboard completes.
 */
export async function loginAs(page: Page, email: string, password: string) {
  await page.goto("/login");
  // The card title rendered by Naive UI wraps in an element that contains
  // "Sign in" — use a broader text query.
  // Naive UI NCard renders two heading elements for the card title; pick the
  // first to avoid strict-mode violations.
  await page.getByRole("heading", { name: /sign in/i }).first().waitFor({ state: "visible" });

  // Naive UI strips autocomplete attributes from inputs; use placeholder text.
  // TODO: add data-testid="email-input" and data-testid="password-input" to Login.vue.
  await page.locator('input[placeholder="you@example.com"]').fill(email);
  await page.locator('input[type="password"]').fill(password);
  await page.getByRole("button", { name: /sign in/i }).click();

  // Wait for the URL to leave /login — dashboard redirect may take a moment.
  await page.waitForURL((url) => !url.pathname.startsWith("/login"), {
    timeout: 15_000
  });
}

/**
 * Navigate to a URL as a given user in a fresh browser context that has
 * already been logged in. Useful for parallel context tests.
 *
 * NOTE: call loginAs(page, ...) before using the page's browser context in
 * another tab. This helper is intentionally thin — context isolation is the
 * caller's responsibility.
 */
export async function ensureOnDashboard(page: Page) {
  await page.waitForURL(/\/dashboard/, { timeout: 10_000 });
}
