# Observability

## Logs

Every container logs JSON to stdout.

- core-api: `lograge` produces one line per request (method, path, status, duration, controller, action, user_id)
- notifier: `lograge-sql` for SQL queries; plain Ruby logger for Karafka
- All structured for parsing by Loki / ELK / Datadog / Cloudwatch

## Metrics

- core-api exposes `/metrics` via `prometheus_exporter` (RPM, latency histograms, Sidekiq queue depth)
- notifier exposes `/metrics` similarly
- K8s overlay has a `ServiceMonitor` stub for kube-prometheus-stack (commented out by default; uncomment if you install the operator)

## Tracing

`opentelemetry-rails` is wired in core-api; spans are emitted but not exported by default (no collector deployed). To enable:

```yaml
env:
  OTEL_EXPORTER_OTLP_ENDPOINT: "http://otel-collector:4318"
  OTEL_SERVICE_NAME: "core-api"
```

## What to watch

| Signal | Where | Alert when |
|---|---|---|
| `core-api` p99 latency | `/metrics` `http_request_duration_seconds` | > 1s for 5 min |
| Sidekiq dead queue | `/sidekiq` | > 0 |
| `outbox_events` with `published_at IS NULL` older than 60s | DB query / metric | > 100 |
| Karafka consumer lag | Karafka's own Prometheus metrics | > 1000 |
| `delivery_log` failed state | DB query / metric | rate > 5% |

## Cross-process notification bus

The notifier runs as two processes sharing one image: the Karafka consumer
writes `delivery_log` rows, and the Falcon web server holds the live WebSocket
sessions. Since they share no memory, the consumer cannot push to sessions
directly; instead, Postgres `NOTIFY` decouples the two JVM-like processes.

- Publisher: `Channels::InAppChannel.deliver` (runs in the Karafka container)
  emits `NOTIFY delivery_log_appended, '<json:{user_id, log}>'` after writing
  the row.
- Subscriber: `Notifier::Web::PgListener` (runs in the Falcon container) holds
  a dedicated Sequel connection and `LISTEN`s on the channel; each notify is
  re-pushed to matching `WsServer` sessions.
- Failure mode: the listener thread reconnects with 1s/5s/15s backoff. If a
  `NOTIFY` is dropped, the WS-reconnect replay (`DeliveryLog.recent_unread_for`)
  is the safety net — clients always see their inbox on the next reconnect.
- Kotlin/Spring analog: this is `ApplicationEventPublisher` across two JVMs,
  with Postgres acting as a lightweight broker. No extra infra needed.
