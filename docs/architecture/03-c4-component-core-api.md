# C4 Level 3 — core-api internals

```mermaid
flowchart LR
    spa[/Vue SPA<br/>REST + JWT/]
    admin[/Operator<br/>Sidekiq::Web/]

    subgraph coreApi["core-api (Rails 8.1 API-only)"]
        direction TB

        subgraph auth["Auth"]
            devise[Devise + devise-jwt]
            denylist[(JwtDenylist)]
            sessions[Auth::SessionsController]
            regs[Auth::RegistrationsController]
            pwd[Auth::PasswordsController]
            confirm[Auth::ConfirmationsController]
        end

        subgraph controllers["REST controllers (Api::V1)"]
            base[BaseController<br/><i>JWT + Pundit + PaperTrail whodunnit</i>]
            inc[IncidentsController]
            ca[CorrectiveActionsController]
            comm[CommentsController]
            wit[WitnessesController]
            att[AttachmentsController]
            sites[SitesController]
            notif[NotificationsController]
            dash[DashboardController]
            me[MeController]
            iv[IncidentVersionsController]
            cav[CorrectiveActionVersionsController]
        end

        subgraph adminCtrls["Admin namespace"]
            adminUsers[Admin::UsersController]
            adminSites[Admin::SitesController]
            adminSettings[Admin::SettingsController]
        end

        subgraph policies["Pundit policies"]
            pol[incident / corrective_action /<br/>comment / witness / attachment /<br/>site / user / organization_setting /<br/>admin_access]
        end

        subgraph domain["Domain models"]
            incModel[Incident<br/><i>AASM</i>]
            caModel[CorrectiveAction<br/><i>AASM</i>]
            user[User<br/><i>Devise + roles</i>]
            org[Organization]
            site[Site / SiteMembership]
            commentM[Comment]
            witM[Witness]
            orgSet[OrganizationSetting]
        end

        subgraph events["Event publication"]
            bus[EventBus]
            uep[UserEventPublisher<br/><i>CDC, PII via FieldCipher</i>]
            outbox[(outbox_events)]
        end

        subgraph workers["Sidekiq workers"]
            shipper[OutboxShipperJob]
            sla[SlaBreachScanJob]
            overdue[OverdueActionScanJob]
            digest[DailyDigestJob]
        end

        paper[PaperTrail<br/><i>versions table</i>]
        tenant[TenantScoped concern]
    end

    appDb[(ehs_app<br/>PostgreSQL)]
    redis[(Redis)]
    kafka[/Kafka<br/>incidents.v1<br/>corrective_actions.v1<br/>system.v1<br/>users.v1 - CDC/]
    minio[(MinIO<br/>ActiveStorage)]

    spa --> base
    admin --> sessions
    spa --> sessions
    base --> pol --> domain
    sessions & regs & pwd & confirm --> devise --> user
    devise --> denylist
    adminCtrls --> pol
    domain --> paper
    incModel & caModel --> bus --> outbox
    user --> uep --> outbox
    domain <--> appDb
    paper --> appDb
    outbox --> appDb
    base --> tenant

    shipper --> outbox
    shipper --> kafka
    sla & overdue --> domain
    sla & overdue & digest --> bus
    workers <--> redis
    base --> redis

    att --> minio
```

## Why this shape

- **Layered Rails** — controller → policy → model. `Api::V1::BaseController` is the only place that knows about JWT, Pundit, and PaperTrail's `whodunnit`; the resource controllers stay thin.
- **AASM owns state** — `Incident` and `CorrectiveAction` expose verbs (`submit!`, `triage!`, `complete!`, …); illegal transitions are rejected at the model, not the controller. State change is also the trigger for event emission.
- **One service, one DB, one event log** — no 2PC. Domain writes and `outbox_events` rows commit in the same transaction; a separate shipper job ships them. This is the core reliability primitive of the write path.
- **Pundit + `TenantScoped`** — every policy resolves through `scope_for(user)` on the org tenant. The boundary is enforced in policies, not in controllers or model `default_scope`, so there is exactly one place to look for "can this user see X."
- **Background work lives in [core-api/app/jobs/](../../core-api/app/jobs/)** — sidekiq is its own container ([02-c4-container.md](02-c4-container.md)) but the code is part of core-api: same models, same migrations, same deploy artifact.
- **PaperTrail at the model layer** — every audited model writes a `versions` row on update/destroy with the `whodunnit` set from `Current.user`. `IncidentVersionsController` and `CorrectiveActionVersionsController` expose this as the audit log API.

