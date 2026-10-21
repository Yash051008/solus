#!/usr/bin/env bash
# Writes apps/web/.env.local from the running local Supabase stack. Keeps an existing KYC pepper.
set -euo pipefail
cd "$(dirname "$0")/.."
out=apps/web/.env.local
eval "$(supabase status -o env | grep -E '^(API_URL|ANON_KEY|SERVICE_ROLE_KEY)=')"
pepper=$(grep -E '^KYC_ID_PEPPER=' "$out" 2>/dev/null | cut -d= -f2- || true)
[ -n "$pepper" ] || pepper=$(node -e 'console.log(require("node:crypto").randomBytes(32).toString("hex"))')
cat > "$out" <<EOF
NEXT_PUBLIC_SUPABASE_URL=$API_URL
NEXT_PUBLIC_SUPABASE_ANON_KEY=$ANON_KEY
SUPABASE_SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
KYC_ID_PEPPER=$pepper
KYC_PROVIDER=mock
EOF
echo "wrote $out"
