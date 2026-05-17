# C4 Level 2 — Containers

How the system is decomposed into deployable units, and how they communicate.

```mermaid
C4Container
    title Containers — EHS Incident System

    Person(user, "User", "Worker / Investigator / Admin")

    System_Boundary(ehs, "EHS Incident System") {
        Container(spa,      "Vue SPA",        "Vue 3 + TypeScript + Vite",       "Single-page app: views, forms, in-app notification badge")
        Container(coreApi,  "core-api",       "Rails 7.2 (API-only), Ruby 3.3",  "Domain logic, auth, REST, outbox publisher")
        Container(sidekiq,  "sidekiq",        "Ruby, Sidekiq + sidekiq-cron",    "Outbox shipper, SLA scans, daily digests")
        Container(notifier, "notifier",       "Sinatra + Karafka + Falcon",      "Consumes events, fans out to email/Telegram/in-app, hosts WebSocket server")
        ContainerDb(appDb,    "ehs_app",        "PostgreSQL 16",     "Domain, auth, outbox, audit (PaperTrail)")
        ContainerDb(notifDb,  "ehs_notifier",   "PostgreSQL 16",     "users_mirror, delivery_log, telegram_chat_links")
        ContainerDb(redis,    "Redis",          "Redis 7",           "Sidekiq queues, scheduled set, retry set")
        ContainerDb(kafka,    "Kafka + Karapace","Kafka KRaft + Karapace", "Event bus + Avro schema registry")
        Container(minio,    "MinIO",          "S3-compatible",                  "Attachment blob store")
    }

    System_Ext(smtp,     "SMTP",         "MailCatcher / SES / SendGrid")
    System_Ext(telegram, "Telegram API", "Bot API for outbound messages")

    Rel(user,    spa,      "Uses",        "HTTPS")
    Rel(spa,     coreApi,  "REST + JWT",  "HTTPS")
    Rel(spa,     notifier, "WebSocket",   "WSS")

    Rel(coreApi, appDb,   "Reads / writes")
    Rel(coreApi, redis,   "Enqueues Sidekiq jobs")
    Rel(coreApi, minio,   "Stores attachments (ActiveStorage)")

    Rel(sidekiq, redis,    "Pulls jobs")
    Rel(sidekiq, appDb,    "Reads outbox, writes audit")
    Rel(sidekiq, kafka,    "Publishes domain events", "Avro / Confluent wire format")

    Rel(notifier, kafka,    "Consumes events", "Karafka consumer groups")
    Rel(notifier, notifDb,  "Maintains mirror + delivery log")
    Rel(notifier, smtp,     "Sends emails", "SMTP")
    Rel(notifier, telegram, "Sends Telegram messages", "HTTPS")
```

## Why this shape

The deliberate split is:

- **One service that owns the truth** — `core-api`. It does all writes to the canonical store and is the only thing the SPA writes to.
- **One service that owns delivery** — `notifier`. It maintains its own derived state (`users_mirror`, `delivery_log`) so it can run independently of `core-api`'s availability.
- **Kafka as the contract** — schema-versioned, durable, replayable.

We don't go to true microservices (one per aggregate) because the domain isn't large enough to need them — and the cost (more inter-service calls, distributed transactions, more deploy units) outweighs the benefit at this scale.

## Why two databases

| Database | Owner | Why separate |
|---|---|---|
| `ehs_app` | core-api | Source of truth for domain entities |
| `ehs_notifier` | notifier | Derived state (`users_mirror`, `delivery_log`); separating enforces the service boundary at the storage layer — no accidental cross-service joins |

Both live in the same Postgres instance for simplicity; in a larger deploy they'd be separate clusters.

## What's NOT here (yet)

- A dedicated read-replica for analytics
- A separate auth/IdP service (Keycloak / Auth0) — local auth via Devise for now; SSO is documented in [ADR-0008](05-decisions/0008-sso-saml-as-next-step.md)
- A second Kafka consumer for analytics — `incidents.v1` is already designed to support one without changes
