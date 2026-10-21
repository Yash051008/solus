#!/usr/bin/env bash
# Writes apps/agent/.env so a phone on the same Wi-Fi can reach the local Supabase stack.
set -euo pipefail
cd "$(dirname "$0")/.."
ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
[ -n "$ip" ] || { echo "Could not find this machine's LAN IP" >&2; exit 1; }
eval "$(supabase status -o env | grep -E '^ANON_KEY=')"
printf 'EXPO_PUBLIC_SUPABASE_URL=http://%s:54321\nEXPO_PUBLIC_SUPABASE_ANON_KEY=%s\n' "$ip" "$ANON_KEY" > apps/agent/.env
echo "wrote apps/agent/.env (Supabase at http://$ip:54321)"
