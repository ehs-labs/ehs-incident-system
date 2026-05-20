#!/usr/bin/env bash
# ============================================================================
# dev-jwt.sh — print a JWT for a demo user against the local core-api.
#
# Usage:
#   scripts/dev-jwt.sh [admin|investigator|worker]   # default: admin
#   scripts/dev-jwt.sh admin | pbcopy                # straight to clipboard
#
# Requires the local stack to be up (docker compose up) and demo seeds loaded
# (scripts/seed-demo.sh). Credentials live in core-api/db/demo_seeds.rb.
# ============================================================================
set -euo pipefail

ROLE="${1:-admin}"
API="${API_URL:-http://localhost:3000}"

case "$ROLE" in
  admin)        EMAIL="admin@acme.demo" ;;
  investigator) EMAIL="investigator@acme.demo" ;;
  worker)       EMAIL="worker@acme.demo" ;;
  *) echo "ERROR: role must be one of admin|investigator|worker (got '$ROLE')" >&2; exit 1 ;;
esac

TOKEN="$(curl -fsS -X POST "$API/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"user\":{\"email\":\"$EMAIL\",\"password\":\"password\"}}" \
  | sed -nE 's/.*"access_token":"([^"]+)".*/\1/p')"

if [[ -z "$TOKEN" ]]; then
  echo "ERROR: login succeeded but no access_token in response" >&2
  exit 1
fi

printf '%s\n' "$TOKEN"
