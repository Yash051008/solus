# CLAUDE.md: Solus (B2B FMCG Distribution, Nigeria)

Production software, not a demo. Boring, provable designs over clever ones. **Never claim something works
without showing test output.** If a rule below conflicts with a request, say so and propose an alternative.
Do not bend it silently.

- Product spec: [docs/SPEC.md](docs/SPEC.md)
- Architecture: [docs/architecture/README.md](docs/architecture/README.md)
- Decisions: [docs/adr/README.md](docs/adr/README.md)
- Progress and scope map: [docs/PROGRESS.md](docs/PROGRESS.md)

## Core requirement
One shared inventory and money core serves **both** flows with provably accurate stock and payments:
- **PULL**: retailer orders → reserve at nearest warehouse that can fulfil → batch → pack → assign driver →
  deliver (e-POD + geotagged photo) → partial/missing/damaged reporting → payment.
- **PUSH**: agent requests stock → distributor approves → two-party OTP handover → geofenced sales
  (offline-capable) → return unsold → reconciliation `picked_up = sold + returned + damaged + variance`.
  A shipment cannot close while variance is unresolved.

**When correctness of stock or money conflicts with speed or convenience, correctness wins.**

## Hard rules (follow the reason, not just the letter)
1. **Inventory is an append-only `stock_movements` ledger.** Types: receipt, reserve, release,
   transfer_out, transfer_in, handover, sale, return, damage, adjustment. Quantities are never edited.
   Locations are polymorphic (`warehouse | agent | driver`, see [ADR-0003](docs/adr/0003-ledger-design.md)).
   The `stock_balances(location, sku → on_hand, reserved)` projection is updated **only** by a trigger in the
   same transaction as the ledger insert. Clients have no write grants on it, and it has
   `CHECK (on_hand >= 0 AND reserved >= 0 AND reserved <= on_hand)`. A test rebuilds it from the ledger and
   proves it matches. Ledger rows carry nullable `batch_id` and `expiry_date` (unused in MVP).
   *Why: push and pull touch the same stock, and only an immutable ledger can be audited and reconciled.*
2. **Money is double-entry `ledger_entries`.** Accounts include wallet, trade_credit, receivables,
   cash_in_transit, variance (full chart in [domain-model](docs/architecture/domain-model.md)). Every
   journal's entries sum to zero, enforced by a deferred constraint trigger. Balances are derived, and any
   projection follows the same conditions as rule 1. Every payment write has an idempotency key. Webhooks are
   signature-verified and replay-safe. *Why: providers retry webhooks and networks duplicate requests.*
3. **Stock reservation is one atomic Postgres function with row locking.** Required test: 50 concurrent
   orders vs 10 units → exactly 10 units sold, zero oversell.
4. **Offline sync sends EVENTS (client UUIDs), not state.** The server validates each event against the
   agent's carried stock and credit. Rejected events go to a review queue and are never silently dropped.
   Sync is idempotent. "Accept into variance" records a physically real sale, raises a pending variance
   against the agent and requires manager approval.
   *Why: reality and the ledger must be able to reconcile, or the ledger is wrong in week one.*
5. **OTPs** are hashed at rest, expire, are attempt-limited, and are bound to one
   handover/credit/reconciliation record and both parties.
6. **RLS on every table**, scoped by organisation + role. Test: distributor A's agent reads nothing of
   distributor B's. No client-side-only permission checks.
7. **Every external service** (KYC, payments/virtual accounts, ERP, SMS/OTP, maps) sits behind a TypeScript
   interface with a mock implementation and contract tests. Before writing an interface, read the provider's
   **current** docs. Cite URLs, never invent API shapes, and mark anything unreachable as "unverified".
8. **Full audit log** via DB triggers on all business tables. Audit rows are append-only (no UPDATE/DELETE
   grants, and a trigger rejects them).

## Write path
Clients **never** INSERT/UPDATE/DELETE business tables directly. Every mutation is an `app.*` command
function (plpgsql, `security definer`, `search_path = ''`) that checks permissions, validates, and writes
ledgers in one transaction. Clients get RLS-scoped `SELECT` only.

## Numeric rules
- **Money:** `bigint` kobo. No floats anywhere, and no `numeric` with decimals in app code. TS uses `bigint`
  or branded integer types, and strings when crossing JSON.
- **Stock:** integer **pieces**. Cartons exist only as a factor in `sku_uom`, applied at input/display edges.
- **IDs:** `uuid`. **Timestamps:** `timestamptz`, UTC.
- **Rounding:** only through `app.round_div(numerator, denominator, mode)` (default `half_even`), which is
  documented and tested. No other rounding anywhere.

## Portability rules (DB may move to Nigeria-hosted Postgres, see [ADR-0001](docs/adr/0001-hosting-and-data-residency.md))
- Business logic lives in Postgres functions and plain SQL migrations. It never lives in Edge Functions or
  client code.
- All TypeScript DB access goes through the thin repository layer (`packages/db`).
- **Never call `auth.uid()` directly.** Use `app.current_user_id()` (the one wrapper), written in policies as
  `(select app.current_user_id())`. See [ADR-0004](docs/adr/0004-auth-abstraction-and-portability.md).
