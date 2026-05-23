# core-api

The Rails 8.1 API-only monolith — domain logic, auth, REST endpoints, outbox publisher.

## Quick reference

| Command | Purpose |
|---|---|
| `bin/rails db:create db:migrate` | Set up the database |
| `bin/rails db:seed:demo` | Load demo organization, users, incidents |
| `bin/rails server` | Boot on port 3000 |
| `bundle exec sidekiq -C config/sidekiq.yml` | Boot background workers |
| `bundle exec rspec` | Run the test suite |
| `bundle exec rake rswag:specs:swaggerize` | Regenerate `openapi.yaml` |
| `bundle exec rubocop` | Lint |
| `bundle exec brakeman` | Security scan |

## What's here

This directory will hold the standard Rails layout once the app is generated:

```
core-api/
├── app/
│   ├── controllers/api/v1/      # Versioned API controllers
│   ├── models/                  # ActiveRecord + AASM state machines
│   ├── policies/                # Pundit authorization policies
│   ├── serializers/             # JSON output shape
│   ├── services/                # PORO service objects (multi-step operations)
│   ├── jobs/                    # Sidekiq jobs (outbox shipper, scans, digests)
│   └── mailers/                 # ActionMailer
├── config/
│   ├── routes.rb                # API routes
│   ├── database.yml             # Two-tier DB config
│   ├── sidekiq.yml              # Queues + cron schedules
│   └── initializers/
│       ├── check_migrations.rb  # Boot-time tripwire
│       ├── cors.rb
│       ├── devise.rb
│       ├── kafka.rb             # rdkafka producer wiring
│       └── avro_registry.rb     # Karapace client
├── db/
│   ├── migrate/                 # ActiveRecord migrations
│   ├── seeds.rb                 # Minimum boot data
│   └── demo_seeds.rb            # Rich demo data
├── spec/                        # RSpec
├── Dockerfile                   # Multi-stage build, runs as non-root
└── Gemfile
```

## Generating the app

The scaffolded `Gemfile`, `Dockerfile`, `config/`, and `routes.rb` are committed.
To finish bootstrapping locally:

```bash
cd core-api
bundle install
bin/rails new . --api --database=postgresql --skip-bundle --skip-git --skip-test --skip-listen --skip-spring --force
bundle install
bundle exec rails g rspec:install
bundle exec rails g devise:install
# … and so on per the implementation plan
```

See [`docs/operations/local-development.md`](../docs/operations/local-development.md) for the full setup.

## Key architectural notes

- **API-only mode** — no view layer; the Vue SPA owns the UI
- **JWT auth** via `devise-jwt` with a denylist table; refresh tokens in httpOnly cookies
- **Pundit** policies per resource; tenant scoping enforced via `default_scope` + policy `Scope` classes
- **AASM** state machines on `Incident` and `CorrectiveAction`
- **PaperTrail** audit on `Incident` and `CorrectiveAction`
- **Outbox pattern** — `OutboxEvent` model + `OutboxShipperJob` ships to Kafka every 5s
- **Avro + Karapace** — schemas in `../schemas/events/v1/`, registered at boot, encoded via `avro-turf`
- **PII discipline** — only `users.v1` carries PII; encrypted via `ehs-envelope`
- **Boot-time migration tripwire** — refuses to start if any migration is pending in production
