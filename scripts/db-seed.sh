#!/usr/bin/env bash
# Runs supabase/seed.sql against the database in $DATABASE_URL.
#
# Seeding must bypass RLS -- the publishable key has no write policies, by
# design -- so this connects directly to Postgres rather than through the API.
#
# Uses a local psql if you have one, otherwise borrows psql from a throwaway
# Docker container so there's nothing extra to install.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env.local ] && set -a && . ./.env.local && set +a

if [ -z "${DATABASE_URL:-}" ]; then
  cat >&2 <<'MSG'
DATABASE_URL is not set.

Supabase dashboard -> Connect -> Session pooler -> copy the URI, then add it to
.env.local (which is gitignored):

  DATABASE_URL=postgresql://postgres.<ref>:<password>@<host>:5432/postgres

It contains your database password, so it never gets committed.
MSG
  exit 1
fi

if command -v psql >/dev/null 2>&1; then
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/seed.sql
else
  echo "no local psql; using docker" >&2
  docker run --rm -i postgres:16-alpine \
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f - < supabase/seed.sql
fi

echo "Seeded. 6 recipes, 30 ingredients."
