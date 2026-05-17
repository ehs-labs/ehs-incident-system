# Flow — Incident submission

A worker submits a new incident. The state transition emits an event via the
outbox, which is shipped to Kafka and consumed by the notifier, which fans out
to email, Telegram, and in-app channels.

```mermaid
sequenceDiagram
    autonumber
    actor Worker
    participant SPA as Vue SPA
    participant Api as core-api
    participant DB as ehs_app
    participant SQ as Sidekiq
    participant K as Kafka (incidents.v1)
    participant N as notifier (Karafka)
    participant Mail as MailCatcher (SMTP)
    participant TG as Telegram API
    participant WS as Notifier WS server

    Worker->>SPA: Fill incident form + attach photos
    SPA->>Api: POST /api/v1/incidents (multipart)
    Api->>DB: INSERT incident (state=draft)
    SPA->>Api: POST /api/v1/incidents/:id/transitions { event: "submit" }
    Api->>DB: BEGIN<br/>UPDATE incident SET state=submitted<br/>INSERT outbox_events row (IncidentSubmitted)<br/>COMMIT
    Api-->>SPA: 200 (updated resource)

    Note over SQ: OutboxShipperJob (cron */5s)
    SQ->>DB: SELECT * FROM outbox_events WHERE published_at IS NULL
    SQ->>K: produce IncidentSubmitted (Avro)
    SQ->>DB: UPDATE outbox_events SET published_at=NOW()

    K->>N: deliver IncidentSubmitted
    N->>N: dispatch → IncidentNotifier
    N->>N: resolve recipient_user_ids via users_mirror
    N->>N: claim delivery_log row (event_id × user × channel)

    par
        N->>Mail: send email
    and
        N->>TG: send message (if user opted in)
    and
        N->>WS: push to active sessions (Pinia store updates → bell badge)
    end

    N->>DB: UPDATE delivery_log SET state="sent", sent_at=NOW()
```

## What can fail and how it recovers

| Failure point | Recovery |
|---|---|
| DB commits but app crashes before Sidekiq triggers | OutboxShipper runs every 5s — next tick picks up the row |
| Kafka produce fails | Outbox row stays `published_at: null` — retried next tick |
| Notifier consumer crashes mid-message | Karafka does not commit offset — re-delivered on restart; `delivery_log` unique index deduplicates |
| Email send fails (SMTP error) | `delivery_log.state = "failed"`, error captured; Karafka retries per its retry/DLQ config |
| Telegram unreachable | Same as email |
| All WS sessions disconnected | In-app notification is persisted to `delivery_log`; next WS connect replays last 20 unread |
