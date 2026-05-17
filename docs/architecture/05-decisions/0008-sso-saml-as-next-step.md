# ADR-0008: SSO/SAML/OIDC is deferred to v2

- **Status:** Accepted (deferred)
- **Date:** 2026-05-17

## Context

Enterprise EHS customers will require SSO via SAML 2.0 or OIDC (Okta, Azure AD,
Google Workspace). Local auth via Devise is a starting point but doesn't scale
to that segment.

## Decision

MVP ships with **local auth only** (Devise + JWT + invitable + lockable +
confirmable). SSO is documented here as the v2 milestone with an explicit wiring sketch (omniauth-saml / omniauth_openid_connect).

## Consequences

**Wins**
- MVP scope is bounded; no IdP integration headaches
- Local auth is rich enough for a believable portfolio demo
- Mentioning SSO as a known next-step in an ADR is itself a positive interview signal

**Costs**
- Real EHS sales cycles will require SSO before signing
