# Migrations

Two schemas, two migration tools — both gated by the same defense:

| Service | Tool | Tracked in | Location |
|---|---|---|---|
| `core-api` | ActiveRecord migrations | `schema_migrations` | `core-api/db/migrate/` |
| `notifier` | Sequel migrations | `schema_info` | `notifier/db/migrations/` |

## Comparison with Liquibase / Mongock

| Liquibase / Mongock | ActiveRecord / Sequel |
|---|---|
| XML/YAML/SQL changelog | Ruby class per migration |
| `databaseChangeLog` table | `schema_migrations` (AR) / `schema_info` (Sequel) |
| `<rollback>` blocks | `down` method (or fully reversible `change`) |
| Preconditions | `if_not_exists`, `safety_assured`, custom Ruby guards |
| `validateOnMigrate` | Boot-time tripwire (below) |
| Run on app boot | Run as a K8s Job (pre-rollout) — never on app boot |

## Running migrations

```bash
# Local — core-api
cd core-api
bin/rails db:migrate                  # apply pending
bin/rails db:migrate:status           # what's applied vs pending
bin/rails db:rollback STEP=1          # undo last
bin/rails db:migrate VERSION=20260517000000   # to specific version

# Local — notifier
cd notifier
bundle exec rake db:migrate           # apply all
bundle exec rake "db:migrate[3]"      # to specific version (3)

# Docker
docker compose run --rm core-api bin/rails db:migrate
docker compose run --rm notifier bundle exec rake db:migrate

# K8s (run as a Job, not on app boot)
kubectl -n ehs apply -k k8s/overlays/local         # includes the migration Job
```

## Strong migrations (CI guard)

The `strong_migrations` gem fails CI on dangerous patterns:

- Adding a `NOT NULL` column without a default to a large table
- Removing a column without zero-downtime steps
- Adding an index non-concurrently
- Changing a column type that would lock the table

If you actually need one of these, mark it `safety_assured` with a comment explaining
the reasoning — that reasoning is your audit trail when CI complains.

## Boot-time tripwire

Each service refuses to start if migrations are pending. This catches the
failure mode of "deployed new code but the migration Job didn't run".

**core-api** (`config/initializers/check_migrations.rb`):

```ruby
if Rails.env.production? || ENV["STRICT_MIGRATION_CHECK"] == "true"
  ActiveRecord::Migration.check_all_pending!   # raises ActiveRecord::PendingMigrationError
end
```

**notifier** (`config/boot.rb`):

```ruby
unless Sequel::Migrator.is_current?(DB, "db/migrations")
  abort "Pending migrations detected."
end
```

This is the same idea as Flyway's `validateOnMigrate` or Liquibase's
`validateChangeSet` — refuse to serve traffic against a schema that doesn't
match the code.

## Deploy ordering in K8s

1. `kubectl apply` ConfigMap / Secret updates
2. `kubectl apply` `Job/db-migrate-*` — `kubectl wait --for=condition=Complete`
3. `kubectl apply` Deployments → rolling restart begins
4. Boot-time tripwire on the new pods double-checks; if Job somehow lied, pod crashes

If step 2 fails, step 3 never runs, old pods keep serving on the old schema.
