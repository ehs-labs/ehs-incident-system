#!/usr/bin/env bash
# ============================================================================
# postgres-init.sh — create the secondary `ehs_notifier` database alongside
# the primary `ehs_app` that POSTGRES_DB creates.
#
# Mounted into /docker-entrypoint-initdb.d so it runs once on first start.
# ============================================================================
set -euo pipefail

if [[ -z "${POSTGRES_MULTIPLE_DATABASES:-}" ]]; then
  exit 0
fi

IFS=',' read -ra DBS <<< "$POSTGRES_MULTIPLE_DATABASES"
for db in "${DBS[@]}"; do
  db_trimmed="$(echo "$db" | xargs)"
  if [[ "$db_trimmed" == "$POSTGRES_DB" ]]; then
    continue  # already created by entrypoint
  fi
  echo "==> Creating database: $db_trimmed"
  # -d postgres → connect to the always-present `postgres` DB. Without it,
  # psql defaults to a DB named after the user (which may not exist).
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -d postgres <<-SQL
    SELECT 'CREATE DATABASE $db_trimmed'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$db_trimmed')\gexec
SQL
done
