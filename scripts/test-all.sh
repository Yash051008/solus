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

echo "== 1/6 reset database: migrations + seed from scratch =="
supabase db reset

echo "== 2/6 pgTAP: schema/grants, rounding, ledgers, RLS isolation, audit, Phase 3 commands, geofence =="
supabase test db

echo "== 3/6 typecheck (root tests + every workspace) =="
npm run --silent typecheck

echo "== 4/6 node: unit + KYC contract, 50-vs-10 concurrency, commit-time invariants, end-to-end flows via Auth/PostgREST =="
npm run --silent test:node

echo "== 5/6 web production build =="
bash scripts/web-env.sh >/dev/null
NEXT_DIST_DIR=.next-build NEXT_TELEMETRY_DISABLED=1 npm run --silent web:build

echo "== 6/6 agent app (Expo): Metro bundle for Android =="
bash scripts/agent-env.sh >/dev/null
(cd apps/agent && CI=1 npx expo export --platform android --output-dir .expo-export-check >/dev/null && echo "agent bundle OK")

echo "== ALL SUITES PASSED =="