- Edge Functions are thin adapters (webhook receivers, provider calls) with no business rules.
- Realtime is a notification layer, never the source of truth.

## Data protection (see [ADR-0002](docs/adr/0002-regulatory-findings-2026-10.md))
- The platform **never custodies funds**. The wallet is a ledger mirror of virtual accounts held at a
  licensed partner.
- Store KYC **status + provider reference + hash only**. Never store raw BVN/NIN, and never store
  biometrics or liveness selfies.
- No real payment transaction data may be stored offshore. Dev and staging use synthetic data only.

## Testing rules
- Invariant tests run against a **real Postgres** (Supabase CLI + Docker). Never use a mock.
- pgTAP for RLS and invariants. A Node `pg` Pool with 50 truly parallel connections for the concurrency test.
- Automated tests for: duplicate webhook, sync idempotency, journals sum to zero, balances rebuilt from the
  ledger.
- If Docker or the Supabase CLI is unavailable, **say so and stop.** Never substitute mocks and claim an
  invariant is proven.

## Repo layout (target; created from Phase 2)
```
apps/web            Next.js dashboards (all web roles)
apps/agent          Expo React Native agent app (SQLite + outbox)
packages/core       shared types, money/UoM helpers (no I/O)
packages/db         repository layer (only place TS touches the DB)
packages/integrations  provider interfaces + mocks + contract tests
supabase/migrations plain SQL migrations (schemas: app, audit, public)
supabase/tests      pgTAP tests
tests/concurrency   Node pg-Pool concurrency tests
docs/               spec, architecture, ADRs, progress
```

## Commands
| Purpose | Command |
|---|---|
| **Full suite from a clean DB** (reset + seed → pgTAP → typecheck all workspaces → Node unit/contract/concurrency/invariant/end-to-end tests → web production build) | `npm run test:all` |
| Start local stack (db, auth, rest only) | `npm run db:start` |
| Reset DB (migrations + seed) | `npm run db:reset` |
| pgTAP only | `npm run test:db` |
| Node DB tests only (needs a reset DB) | `npm run test:node` |
| Typecheck | `npm run typecheck` |
| Write `apps/web/.env.local` from the running stack | `npm run web:env` |
| Web dev server (http://localhost:3100; port 3000 is taken by Docker here) | `npm run dev --workspace @solus/web` |
| Regenerate DB types after a migration | `npm run db:types` |

`scripts/test-all.sh` exits with code 2 and does not run if Docker or the Supabase CLI is missing.
Local DB: `postgresql://postgres:postgres@127.0.0.1:54322/postgres` (override with `DATABASE_URL`).
Seeded users: `<handle>@solus.test`, password `SolusDev-2026!` (local only, handles listed in `supabase/seed.sql`).

## SQL conventions learned the hard way
- **Projection triggers: UPDATE first, INSERT if missing, retry on `unique_violation`.** Never use
  `INSERT … ON CONFLICT DO UPDATE` for delta upserts. Postgres evaluates CHECK constraints against the
  *proposed insert row* (the bare delta) before resolving the conflict, which rejects valid decrements.
- RLS array helpers: write `col = any((select app.fn())::uuid[])`. Without the cast, `any((select …))` is
  parsed as a subquery yielding `uuid[]` rows and fails.
- plpgsql compiles both branches of a `CASE`, so `case when tg_table_name = … then new.x else new.y end`
  fails on tables without `y`. Use `IF`.
- Postgres has no autonomous transactions: anything that must persist on a "failure" (OTP attempt counters)
  must return a failure result, not raise.
- Tests that need deferred constraint triggers to fire inside a rolled-back pgTAP transaction use
  `set constraints all immediate`.
- `now()` is fixed for the whole transaction. Never order "latest" rows by a timestamp alone: use an
  identity `seq` column.
- pgTAP helpers that look up ids must read snapshots taken as the owner (temp tables), not live tables.
  After `set role authenticated` the lookup is filtered by the caller's RLS.
- Integration tests must use run-unique fixture values: the stack isn't reset between `test:node` runs.

## API surface
- Commands live in schema `app`, exposed through PostgREST (`supabase/config.toml` `api.schemas`). Only
  functions with an explicit `EXECUTE` grant are callable. `supabase/tests/001_schema_grants.test.sql`
  holds the allowlist, so adding a client-callable function means adding it there deliberately.
- `auto_expose_new_tables = false`: nothing is exposed without an explicit grant. `service_role` holds
  **no table privileges**, only EXECUTE on adapter functions (currently `app.record_kyc_result`).
- TypeScript reaches the DB only through `packages/db` (`createRepository` for user-scoped calls,
  `createAdapterRepository` for server adapters).

Environment as of 2026-10-21: Node v26.4.0, npm 11.17.0, Docker 29.5.2 (running), Supabase CLI 2.121.0,
Postgres 17 (local image). No psql on the host: use `docker exec supabase_db_solus psql -U postgres`.

## Working method
Seven gated phases (see [PROGRESS.md](docs/PROGRESS.md)). At the end of each phase: run the full suite, show
the output, summarise what exists, list known gaps, update `docs/PROGRESS.md`, then **stop and wait for
"next"**. Keep files small and typed. Write real runnable code, never pseudocode.
