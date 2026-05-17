# ADR-0009: Redis is required by Sidekiq

- **Status:** Accepted
- **Date:** 2026-05-17

## Context

We chose Sidekiq for background jobs (ADR omitted because it's a default Ruby
choice). Sidekiq stores its queue, scheduled set, retry set, dead set, and
unique-job tokens in Redis. There is no built-in Postgres backend.

## Decision

Run Redis in the stack solely to back Sidekiq. Don't reuse it for cache or
ActionCable — we're not using either.

## Consequences

**Wins**
- Industry-standard Ruby job runner; mentioned in nearly every Ruby JD
- Mature observability (Sidekiq Web UI, Prometheus exporter)

**Costs**
- Another stateful component to operate (small; Redis is cheap)
- If a portfolio reviewer pushes back on "why not SolidQueue (Postgres-backed)?": SolidQueue is newer (Rails 8 default) and less prevalent in 2026 production Ruby shops — Sidekiq is the stronger resume signal
