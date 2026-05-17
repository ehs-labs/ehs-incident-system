#!/usr/bin/env bash
# ============================================================================
# bootstrap.sh — bring up the full local stack and seed demo data
#
# Idempotent: safe to run repeatedly. Detects whether infra is already up.
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
RESET=$'\033[0m'

log()  { printf "${GREEN}==> %s${RESET}\n" "$*"; }
warn() { printf "${YELLOW}!! %s${RESET}\n" "$*"; }
die()  { printf "${RED}ERROR: %s${RESET}\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
command -v docker >/dev/null  || die "Docker is required"
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required"

if [[ ! -f .env ]]; then
  log ".env not found — copying from .env.example"
  cp .env.example .env
  warn "Edit .env to set real secrets (JWT_SECRET, FIELD_CIPHER_KEY, …) before production use"
fi

# ---------------------------------------------------------------------------
# Bring up infrastructure first (so we can verify health before apps boot)
# ---------------------------------------------------------------------------
log "Starting infrastructure (postgres, redis, kafka, karapace, minio, mailcatcher)..."
docker compose up -d --wait postgres redis kafka karapace kafka-ui minio mailcatcher

log "Ensuring Kafka topics exist..."
for topic in incidents.v1 corrective_actions.v1 users.v1 system.v1; do
  docker compose exec -T kafka kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --create --if-not-exists \
    --topic "$topic" --partitions 3 --replication-factor 1 >/dev/null 2>&1 \
    && log "  topic ready: $topic" \
    || warn "  topic creation failed: $topic (it may already exist)"
done

log "Ensuring MinIO bucket exists..."
docker compose up minio-init

# ---------------------------------------------------------------------------
# Register Avro schemas with Karapace
# ---------------------------------------------------------------------------
log "Registering Avro schemas..."
if [[ -d schemas/events/v1 ]] && compgen -G "schemas/events/v1/*.avsc" >/dev/null; then
  for schema in schemas/events/v1/*.avsc; do
    # Subject == record name (PascalCase) — matches Confluent convention for
    # `<schema_name>-value` subjects used by avro-turf in record-name mode.
    subject="$(basename "$schema" .avsc)-value"
    payload=$(jq -Rs --arg t AVRO '{schema: ., schemaType: $t}' < "$schema")
    curl -fsS -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
      -d "$payload" \
      "http://localhost:8081/subjects/$subject/versions" >/dev/null \
      && log "  registered: $subject" \
      || warn "  schema registration failed: $subject (may already exist with incompatible change)"
  done
else
  warn "No .avsc files in schemas/events/v1/ yet — skipping schema registration"
fi

# ---------------------------------------------------------------------------
# Build app images & run migrations
# ---------------------------------------------------------------------------
log "Building application images..."
docker compose build core-api notifier frontend

log "Running migrations..."
docker compose run --rm core-api bin/rails db:create db:migrate || warn "core-api migrations may already be applied"
docker compose run --rm notifier bundle exec rake db:create db:migrate || warn "notifier migrations may already be applied"

# ---------------------------------------------------------------------------
# Bring up apps
# ---------------------------------------------------------------------------
log "Starting applications..."
docker compose up -d --wait core-api sidekiq notifier frontend
# Karafka consumer process — same image as notifier, started after notifier
# is healthy so it picks up the freshly-built image. `--wait` is skipped here
# because Karafka has no HTTP healthcheck.
docker compose up -d notifier-karafka

# ---------------------------------------------------------------------------
# Seed demo data
# ---------------------------------------------------------------------------
if [[ "${SKIP_SEED:-}" != "true" ]]; then
  log "Seeding demo data..."
  "$ROOT/scripts/seed-demo.sh"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
cat <<EOF

${GREEN}✓ EHS Incident System is up.${RESET}

  Web app:           http://localhost:5173
  MailCatcher:       http://localhost:1080
  Kafka UI:          http://localhost:8080
  Karapace:          http://localhost:8081
  Sidekiq dashboard: http://localhost:3000/sidekiq
  MinIO console:     http://localhost:9001  (minioadmin / minioadmin)

  Demo accounts (password: password):
    admin@acme.demo        — Admin
    investigator@acme.demo — Investigator
    worker@acme.demo       — Worker

  Or sign up fresh at http://localhost:5173/signup

  Stop the stack: ${YELLOW}docker compose down${RESET}
  Stop and wipe data: ${YELLOW}docker compose down -v${RESET}
EOF
