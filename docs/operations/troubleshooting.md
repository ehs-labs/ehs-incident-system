# Troubleshooting

## Bootstrap script hangs / fails

| Stage | Likely cause | Fix |
|---|---|---|
| Postgres healthcheck | Old volume with incompatible schema | `docker compose down -v` and re-run |
| Kafka healthcheck | First KRaft init can take 60s+ | Wait. If still failing: `docker compose logs kafka` |
| Karapace healthcheck | Kafka not yet ready | Re-run `bootstrap.sh` (idempotent) |
| Image build | Out of disk | `docker system prune -af --volumes` (DESTRUCTIVE) |
| Avro registration | Schema file syntactically broken | `jq . schemas/events/v1/*.avsc` to validate JSON |

## Notifier won't decrypt PII

Symptom: `Ehs::Envelope::UnknownKeyVersion` or `MalformedCiphertext` in notifier logs.

Diagnose:
1. `kubectl -n ehs exec deploy/notifier -- env | grep FIELD_CIPHER` — is the key mounted?
2. Does it match what core-api uses? `kubectl -n ehs exec deploy/core-api -- env | grep FIELD_CIPHER`
3. If you rotated the key but didn't follow the dual-decrypt procedure, you'll see this. Re-mount the previous key version temporarily.

## WebSocket disconnects in dev

The default development environment uses HTTP-not-HTTPS, so we use `ws://` not `wss://`. If you see TLS errors:
- Verify `VITE_WS_URL` is `ws://localhost:4000/ws` (not `wss://`)
- Restart the frontend (`docker compose restart frontend`)

## "Pending migrations" on boot

This is the tripwire firing — it's working as intended. Run migrations:

```bash
docker compose run --rm core-api bin/rails db:migrate
docker compose run --rm notifier bundle exec rake db:migrate
```

## Outbox events not shipping

1. Check Sidekiq is running: `docker compose ps sidekiq`
2. Check `OutboxShipperJob` is scheduled: open `http://localhost:3000/sidekiq/cron`
3. Look for errors in `outbox_events` rows: `published_at IS NULL` rows older than a minute usually indicate Kafka or Karapace is unreachable
