# Docker Compose details

## Service map

| Service | Image | Ports | Purpose |
|---|---|---|---|
| postgres   | postgres:16-alpine | 5432 | Two logical DBs: `ehs_app`, `ehs_notifier` |
| redis      | redis:7-alpine | 6379 | Sidekiq backing store |
| kafka      | bitnami/kafka:3.7 | 9092 | KRaft mode (no Zookeeper) |
| karapace   | ghcr.io/aiven/karapace | 8081 | Avro schema registry |
| kafka-ui   | provectuslabs/kafka-ui | 8080 | Topic inspector |
| minio      | minio/minio | 9000, 9001 | S3-compatible blob store |
| mailcatcher| dockage/mailcatcher | 1025, 1080 | SMTP sink + web UI |
| core-api   | local build | 3000 | Rails API |
| sidekiq    | local build (same image as core-api) | – | Background jobs |
| notifier   | local build | 4000 | Sinatra HTTP/WS + Karafka |
| frontend   | local build | 5173 | Vite dev server |

## Useful commands

```bash
docker compose up -d --wait       # full stack, wait for healthchecks
docker compose up -d postgres redis kafka karapace  # infra only
docker compose logs -f core-api   # tail logs
docker compose restart notifier
docker compose down               # stop everything
docker compose down -v            # stop + WIPE volumes (DB, Kafka, MinIO)
```

## Profiles

The default `docker-compose.yml` brings up everything. To run apps on host but
keep infra in compose, just `docker compose up -d postgres redis kafka karapace minio mailcatcher`.

## Dev overrides

`docker-compose.dev.yml` is auto-merged with `docker-compose.yml`. It:
- Mounts service source code (hot reload)
- Replaces commands with their dev variants (`vite dev`, `rails s` instead of `bundle exec puma`)
- Mounts persistent bundler / pnpm caches in named volumes
