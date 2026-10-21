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

echo "== 1/4 reset database: migrations + seed from scratch =="
supabase db reset

echo "== 2/4 pgTAP: schema/grants, rounding, stock ledger, money ledger, RLS isolation, audit =="
supabase test db

echo "== 3/4 typecheck =="
npx tsc -p tsconfig.json

echo "== 4/4 node: 50-vs-10 concurrency, commit-time invariants, duplicate posting =="
node --test "tests/**/*.test.ts"

echo "== ALL SUITES PASSED =="
