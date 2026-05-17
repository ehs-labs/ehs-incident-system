# notifier

A small Sinatra app that consumes domain events from Kafka and fans them out to
**email**, **Telegram**, and **in-app** (WebSocket) channels.

## Why Sinatra?

This service has no domain model — it's a pipeline. A full Rails app would be
90% dead code. Sinatra also showcases Ruby beyond Rails.

## What's here

```
notifier/
├── app/
│   ├── consumers/         # Karafka consumers (one per topic)
│   ├── handlers/          # Event → notification mapping
│   ├── channels/          # Email / Telegram / In-app adapters
│   ├── models/            # Sequel models (users_mirror, delivery_log, ...)
│   └── web/               # Sinatra HTTP + WebSocket server
├── config/
│   ├── boot.rb            # DB, cipher, migration tripwire, eager-load
│   └── karafka.rb         # Karafka app + Avro deserializer
├── db/migrations/         # Sequel migrations (001, 002, 003, ...)
├── spec/                  # RSpec (+ karafka-testing)
├── Dockerfile             # Multi-stage, non-root, Falcon as PID-1
├── Gemfile
├── Rakefile               # db:create, db:migrate, db:drop
└── config.ru              # Rack entry point
```

## Running

```bash
bundle install
bundle exec rake db:create db:migrate
bundle exec karafka server                       # consumer process
bundle exec falcon serve --bind http://0.0.0.0:4000   # HTTP + WS process
```

Both processes are wired in `docker-compose.yml` as separate services in production-style deploys.

## Key architectural notes

- **Karafka** for Kafka consumers (consumer groups, retries, DLQ)
- **Avro + Karapace** — schemas resolved by ID via `avro-turf`
- **`users.v1` CDC mirror** — populated by `UsersConsumer`, PII fields decrypted via `ehs-envelope`
- **Idempotent delivery** — `delivery_log` has a unique key on `(event_id, user_id, channel)`
- **Falcon** — fiber-based async server, cheap multi-thousand WS connections
- **Pending-migration tripwire** — `config/boot.rb` aborts if Sequel migrations are stale
