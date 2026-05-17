# C4 Level 3 — Notifier internals

```mermaid
flowchart LR
    subgraph notifier["notifier (Sinatra + Karafka + Falcon)"]
        direction TB

        subgraph consumers["Karafka consumers"]
            iC[IncidentsConsumer]
            caC[CorrectiveActionsConsumer]
            sC[SystemConsumer]
            uC[UsersConsumer<br/><i>CDC sink</i>]
        end

        subgraph handlers["Event handlers"]
            de[DomainEvent dispatcher]
            iN[IncidentNotifier]
        end

        subgraph channels["Channels"]
            email[EmailChannel]
            tg[TelegramChannel]
            inApp[InAppChannel]
        end

        subgraph web["HTTP / WS (Falcon)"]
            health[/healthz/]
            ws[/ws  WebSocket/]
            wsServer[WsServer<br/><i>per-user sessions</i>]
        end

        subgraph models["Sequel models"]
            mirror[(users_mirror)]
            log[(delivery_log)]
        end

        envelope[ehs-envelope<br/>AES-256-GCM]
    end

    kafkaIncidents[/Kafka<br/>incidents.v1<br/>corrective_actions.v1<br/>system.v1/] --> iC & caC & sC
    kafkaUsers[/Kafka<br/>users.v1 - CDC/] --> uC

    iC & caC & sC --> de --> iN
    uC --> envelope --> mirror

    iN --> mirror
    iN --> log
    iN --> email & tg & inApp
    inApp --> wsServer
    ws --> wsServer

    email --> smtp[(SMTP)]
    tg --> tgApi[(Telegram API)]
    wsServer --> browser[(Browser WS)]
```

## Why this shape

- **One consumer per topic** — Karafka's clean unit of work. Consumers do nothing but Avro-decode and hand off to the dispatcher.
- **Single dispatcher** — `Handlers::DomainEvent` is a tiny event-type → handler map. New event types land as one `register(...)` call plus one handler block.
- **Channels are pure adapters** — they take a `DeliveryLog` row and an enriched recipient (from `users_mirror`) and dispatch through their wire protocol. Add a new channel (Slack, SMS) without touching any handler.
- **`users.v1` CDC keeps `users_mirror` warm** — the rest of the service never calls back to `core-api` for identity, even after restarts. The `ehs-envelope` round trip happens here.
- **Falcon + WsServer** — fiber-based async, cheap multi-thousand WS sessions. `WsServer` keeps an in-process `user_id → Set<connection>` registry so `InAppChannel.deliver` can push without coordination.

## Idempotency model

```mermaid
sequenceDiagram
    autonumber
    participant Kafka
    participant Consumer
    participant Handler
    participant DLog as delivery_log
    participant Channel

    Kafka->>Consumer: event { event_id }
    Consumer->>Handler: dispatch
    Handler->>DLog: claim(event_id, user_id, channel)
    alt first claim
        DLog-->>Handler: new row (pending)
        Handler->>Channel: deliver
        Channel->>DLog: mark_sent! (or mark_failed!)
    else already sent
        DLog-->>Handler: nil (skip)
    end
```

The unique index on `(event_id, user_id, channel)` means duplicate Kafka deliveries (which happen — Karafka is at-least-once) never produce duplicate emails / Telegrams / in-app pushes.
