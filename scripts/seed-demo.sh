#!/usr/bin/env bash
# ============================================================================
# seed-demo.sh — seed the running stack with demo organization, users, and incidents
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Seeding demo data via 'rails db:seed:demo'..."
docker compose exec -T core-api bin/rails db:seed:demo
echo "==> Demo data seeded."
