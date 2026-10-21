#!/usr/bin/env bash
# Full suite from a clean database. Invariants are proven against a REAL Postgres only:
# if Docker or the Supabase CLI is missing, this stops instead of substituting mocks.
set -euo pipefail
cd "$(dirname "$0")/.."

fail_env() {
  echo "ERROR: $1" >&2
  echo "Invariant tests require a real local Postgres (Supabase CLI + Docker). Refusing to run with mocks." >&2
  exit 2
}

command -v docker >/dev/null 2>&1 || fail_env "docker is not installed"
docker info >/dev/null 2>&1 || fail_env "the Docker daemon is not running (start Docker Desktop)"
command -v supabase >/dev/null 2>&1 || fail_env "the Supabase CLI is not installed (brew install supabase/tap/supabase)"
[ -d node_modules ] || npm install --no-audit --no-fund

if ! supabase status >/dev/null 2>&1; then
  echo "== starting local Supabase stack =="
  npm run --silent db:start
fi

echo "== 1/5 reset database: migrations + seed from scratch =="
supabase db reset

echo "== 2/5 pgTAP: schema/grants, rounding, ledgers, RLS isolation, audit, Phase 3 commands, geofence =="
supabase test db

echo "== 3/5 typecheck (root tests + every workspace) =="
npm run --silent typecheck

echo "== 4/5 node: unit + KYC contract, 50-vs-10 concurrency, commit-time invariants, end-to-end flows via Auth/PostgREST =="
npm run --silent test:node

echo "== 5/5 web production build =="
bash scripts/web-env.sh >/dev/null
NEXT_TELEMETRY_DISABLED=1 npm run --silent web:build

echo "== ALL SUITES PASSED =="