## Transactional outbox

```mermaid
sequenceDiagram
    autonumber
    participant Ctrl as Controller
    participant Model as Incident / CorrectiveAction
    participant Bus as EventBus
    participant Outbox as outbox_events
    participant Shipper as OutboxShipperJob
    participant Kafka

    Ctrl->>Model: transition! (AASM)
    activate Model
    Note over Model,Outbox: single DB transaction
    Model->>Bus: publish!(event)
    Bus->>Outbox: INSERT (event_id, topic, payload)
    Model-->>Ctrl: ok
    deactivate Model

    loop every 5s
        Shipper->>Outbox: SELECT pending LIMIT N
        Shipper->>Kafka: produce (Avro / Confluent wire)
        Shipper->>Outbox: mark_published!(event_id)
    end
```

`event_id` is a ULID generated inside the transaction. The shipper is idempotent on it — duplicate ships are absorbed by consumers' `delivery_log` ([03-c4-component-notifier.md](03-c4-component-notifier.md)). Failures bump `attempt_count` and stash `last_error`; the row stays pending until success.

## Sidekiq workers

| Job | Queue | Schedule | Purpose |
|---|---|---|---|
| `OutboxShipperJob` | `outbox` | `*/5 * * * * *` (every 5 s) | Ships pending `outbox_events` to Kafka |
| `SlaBreachScanJob` | `default` | `0 * * * *` (hourly) | Flags submitted incidents past triage SLA; emits `SlaBreached` |
| `OverdueActionScanJob` | `default` | `0 8 * * *` (daily 08:00) | Flags open/in-progress CAs past `due_date`; emits `CorrectiveActionOverdue`; 24 h de-dupe via `overdue_notified_at` |
| `DailyDigestJob` | `default` | `0 7 * * *` (daily 07:00) | Per-user notification digest |

Schedule lives in [core-api/config/sidekiq.yml](../../core-api/config/sidekiq.yml) and is loaded by [core-api/config/initializers/sidekiq_cron.rb](../../core-api/config/initializers/sidekiq_cron.rb). Queue priorities are `[critical, 3] [default, 2] [outbox, 2] [low, 1]`.

## Auth

JWT issuance and verification live in [core-api/app/controllers/api/v1/auth/sessions_controller.rb](../../core-api/app/controllers/api/v1/auth/sessions_controller.rb) (Devise + devise-jwt). Access tokens are short-lived; refresh is via an httpOnly cookie. Revocation is `JwtDenylist` (Devise's denylist strategy). See [docs/flows/auth-and-jwt-refresh.md](../flows/auth-and-jwt-refresh.md) for the end-to-end refresh sequence.

## Tenant scoping

[core-api/app/models/concerns/tenant_scoped.rb](../../core-api/app/models/concerns/tenant_scoped.rb) provides `for_org(org)` and `scope_for(user)`. Every Pundit policy in [core-api/app/policies/](../../core-api/app/policies/) inherits from `ApplicationPolicy`, whose `Scope#resolve` calls `scope_for(@user)`. Org isolation is therefore enforced once, in the policy layer — not via `default_scope` or controller filters.

## See also

- [03-c4-component-notifier.md](03-c4-component-notifier.md) — what consumes the events on the other side
- [03-c4-component-frontend.md](03-c4-component-frontend.md) — what calls the REST surface
- [02-c4-container.md](02-c4-container.md) — how this fits into the broader topology
