# Flow — SLA breach detection

The triage SLA is severity-driven. A nightly scan detects incidents that missed
their triage window and emits `SlaBreached` events.

```mermaid
sequenceDiagram
    autonumber
    participant Cron as Sidekiq-cron (hourly)
    participant Job as SlaBreachScanJob
    participant DB as ehs_app
    participant K as Kafka system.v1
    participant N as notifier

    Cron->>Job: enqueue
    Job->>DB: SELECT incidents WHERE state='submitted'<br/>AND created_at < triage_deadline_for(severity)
    DB-->>Job: rows
    loop for each row
        Job->>DB: INSERT outbox_events (SlaBreached)<br/>UPDATE incident SET sla_breached_at=NOW()
    end

    Note over DB,K: OutboxShipperJob ships within ~5s
    DB-->>K: SlaBreached events
    K->>N: fanout to admins + assigned investigators
```

## Triage windows

| Severity | Triage window |
|---|---|
| 1 (catastrophic), 2 | 4 hours |
| 3 | 24 hours |
| 4, 5 | 72 hours |

Configurable per-org in `admin/settings`.

## Why this matters for the narrative

EHS platforms exist to move organizations "from reactive to proactive safety"
(HSI Donesafe's own phrasing). A measurable, automated breach scan with audited
delivery is exactly the kind of "proactive" capability interviewers look for.
