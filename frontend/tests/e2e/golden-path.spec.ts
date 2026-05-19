/**
 * Golden-path end-to-end scenarios.
 *
 * Scenario ordering matters — each test in the serial suite builds on state
 * created by the previous one. The incident ID created by Scenario 1 is stored
 * in a module-scoped variable and reused in Scenarios 2–5.
 *
 * Selector strategy:
 *  - data-testid attributes are preferred. Where they do not yet exist in the
 *    components, ARIA role / label / text selectors are used and flagged with
 *    a TODO comment so components can be updated to add testids later.
 *
 * Bell-badge / WebSocket scenario (Scenario 3):
 *  Live cross-process WS push is wired via Postgres LISTEN/NOTIFY: the Karafka
 *  consumer publishes on the `delivery_log_appended` channel after writing a
 *  delivery_log row, and the Falcon web process re-pushes the payload to live
 *  sessions. Scenario 3 therefore asserts the investigator's bell badge
 *  increments WITHOUT a page reload, polling for the badge update within a few
 *  seconds of the worker submitting the incident.
 */

import path from "path";
import { fileURLToPath } from "url";
import { test, expect, type Page, type BrowserContext } from "@playwright/test";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
import { loginAs } from "./helpers/auth";

// ---------------------------------------------------------------------------
// Shared state across the serial suite
// ---------------------------------------------------------------------------
let incidentId: string;

// Demo accounts — must match the seed in core-api/db/seeds.rb.
const WORKER_EMAIL = "worker@acme.demo";
const INVESTIGATOR_EMAIL = "investigator@acme.demo";
const PASSWORD = "password";

// Fixture image used for photo upload in Scenario 1.
const PHOTO_PATH = path.join(__dirname, "fixtures", "sample-photo.jpg");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Click a Naive UI NButton that contains the given text. */
async function clickButton(page: Page, label: string | RegExp) {
  await page.getByRole("button", { name: label }).click();
}

/**
 * Click a Naive UI NTabs tab by label text.
 * Naive UI tabs do not use role="tab"; they render as .n-tabs-tab divs.
 * TODO: add data-testid attributes to NTabPane tab elements in IncidentDetail.vue.
 */
async function clickTab(page: Page, label: string | RegExp) {
  await page.locator(".n-tabs-tab").filter({ hasText: label }).click();
}

/**
 * Accept a Naive UI NPopconfirm.
 * The confirm dialog renders "Cancel" and "Confirm" buttons inside
 * .n-popconfirm. We click the "Confirm" button.
 * TODO: add data-testid="popconfirm-confirm" to the positive button in any
 *       project-level Naive UI customisation to use a testid selector.
 */
async function confirmPopconfirm(page: Page) {
  await page.locator(".n-popconfirm").getByRole("button", { name: "Confirm" }).click();
}

// ---------------------------------------------------------------------------
// Suite — all scenarios share a real incident created in Scenario 1.
// Using test.describe.serial so tests run sequentially and share state.
// ---------------------------------------------------------------------------

