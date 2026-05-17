# Personas

Three personas drive every UX decision. Everything in the product maps to one of them.

## Worker — "Alex, line operator at Sydney Warehouse"

- **Context:** On the warehouse floor; uses the app from a tablet or shared workstation; not technical
- **Wants:** Submit an incident quickly with photos; check the status of the things they reported; complete actions assigned to them
- **Hates:** Forms with 30 fields; jargon; remembering passwords for things they use once a month
- **Implications for UX:** Submission form is multi-step (what / where / when / witnesses / photos); fields are plain English; mobile-friendly (we ship desktop-first but no layout breaks on tablet)

## Investigator — "Pat, HSE coordinator at Acme HQ"

- **Context:** Power user; spends meaningful time in the app each week; manages 3-15 active incidents at any time
- **Wants:** Triage queue sorted by severity & age; one-click state transitions; clear audit history; a real keyboard-driven dashboard
- **Hates:** Lost work (modal dialogs that lose state); having to chase up assigned action owners manually
- **Implications:** Dashboard with KPIs first; bulk operations on action queues; email + in-app digest of overdue items; copy-link / share-state in every URL

## Admin — "Sam, EHS Manager, multi-site"

- **Context:** Configures the workspace once a quarter, otherwise hands-off; sometimes deputizes as Investigator
- **Wants:** Invite users; lock departed staff; configure severity SLAs per org; export reports; understand what's happening across all sites
- **Hates:** Not knowing who has access to what
- **Implications:** Admin section is a separate route tree; user list shows role + sites at a glance; soft-delete keeps audit history; everything an admin does is auditable too

## What we deliberately don't build for

- **Contractors** (external, occasional users with limited access) — out of scope for MVP, doable later
- **Board / executive observers** (read-only with summary dashboards) — could be served by the existing admin dashboard plus a permission flag, but not in scope
- **Auditors** (regulatory reviewers needing exports + immutable history) — PaperTrail history is there, but the export tooling and tamper-evident log are deferred
