# C4 Level 2 — Containers

How the system is decomposed into deployable units, and how they communicate.

```mermaid
%%{init: {'flowchart': {'htmlLabels': true}, 'themeVariables': {'fontSize': '18px'}}}%%
flowchart TB
    user["<b>User</b><br/><i>[Person]</i><br/>Worker / Investigator / Admin"]

    subgraph ehs["EHS Incident System"]
        direction TB
        spa["<b>Vue SPA</b><br/><i>[Container: Vue 3 + TypeScript + Vite]</i><br/>Single-page app: views, forms,<br/>in-app notification badge"]

        subgraph backend[" "]
            direction LR

            subgraph writePath["Write path"]
                direction TB
                coreApi["<b>core-api</b><br/><i>[Container: Rails 8.1 API-only, Ruby 4.0]</i><br/>Domain logic, auth, REST,<br/>outbox publisher"]
                sidekiq["<b>sidekiq</b><br/><i>[Container: Ruby, Sidekiq + sidekiq-cron]</i><br/>Outbox shipper, SLA scans,<br/>daily digests"]
                minio[("<b>MinIO</b><br/><i>[S3-compatible]</i><br/>Attachment blob store")]
                appDb[("<b>ehs_app</b><br/><i>[PostgreSQL 16]</i><br/>Domain, auth, outbox,<br/>audit (PaperTrail)")]
                redis[("<b>Redis</b><br/><i>[Redis 7]</i><br/>Sidekiq queues, scheduled set,<br/>retry set")]
            end

            kafka[("<b>Kafka + Karapace</b><br/><i>[Kafka KRaft + Karapace]</i><br/>Event bus +<br/>Avro schema registry")]

            subgraph fanout["Notification fanout"]
                direction TB
                notifier["<b>notifier</b><br/><i>[Container: Sinatra + Karafka + Falcon]</i><br/>Consumes events, fans out to<br/>email/Telegram/in-app,<br/>hosts WebSocket server"]
                notifDb[("<b>ehs_notifier</b><br/><i>[PostgreSQL 16]</i><br/>users_mirror, delivery_log,<br/>telegram_chat_links")]
            end
        end
    end

    smtp["<b>SMTP</b><br/><i>[External System]</i><br/>MailCatcher / SES / SendGrid"]
    telegram["<b>Telegram API</b><br/><i>[External System]</i><br/>Bot API for outbound messages"]

    user -->|"Uses<br/><i>[HTTPS]</i>"| spa
    spa -->|"REST + JWT<br/><i>[HTTPS]</i>"| coreApi
    spa -->|"WebSocket<br/><i>[WSS]</i>"| notifier

    coreApi -->|"Stores attachments<br/>(ActiveStorage)"| minio
    coreApi -->|"Reads / writes"| appDb
    coreApi -->|"Enqueues Sidekiq jobs"| redis

    sidekiq -->|"Pulls jobs"| redis
    sidekiq -->|"Reads outbox,<br/>writes audit"| appDb
    sidekiq -->|"Publishes domain events<br/><i>[Avro / Confluent wire format]</i>"| kafka

    kafka -->|"Consumes events<br/><i>[Karafka consumer groups]</i>"| notifier
    notifier -->|"Maintains mirror<br/>+ delivery log"| notifDb
    notifier -->|"Sends emails<br/><i>[SMTP]</i>"| smtp
    notifier -->|"Sends Telegram messages<br/><i>[HTTPS]</i>"| telegram

    classDef person    fill:#08427b,stroke:#052e56,color:#ffffff,stroke-width:1px
    classDef container fill:#1168bd,stroke:#0b4884,color:#ffffff,stroke-width:1px
    classDef external  fill:#999999,stroke:#6b6b6b,color:#ffffff,stroke-width:1px

    class user person
    class spa,coreApi,sidekiq,notifier,appDb,notifDb,redis,kafka,minio container
    class smtp,telegram external

    style ehs       fill:none,stroke:#0b4884,stroke-dasharray:5 5,color:#0b4884
    style backend   fill:none,stroke:none
    style writePath fill:none,stroke:#999,stroke-dasharray:3 3,color:#666
    style fanout    fill:none,stroke:#999,stroke-dasharray:3 3,color:#666
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
