# Admin guide

You have all investigator powers, plus organization-level configuration.

## Inviting a user

1. **Admin → Users → Invite**
2. Enter email, name, role (Worker / Investigator / Admin), site memberships
3. Click **Send invitation**
4. User receives an email with a one-time signup link (expires in 3 days)

## Locking / unlocking

A user is auto-locked after 5 failed login attempts. To unlock manually:

1. **Admin → Users → search the user**
2. Open their detail page
3. Click **Unlock**

To prevent a departed staff member from logging in immediately, click **Lock** on their detail page — they cannot log in even with a valid password.

## Soft-deleting a user

Click **Delete** on a user's detail. This:

- Sets `deleted_at`
- Revokes all their JWTs (denylist)
- Hides them from user pickers
- **Preserves audit history** — their actions remain in PaperTrail

To fully purge (very rare — typically only for GDPR DSAR), use the documented purge runbook in `docs/operations/data-handling.md` (not in MVP).

## Sites

Sites have an IANA timezone (e.g. `Australia/Sydney`). SLA timers use the site's local time.

## Settings (per-org)

- Severity → triage SLA mapping (defaults: S1/S2 = 4h, S3 = 24h, S4/S5 = 72h)
- Severity → action default due-date mapping (defaults: S1/S2 = 7d, S3 = 14d, S4/S5 = 30d)
- Notification defaults (per event-type per channel)
- Signup enabled / disabled (overrides the env-level `SIGNUP_ENABLED`)
