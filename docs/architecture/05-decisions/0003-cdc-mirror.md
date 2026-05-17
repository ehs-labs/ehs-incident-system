# ADR-0003: CDC mirror for user identity in notifier

- **Status:** Accepted
- **Date:** 2026-05-17

## Context

Notifier needs to resolve `user_id → email / telegram_chat_id / role / prefs`
on every event. Options:

1. Call core-api HTTP per event
2. Maintain a local read-model fed by a `users.v1` CDC topic

## Decision

Option 2 — **CDC mirror**. core-api publishes a `UserUpserted` event on every
user create/update; `users.v1` is **log-compacted** so the topic is a
key/value store of latest-per-user. Notifier consumes it into `users_mirror`.

## Consequences

**Wins**
- Notifier survives core-api downtime
- No per-event HTTP round-trips
- Log-compacted topic means cold-start = replay-from-zero, no separate snapshot needed

**Costs**
- Eventual consistency on user changes (typically < 1 s end-to-end)
- The mirror schema lives in two places (core-api producer + notifier consumer); ADR-0004 covers PII handling
