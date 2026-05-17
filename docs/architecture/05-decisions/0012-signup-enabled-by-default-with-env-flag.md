# ADR-0012: Signup is enabled by default in MVP

- **Status:** Accepted
- **Date:** 2026-05-17

## Context

Production EHS deployments are invite-only — admins onboard users. But this
is a portfolio project that strangers (recruiters, interviewers) will try
without an invitation.

## Decision

- `POST /api/v1/auth/signup` is **enabled by default**
- A new signup creates a fresh Organization and the user becomes its first admin
- Gated by `SIGNUP_ENABLED=true/false` so an operator can turn it off

## Consequences

**Wins**
- Anyone can try the demo without coordination
- The "first-admin-of-a-new-org" flow is exercised by every fresh signup — a useful test path

**Costs**
- In a public deployment, anonymous signup is spam-prone; we'd add CAPTCHA + rate limiting before opening to the internet (documented but not in MVP)
