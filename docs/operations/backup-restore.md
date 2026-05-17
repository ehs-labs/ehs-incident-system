# Backup & restore

## Backup posture (not implemented in MVP — documented only)

| Data | Tool | Cadence | Location |
|---|---|---|---|
| Postgres | `pg_dump` in CronJob | hourly + daily | S3 bucket (separate from app bucket) |
| Kafka topics | `kafka-mirror-maker2` to a backup cluster | continuous | secondary cluster in different region |
| MinIO / S3 attachments | Versioning + lifecycle rules | continuous | same bucket, separate version |
| ETCD (K8s state) | Managed cluster — provider-handled | — | — |

## pg_dump CronJob (sketch)

```yaml
apiVersion: batch/v1
kind: CronJob
metadata: { name: pg-backup, namespace: ehs }
spec:
  schedule: "0 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: dumper
            image: postgres:16-alpine
            command: ["sh", "-c"]
            args:
            - |
              pg_dump "$DATABASE_URL_APP" | gzip > /tmp/ehs_app.sql.gz
              pg_dump "$DATABASE_URL_NOTIFIER" | gzip > /tmp/ehs_notifier.sql.gz
              # Upload to S3 — example:
              # aws s3 cp /tmp/ehs_app.sql.gz s3://backups/...
```

## Restore drill

A backup is a backup only if you've practiced restoring from it. Documented restore procedure:

1. Spin up a scratch Postgres pod
2. `gunzip ehs_app.sql.gz | psql ...`
3. Run `core-api`'s migrations (idempotent — should be no-op)
4. Smoke test via `core-api` pointed at the scratch DB
5. Verify row counts match: incidents, corrective_actions, users
