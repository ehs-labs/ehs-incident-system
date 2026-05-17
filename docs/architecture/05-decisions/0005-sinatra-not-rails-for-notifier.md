# ADR-0005: Sinatra (not Rails) for the notifier service

- **Status:** Accepted
- **Date:** 2026-05-17

## Context

The notifier has no domain model — it's a pipeline that consumes events,
joins against a small mirror table, and dispatches through channel adapters.
A standard Rails app would carry ActiveRecord, asset pipeline, action mailer
configuration, route generators, etc. — 90% of which we don't use.

## Decision

Build notifier as a **Sinatra** app. Use **Sequel** for DB access (lighter than
AR, native migrations). Use **Falcon** as the async server for cheap WebSocket
fan-out.

## Consequences

**Wins**
- Notifier image is ~150 MB vs ~400 MB for the Rails equivalent
- Boot time < 1 s; faster restarts in K8s rollouts
- Showcases breadth: Rails *plus* Sinatra, AR *plus* Sequel
- Async-by-default for WebSockets via Falcon

**Costs**
- Two web frameworks in the repo (small cost; both are mainstream)
- Reviewers familiar only with Rails need to learn one extra DSL — but Sinatra and Sequel are both small
