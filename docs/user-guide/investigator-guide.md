# Investigator guide

## What you can do

- Triage incoming incidents from your sites
- Investigate (record root cause, comments, audit history)
- Create and assign corrective actions
- Close incidents once all actions are verified

## Triage queue

The dashboard shows incidents in `submitted` state sorted by severity and age.
Click an incident to open its detail; click **Triage** to:

- Set / confirm severity
- Assign to yourself or another investigator
- Add a triage note

## Investigation

In the **Investigating** state, you can:

- Add comments (visible to other investigators and admins; not to workers)
- Update the **Root cause** field — this is the audit-critical bit
- Add corrective actions (assignee + title + description + due date)

## Closure

Once **all corrective actions** are in the `verified` state, click **Verify & Close**.
The audit history (PaperTrail) captures who closed it and when.

## Reopening

If new information emerges, click **Reopen** on a closed incident. Reason required.

## Dashboard KPIs

- Open by severity (with SLA breach count)
- Overdue corrective actions
- Incident trend last 30 days
- Average time to close