test.describe.serial("Golden path — full incident lifecycle", () => {
  // -------------------------------------------------------------------------
  // Scenario 1: Worker submits an incident with a photo
  // -------------------------------------------------------------------------
  test("Scenario 1 — worker submits an incident with a photo", async ({ page }) => {
    await loginAs(page, WORKER_EMAIL, PASSWORD);

    // Navigate to the new incident form.
    await page.goto("/incidents/new");
    // TODO: add data-testid="page-title" to the <h1> in IncidentNew.vue
    await expect(page.getByRole("heading", { name: /report an incident/i })).toBeVisible();

    // --- Step 1: What ---
    // Incident type — the NSelect renders a clickable element.
    // TODO: add data-testid="incident-type-select" to <n-select> in IncidentNew.vue
    await page.locator(".n-select").first().click();
    await page.getByText("Near-miss").click();

    // Severity — second NSelect on the page. Options render as "S2 — Major" etc;
    // match the leading code with a regex so the descriptive label can evolve.
    await page.locator(".n-select").nth(1).click();
    await page.getByText(/^S2\b/).click();

    // Summary
    // TODO: add data-testid="summary-input" to the summary <n-input>
    await page.locator('[placeholder="One-line summary"]').fill("E2E golden-path test incident");

    // Description
    await page.locator('[placeholder="What happened?"]').fill(
      "Created by automated Playwright golden-path spec"
    );

    // Advance to step 2.
    await clickButton(page, "Next");

    // --- Step 2: Where & when ---
    // Site is already pre-selected for the worker (Sydney Warehouse).
    // Location
    await page.locator('[placeholder="e.g. Aisle 5, Loading bay"]').fill("Aisle 5, Bay C");

    // Advance to step 3 (Witnesses — optional, skip).
    await clickButton(page, "Next");

    // --- Step 3: Witnesses — skip ---
    await clickButton(page, "Next");

    // --- Step 4: Photos ---
    // Naive UI NUpload renders a hidden <input type="file" class="n-upload-file-input">.
    // Playwright's setInputFiles works on hidden inputs even without a dialog.
    // TODO: add data-testid="photo-upload-input" to the NUpload in IncidentNew.vue.
    await page.locator("input.n-upload-file-input").setInputFiles(PHOTO_PATH);

    // Advance to step 5 (review).
    await clickButton(page, "Next");

    // --- Step 5: Review & submit ---
    await expect(page.getByRole("heading", { name: /review/i })).toBeVisible();
    await clickButton(page, "Submit incident");

    // After submission the SPA redirects to /incidents/:id.
    await page.waitForURL(/\/incidents\/\d+$/, { timeout: 20_000 });

    // Extract the incident ID from the URL.
    const url = new URL(page.url());
    incidentId = url.pathname.split("/").pop()!;
    expect(incidentId).toMatch(/^\d+$/);

    // The detail page should show the incident state.
    // The badge/tag contains the state label.
    // TODO: add data-testid="incident-state-tag" to the <n-tag> in IncidentDetail.vue
    await expect(page.locator(".n-tag").filter({ hasText: "submitted" })).toBeVisible();
  });

  // -------------------------------------------------------------------------
  // Scenario 2: Investigator triages the incident
  // -------------------------------------------------------------------------
  test("Scenario 2 — investigator triages the incident", async ({ browser }) => {
    // Use a fresh context so we do not share cookies/localStorage with the
    // worker session from Scenario 1.
    const ctx: BrowserContext = await browser.newContext();
    const page = await ctx.newPage();

    try {
      await loginAs(page, INVESTIGATOR_EMAIL, PASSWORD);
      await page.goto(`/incidents/${incidentId}`);

      // Wait for the incident to load.
      // TODO: add data-testid="incident-state-tag"
      await expect(page.locator(".n-tag").filter({ hasText: "submitted" })).toBeVisible({
        timeout: 15_000
      });

      // The "Triage (assign me)" button is rendered inside an NPopconfirm.
      // Click the button and then confirm the popconfirm.
      await clickButton(page, /triage/i);
      await confirmPopconfirm(page);

      // After triage the state tag transitions to "investigating".
      await expect(page.locator(".n-tag").filter({ hasText: "investigating" })).toBeVisible({
        timeout: 15_000
      });
    } finally {
      await ctx.close();
    }
  });

  // -------------------------------------------------------------------------
  // Scenario 3: Bell badge increments live via WS push
  //
  // Cross-process push: Karafka consumer writes a delivery_log row and emits
  // NOTIFY on `delivery_log_appended`; the Falcon web process's PgListener
  // re-pushes to live WS sessions. The investigator's bell badge should update
  // without a page reload within ~3 seconds.
  // -------------------------------------------------------------------------
  test("Scenario 3 — bell badge increments live via WS push", async ({ browser }) => {
    test.setTimeout(90_000);

    // Context A: investigator — observe the badge.
    const ctxA: BrowserContext = await browser.newContext();
    const pageA = await ctxA.newPage();

    // Context B: worker — used only to obtain a token for the API call.
    const ctxB: BrowserContext = await browser.newContext();
    const pageB = await ctxB.newPage();

    try {
      // Investigator logs in and sits on the dashboard.
      await loginAs(pageA, INVESTIGATOR_EMAIL, PASSWORD);
      await pageA.goto("/dashboard");

      // Snapshot the current badge count BEFORE the new event arrives. The
      // .n-badge-sup element only renders when count > 0, so treat absence as 0.
      // TODO: add data-testid="inbox-badge" to the <n-badge> in AppShell.vue
      const readBadge = () =>
        pageA.evaluate(() => {
          const sup = document.querySelector(".n-badge-sup");
          return sup ? parseInt(sup.textContent?.trim() || "0", 10) || 0 : 0;
        });
      const countBefore = await readBadge();

      // Worker logs in; use their session's localStorage token to call the API
      // directly — this avoids a slow 5-step form and keeps the test under 90s.
      await loginAs(pageB, WORKER_EMAIL, PASSWORD);

      const workerToken = await pageB.evaluate(() => localStorage.getItem("ehs.jwt"));
      const apiBase = "http://localhost:3000/api/v1";

      // Look up the worker's site dynamically — seed IDs drift across resets.
      const meRes = await pageB.request.get(`${apiBase}/me`, {
        headers: { Authorization: `Bearer ${workerToken}` }
      });
      expect(meRes.ok()).toBeTruthy();
      const me = await meRes.json();
      const workerSiteId = me.data.attributes.sites[0]?.id;
      expect(workerSiteId).toBeTruthy();

      // Create a draft incident.
      const createRes = await pageB.request.post(`${apiBase}/incidents`, {
        headers: { Authorization: `Bearer ${workerToken}` },
        data: {
          incident: {
            incident_type: "slip",
            severity: 3,
            summary: "Scenario 3 bell-badge incident",
            description: "Bell badge test — created via API to keep test fast",
            site_id: workerSiteId,
            location: "Roof A",
            occurred_at: new Date().toISOString()
          }
        }
      });
      expect(createRes.ok()).toBeTruthy();
      const created = await createRes.json();
      const newId = created.data.id;

      // Submit the incident (transition from draft → submitted).
      const transitionRes = await pageB.request.post(`${apiBase}/incidents/${newId}/transitions`, {
        headers: { Authorization: `Bearer ${workerToken}` },
        data: { event: "submit" }
      });
      expect(transitionRes.ok()).toBeTruthy();

      // The Kafka → Karafka → in_app channel → NOTIFY → PgListener → WS push
      // chain should deliver to the investigator's open session within a few
      // seconds. No reload — the SPA receives the live frame and increments the
      // badge in place.
      await expect
        .poll(readBadge, {
          timeout: 15_000,
          message: "expected bell badge to increment via live WS push"
        })
        .toBeGreaterThan(countBefore);
    } finally {
      await ctxA.close();
      await ctxB.close();
    }
  });

  // -------------------------------------------------------------------------
  // Scenario 4: Corrective action — assign, complete, verify → incident closes
  // -------------------------------------------------------------------------
  test("Scenario 4 — assign corrective action, worker completes it, investigator verifies", async ({
    browser
  }) => {
    // Scenario 4 opens 3 sequential browser contexts; allow extra time.
    test.setTimeout(120_000);
    // --- Step A: Create a corrective action via API, then transition via UI ---
    //
    // NOTE: The "New corrective action" form in IncidentDetail.vue populates
    // its assignee dropdown by calling GET /api/v1/admin/users, which is
    // restricted to admin role only. Investigators get a 403, so the dropdown
    // stays empty when logged in as investigator. The form therefore cannot be
    // submitted through the UI by the investigator.
    //
    // This is a known bug: the SPA's loadOrgUsers() explicitly tries the admin
    // endpoint for investigators, but the backend's AdminAccessPolicy requires
    // admin role. A dedicated non-admin users endpoint is needed (tracked as a
    // follow-up). Until then, this test creates the corrective action via the
    // API (using the investigator's own token) and then tests the UI for the
    // state transition, which IS testable through the UI.
    //
    // TODO(fix): add a GET /api/v1/members or GET /api/v1/org/users endpoint
    // accessible to investigators for the assignee picker.
    const ctxInv: BrowserContext = await browser.newContext();
    const pageInv = await ctxInv.newPage();

    try {
      await loginAs(pageInv, INVESTIGATOR_EMAIL, PASSWORD);

      // Obtain the token for direct API calls.
      const invToken = await pageInv.evaluate(() => localStorage.getItem("ehs.jwt"));
      const apiBase = "http://localhost:3000/api/v1";

      // Look up the worker's user id dynamically — seed IDs drift across resets.
      const usersRes = await pageInv.request.get(`${apiBase}/admin/users`, {
        headers: { Authorization: `Bearer ${invToken}` }
      });
      let workerId: number | null = null;
      if (usersRes.ok()) {
        const list = await usersRes.json();
        workerId = Number(
          list.data.find((u: { attributes: { email: string } }) => u.attributes.email === WORKER_EMAIL)?.id
        );
      }
      if (!workerId) {
        // Investigators get 403 on /admin/users; fall back to logging in as the
        // worker briefly to read /me.id.
        const ctxLookup = await browser.newContext();
        const pageLookup = await ctxLookup.newPage();
        await loginAs(pageLookup, WORKER_EMAIL, PASSWORD);
        const tok = await pageLookup.evaluate(() => localStorage.getItem("ehs.jwt"));
        const meRes = await pageLookup.request.get(`${apiBase}/me`, {
          headers: { Authorization: `Bearer ${tok}` }
        });
        const me = await meRes.json();
        workerId = Number(me.data.id);
        await ctxLookup.close();
      }
      expect(workerId).toBeTruthy();

      // Create the corrective action via API (works for investigator role).
      const caRes = await pageInv.request.post(
        `${apiBase}/incidents/${incidentId}/corrective_actions`,
        {
          headers: { Authorization: `Bearer ${invToken}` },
          data: {
            corrective_action: {
              title: "Fix aisle 5 lighting",
              description: "Created via API in e2e test due to investigator/admin permission gap",
              due_date: new Date(Date.now() + 7 * 24 * 3600_000).toISOString(),
              assignee_id: workerId
            }
          }
        }
      );
      expect(caRes.ok()).toBeTruthy();

      // Load the incident detail page to verify the action appears in the UI.
      await pageInv.goto(`/incidents/${incidentId}`);
      await expect(pageInv.locator(".n-tag").filter({ hasText: "investigating" })).toBeVisible({
        timeout: 15_000
      });

      await clickTab(pageInv, /corrective actions/i);
      await expect(pageInv.getByText("Fix aisle 5 lighting")).toBeVisible({ timeout: 10_000 });

      // Transition the incident: investigating → pending_closure ("Send for verification").
      await clickButton(pageInv, /send for verification/i);
      await confirmPopconfirm(pageInv);
      await expect(pageInv.locator(".n-tag").filter({ hasText: "pending_closure" })).toBeVisible({
        timeout: 15_000
      });
    } finally {
      await ctxInv.close();
    }

    // --- Step B: Worker starts and completes the action ---------------------
    const ctxWorker: BrowserContext = await browser.newContext();
    const pageWorker = await ctxWorker.newPage();

    try {
      await loginAs(pageWorker, WORKER_EMAIL, PASSWORD);

      // Navigate to My Actions.
      await pageWorker.goto("/actions");
      await expect(pageWorker.getByRole("heading", { name: /my actions/i })).toBeVisible();

      // Find the corrective action row.
      await expect(pageWorker.getByText("Fix aisle 5 lighting").first()).toBeVisible({
        timeout: 15_000
      });

      // Find the specific action row for THIS run's incident using the incident ID.
      // The NDataTable renders incident IDs as clickable links in each row.
      // Filter by both the title AND the incident ID to avoid matching rows from
      // previous test runs that used the same action title.
      // TODO: add data-testid to the actions table rows.
      const actionRow = pageWorker
        .locator("tr")
        .filter({ hasText: "Fix aisle 5 lighting" })
        .filter({ hasText: `#${incidentId}` });
      await expect(actionRow).toBeVisible({ timeout: 10_000 });

      // Start the action within that row.
      await actionRow.getByRole("button", { name: "start" }).click();

      // The table reloads; the row now shows "in_progress" and a "complete" button.
      await expect(actionRow.getByText("in_progress")).toBeVisible({ timeout: 10_000 });

      // Complete the action.
      await actionRow.getByRole("button", { name: "complete" }).click();

      await expect(actionRow.getByText("done")).toBeVisible({ timeout: 10_000 });
    } finally {
      await ctxWorker.close();
    }

    // --- Step C: Investigator verifies the action → incident closes ----------
    const ctxInv2: BrowserContext = await browser.newContext();
    const pageInv2 = await ctxInv2.newPage();

    try {
      await loginAs(pageInv2, INVESTIGATOR_EMAIL, PASSWORD);

      await pageInv2.goto(`/incidents/${incidentId}`);
      await clickTab(pageInv2, /corrective actions/i);

      // The action should now be in "done" state — verify it via the UI.
      await expect(pageInv2.getByText("done")).toBeVisible({ timeout: 15_000 });

      // Click the action-level "verify" button (inside the n-list, not the header).
      const actionsList = pageInv2.locator(".n-list");
      await actionsList.getByRole("button", { name: "verify" }).first().click();

      await expect(pageInv2.getByText("verified")).toBeVisible({ timeout: 10_000 });

      // Verifying the last corrective action triggers maybe_close_parent_incident!
      // on the backend, which auto-transitions the incident to "closed" via AASM.
      // The frontend's loadAux() (called after actionTransition) does not reload
      // the incident itself, so the UI temporarily shows stale "pending_closure".
      // Reloading the page picks up the authoritative backend state.
      //
      // NOTE: the frontend has a known gap here — actionTransition should also call
      // loadIncident() when the auto-close backend callback fires. Until that is
      // fixed, the test reloads to get the correct state.
      await pageInv2.reload();
      await expect(pageInv2.locator(".n-tag").filter({ hasText: "closed" })).toBeVisible({
        timeout: 15_000
      });
    } finally {
      await ctxInv2.close();
    }
  });

  // -------------------------------------------------------------------------
  // Scenario 5: Versions tab shows the audit trail
  // -------------------------------------------------------------------------
  test("Scenario 5 — versions tab shows the audit trail", async ({ browser }) => {
    const ctx: BrowserContext = await browser.newContext();
    const page = await ctx.newPage();

    try {
      await loginAs(page, INVESTIGATOR_EMAIL, PASSWORD);
      await page.goto(`/incidents/${incidentId}`);

      // Navigate to the Versions tab.
      // TODO: add data-testid="tab-versions"
      await clickTab(page, /versions/i);

      // The version list must contain at least the create event plus several
      // update events (state transitions through the lifecycle). Confirm ≥ 3.
      const versionItems = page.locator(".n-list-item .n-thing");
      await expect(versionItems.first()).toBeVisible({ timeout: 10_000 });
      const count = await versionItems.count();
      expect(count).toBeGreaterThanOrEqual(3);

      // PaperTrail records "create" / "update" as event types — not AASM event
      // names. The version title format is "Event · username" (IncidentDetail.vue
      // maps create→Created, update→Updated for readability).
      //
      // The creation event is always present.
      await expect(page.locator(".n-thing-header__title").filter({ hasText: /^Created/ })).toBeVisible();
      // State changes render as "State submitted → investigating" rows in the
      // diff. Both keywords must appear after a full lifecycle.
      await expect(page.getByText(/submitted/i).first()).toBeVisible();
      await expect(page.getByText(/investigating/i).first()).toBeVisible();
    } finally {
      await ctx.close();
    }
  });
});
