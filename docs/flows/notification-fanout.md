# Flow — Notification fanout

How a single domain event becomes notifications across multiple channels for
multiple recipients, idempotently.

```mermaid
sequenceDiagram
    autonumber
    participant K as Kafka topic
    participant C as Karafka consumer
    participant D as DomainEvent dispatcher
    participant H as IncidentNotifier (handler)
    participant M as users_mirror
    participant L as delivery_log
    participant E as EmailChannel
    participant T as TelegramChannel
    participant W as InAppChannel → WsServer

    K->>C: event { event_id, event_type, recipient_user_ids: [u1, u2, u3], ... }
    C->>D: dispatch(event)
    D->>H: handler.call(event)

    H->>M: SELECT * WHERE user_id IN (u1, u2, u3)
    M-->>H: [u1{email, prefs}, u3{email, telegram, prefs}]<br/><i>u2 missing — dropped</i>

    loop for each recipient
        Note over H: check per-event-type prefs (email, telegram, in_app)
        H->>L: claim(event_id, user_id, channel)
        alt first claim
            L-->>H: new pending row
            par per channel
                H->>E: deliver
                E->>L: mark_sent!
            and
                H->>T: deliver (if chat_id present)
                T->>L: mark_sent!
            and
                H->>W: push to live sessions
                W->>L: mark_sent!
            end
        else already-sent (replay)
            L-->>H: nil — skip
        end
    end
```

## Key invariants

- **One row per `(event_id, user_id, channel)`** in `delivery_log` — unique index. Even if Karafka re-delivers, fanout is idempotent.
- **Failed deliveries get a state of `failed`** and the error message. Karafka's retry/DLQ takes over from there.
- **Missing recipients in the mirror are silently dropped** — this is the right behavior: a missing user typically means a soft-deleted account. The CDC ensures the mirror catches up eventually.
- **Per-channel preference check** is `prefs[event_type][channel] || defaults[channel]`. Defaults: email=on, telegram=off (opt-in), in-app=on.
