# ADR-0002: Transactional outbox for event publishing

- **Status:** Accepted
- **Date:** 2026-05-17

## Context

Publishing to Kafka in the same code path as a DB write creates a distributed-transaction problem:

- DB commits, Kafka fails → event lost; downstream consumers don't know about the state change
- Kafka commits, DB fails → ghost event; consumers act on something that didn't happen
- Both succeed but app crashes between → ambiguous state

We need at-least-once event delivery with no XA / two-phase commit complexity.

## Decision

Adopt the **transactional outbox** pattern.

1. In the same DB transaction as the domain state change, INSERT a row into `outbox_events` (`event_id`, `topic`, `payload`, `published_at = NULL`).
2. A Sidekiq cron job (`OutboxShipperJob`, every 5 s) reads unpublished rows, produces them to Kafka, marks them `published_at = NOW()`.
3. Consumer-side idempotency via the `delivery_log` unique key on `(event_id, user_id, channel)` absorbs duplicates from Kafka redeliveries.

## Consequences

**Wins**
- No lost events, no ghost events, no XA
- Recovery is automatic — every tick of the shipper re-attempts unpublished rows
- The `outbox_events` table is itself an audit trail of what was emitted

**Costs**
- ~5 s typical delay between commit and Kafka publish (acceptable for notifications)
- One extra write per state change (acceptable; tiny)
- Extra Sidekiq cron job to operate

## Alternatives considered

- **Direct publish, fire-and-forget** — loses events on any failure
- **Debezium CDC on the app DB** — heavier infra; sends every row change including ones we don't model as events
- **Kafka transactions / EOS** — requires both producer and consumer to opt into transactional semantics; overkill for our throughput
