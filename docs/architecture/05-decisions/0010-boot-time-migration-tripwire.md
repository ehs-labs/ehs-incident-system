# ADR-0010: Boot-time pending-migration tripwire

- **Status:** Accepted
- **Date:** 2026-05-17

## Context

A common production failure mode: new code deployed, but the migration job
didn't run (CI bug, manual override, race). The new code starts against the
old schema and serves errors to users — or worse, silently corrupts data.

We can detect this at boot time, before serving traffic.

## Decision

- **core-api:** `ActiveRecord::Migration.check_all_pending!` in `config/initializers/check_migrations.rb`. Active in `production` and when `STRICT_MIGRATION_CHECK=true`.
- **notifier:** `Sequel::Migrator.is_current?(DB, "db/migrations")` in `config/boot.rb`.
- Both abort startup with a clear message if pending migrations exist.

## Consequences

**Wins**
- The same protection Flyway's `validateOnMigrate` provides — but built into the apps themselves
- K8s rolling update will treat the new pod as unhealthy and roll back automatically
- Defensive against ops mistakes

**Costs**
- Adds ~50 ms to boot time (one query)
- Requires careful handling in `rails console` (the initializer skips when running under Rails::Console)
