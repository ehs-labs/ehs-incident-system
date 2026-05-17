# Flow — Triage and assign

```mermaid
sequenceDiagram
    autonumber
    actor Inv as Investigator
    participant SPA as Vue SPA
    participant Api as core-api
    participant DB as ehs_app
    participant K as Kafka (incidents.v1 + corrective_actions.v1)
    participant N as notifier

    Inv->>SPA: Open incident; click "Triage"
    SPA->>Api: POST /incidents/:id/transitions {event:"triage", assignee_id, severity}
    Api->>DB: state=investigating; assignee_id set; outbox: IncidentAssigned
    Api-->>SPA: 200 updated

    Inv->>SPA: Add corrective actions (title, owner, due_date)
    SPA->>Api: POST /incidents/:id/corrective_actions × N
    Api->>DB: INSERT corrective_actions; outbox: CorrectiveActionAssigned × N

    Inv->>SPA: Click "Assigned" (transition)
    SPA->>Api: POST /incidents/:id/transitions {event:"actions_assigned"}
    Api->>DB: state=pending_closure

    Note over K,N: Outbox shipper → Kafka → notifier → channels (per other flow doc)
```

Subsequent worker action completion → `verify` transition → close is in the [incident-submission](incident-submission.md) flow generalized — same outbox → Kafka → fanout shape.
