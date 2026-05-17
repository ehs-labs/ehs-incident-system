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
