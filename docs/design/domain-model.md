# Domain model

```mermaid
erDiagram
    ORGANIZATION ||--o{ SITE : has
    ORGANIZATION ||--o{ USER : has
    SITE         }o--o{ USER : "membership"
    USER         ||--o{ INCIDENT : "reports / is assigned to"
    SITE         ||--o{ INCIDENT : "occurs at"
    ORGANIZATION ||--o{ INCIDENT : owns
    INCIDENT     ||--o{ WITNESS : "has"
    INCIDENT     ||--o{ ATTACHMENT : "has"
    INCIDENT     ||--o{ COMMENT : "has"
    INCIDENT     ||--o{ CORRECTIVE_ACTION : "results in"
    USER         ||--o{ CORRECTIVE_ACTION : "is assigned"
    CORRECTIVE_ACTION ||--o| ATTACHMENT : "evidence"

    ORGANIZATION {
        ulid id PK
        string name
        string slug "unique"
        datetime created_at
    }
    SITE {
        ulid id PK
        ulid org_id FK
        string name
        string timezone "IANA, e.g. Australia/Sydney"
    }
    USER {
        ulid id PK
        ulid org_id FK
        string email "unique per org"
        string name
        enum role "worker | investigator | admin"
        datetime invited_at
        datetime confirmed_at
        datetime locked_at
        datetime deleted_at
        string telegram_chat_id "nullable"
    }
    INCIDENT {
        ulid id PK
        ulid org_id FK
        ulid site_id FK
        ulid reporter_id FK
        ulid assignee_id FK "nullable until triaged"
        string type
        int severity "1-5"
        datetime occurred_at
        string location
        string summary
        text description
        text root_cause "filled during investigation"
        enum state "AASM column"
        tsvector tsv "for pg_search"
        datetime created_at
        datetime closed_at
    }
    WITNESS {
        ulid id PK
        ulid incident_id FK
        string name
        string contact
        text statement
    }
    ATTACHMENT {
        ulid id PK
        string attachable_type "Incident | CorrectiveAction"
        ulid attachable_id
        ulid uploader_id FK
        string filename
        string content_type
        bigint byte_size
        enum kind "photo | document"
    }
    CORRECTIVE_ACTION {
        ulid id PK
        ulid incident_id FK
        ulid assignee_id FK
        string title
        text description
        date due_date
        enum state "open | in_progress | done | verified | cancelled"
        datetime completed_at
    }
    CORRECTIVE_ACTION_EVENT {
        ulid id PK
        ulid corrective_action_id FK
        enum event_name "assigned | started | completed | verified | cancelled"
        ulid actor_id FK
        text note
        datetime created_at
    }
    COMMENT {
        ulid id PK
        ulid incident_id FK
        ulid author_id FK
        text body
        datetime created_at
    }
```

## Key constraints

- **Tenant scoping** — every row except `Organization` and `User` (which references org) has `org_id`; enforced by `default_scope` on each AR model + Pundit `Scope` classes.
- **ULIDs as primary keys** — sortable by creation time, URL-safe, no collisions across services. Future-proofs sharding.
- **Soft delete on `User`** — sets `deleted_at`, JWTs revoked via denylist, audit history preserved (PaperTrail).
- **Polymorphic `Attachment`** — same table backs both incident photos and corrective-action evidence.

## What the AASM `state` column drives

| Model | States |
|---|---|
| `Incident` | `draft → submitted → investigating → pending_closure → closed` (plus reopen) |
| `CorrectiveAction` | `open → in_progress → done → verified` |

Full diagrams: [state-machines.md](state-machines.md).

## PaperTrail audit and domain event logs

Versions are written for every change on `Incident` and `CorrectiveAction`.
This is critical for the EHS narrative — incident records must be defensible in
regulatory reviews, which means "who changed what when" is non-negotiable.

`corrective_action_events` is a separate append-only **domain audit log**
distinct from PaperTrail's `versions` table. It captures *who made which state
transition with what note*, while `versions` captures *what attribute diffs
were applied*. Both serve compliance, but the SPA's Activity feed reads from
`corrective_action_events`, which gives it operator-level semantics (started,
completed, verified, etc.) without unpacking attribute diffs.

## Search

`incidents.tsv` is a `tsvector` populated by `pg_search` from `summary +
description + root_cause`. A GIN index on it makes full-text search fast without
dragging in Elasticsearch.
