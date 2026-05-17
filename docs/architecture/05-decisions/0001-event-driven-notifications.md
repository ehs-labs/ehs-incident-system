# ADR-0001: Event-driven notifications via Kafka + a separate notifier service

- **Status:** Accepted
- **Date:** 2026-05-17

## Context

Notifications in EHS span at least three channels (email, Telegram, in-app
WebSocket) and are time-sensitive. The default Rails approach — a Sidekiq job
per notification firing from an `after_save` callback in core-api — works, but
has drawbacks:

- Couples notification logic to the monolith
- One slow channel (e.g. Telegram timeout) holds up notification workers that
  could otherwise be sending email
- Future analytics consumer would have to scrape the database
- No replay / audit of the notification trigger separate from the domain event

## Decision

Domain state changes in core-api emit **events to Kafka via the transactional
outbox**. A separate **notifier service** consumes the events and fans them out
to channels.

- Topics: `incidents.v1`, `corrective_actions.v1`, `users.v1`, `system.v1`
- Schemas: Avro, registered in Karapace (open-source schema registry)
- Notifier owns its own database (`ehs_notifier`) for delivery log + user mirror
- core-api never makes synchronous calls to notifier

## Consequences

**Wins**
- Independent scaling — notification spikes don't slow domain APIs
- Adding a new channel = adding a new `Channel` class, no changes to core-api
- Future consumers (analytics, BI) plug in without touching producer code
- Clear audit trail of *what was published when*, separate from *what was attempted to be delivered*

**Costs**
- Two services to run, deploy, monitor (offset by the modest size of notifier)
- Kafka cluster to operate (acceptable — it's a portfolio-grade signal anyway)
- Eventual consistency — UI doesn't know "your action triggered a notification" synchronously; on submit the SPA assumes success and the WS push confirms

## Alternatives considered

- **Monolithic** (Sidekiq inside core-api) — simpler but loses the architectural narrative; recombines concerns
- **Redis Streams** instead of Kafka — easier ops, less resume signal, weaker schema governance
- **HTTP webhooks** instead of message broker — fragile to delivery failures; no replay
