# Local development

## Prerequisites

- Docker Desktop ≥ 4.30 (includes Compose v2)
- Ruby 3.3 (managed via `rbenv` / `asdf` / `mise`) — only if you want to run apps outside Docker
- Node ≥ 20 + pnpm ≥ 9 — same caveat
- `jq` and `curl` for the bootstrap script
- ~6 GB free RAM for the full compose stack

## Quickstart

```bash
git clone https://github.com/ehs-labs/ehs-incident-system
cd ehs-incident-system
cp .env.example .env       # adjust JWT_SECRET, FIELD_CIPHER_KEY for non-trivial use
./scripts/bootstrap.sh
```

Open `http://localhost:5173`. Demo accounts and other URLs are printed at the end of the script.

## Email confirmation in dev

Devise sends a confirmation email after signup. The SMTP target is **MailCatcher** (in the compose stack):

1. Sign up at `http://localhost:5173/signup`
2. Open MailCatcher at `http://localhost:1080`
3. Click the confirmation link
4. Log in

Nothing actually leaves your machine.

## Running services outside Docker

Sometimes you want to attach a debugger or get faster reloads on the host:

```bash
# Bring up just infra
docker compose up -d postgres redis kafka karapace minio mailcatcher

# Run core-api on host
cd core-api
bundle install
bin/rails db:create db:migrate db:seed:demo
bin/rails server

# Run sidekiq on host
bundle exec sidekiq -C config/sidekiq.yml

# Run notifier on host
cd ../notifier
bundle install
bundle exec rake db:create db:migrate
bundle exec karafka server &
bundle exec falcon serve --bind http://0.0.0.0:4000

# Run frontend on host
cd ../frontend
pnpm install
pnpm dev
```

Environment variables: copy `.env` to `core-api/.env`, `notifier/.env`, `frontend/.env` — `dotenv-rails` and `dotenv` pick them up automatically.

## Common issues

| Symptom | Likely cause | Fix |
|---|---|---|
| `bootstrap.sh` hangs at "Waiting for Kafka" | First Kafka boot is slow (KRaft init) | Wait ~60s; if longer, `docker compose logs kafka` |
| Karapace returns 500 on schema register | Kafka not ready | Re-run `./scripts/bootstrap.sh` (idempotent) |
| Web app shows blank page | Frontend container not up; check `docker compose ps frontend` | `docker compose logs frontend` |
| `bundle install` fails on `rdkafka` | Missing librdkafka headers | `brew install librdkafka` (macOS) |
| MailCatcher shows no messages | Apps pointing at wrong SMTP host | Verify `SMTP_HOST=mailcatcher` in `.env` |

More in [troubleshooting.md](troubleshooting.md).
