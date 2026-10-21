# ADR-0004: Auth abstraction and portability seams
- Status: Accepted
- Date: 2026-10-21
- Related: [ADR-0001](0001-hosting-and-data-residency.md)

## Context
Production may move to a Nigeria-hosted Postgres, possibly without Supabase Auth (ADR-0001 option C).
Supabase guidance writes `auth.uid()` straight into policies, which would scatter the auth source across every
policy and function.

## Decision
1. **One identity seam:** `app.current_user_id() returns uuid` is the only object that calls `auth.uid()`.
   ```sql
   -- Phase 2 migration (shape fixed here; implementation may change in exactly one place)
   create function app.current_user_id() returns uuid
     language sql stable security definer set search_path = ''
     as $$ select auth.uid() $$;
   ```
   On plain Postgres it becomes e.g. `current_setting('app.user_id', true)::uuid`, set per request by the
   API layer from a verified JWT. A pgTAP test greps `pg_policies` and `pg_proc` definitions and **fails if
   `auth.uid` appears anywhere except this function**.
2. **Policies call it wrapped in a sub-select**, `(select app.current_user_id())`, so Postgres evaluates it
   once per statement as an initPlan instead of per row. That follows Supabase's RLS performance guidance,
   which also says to index every policy column and to use `security definer` helpers with an empty
   `search_path` for cross-table checks
   ([RLS docs](https://supabase.com/docs/guides/database/postgres/row-level-security), read 2026-10-21).
3. **Role/org helpers** (`app.current_org_ids()`, `app.has_role()`, `app.current_branch_ids()`,
   `app.is_platform_admin()`) are `security definer`, `stable`, `search_path = ''`, fully schema-qualified,
   and built only on `app.current_user_id()`.
4. **Repository layer** (`packages/db`): the only TypeScript that touches the database. It exposes typed
   functions (`orders.place(...)`, `stock.balances(...)`) backed by supabase-js today. The interface hides
   the client so it can switch to a plain HTTP/PostgREST or `pg` implementation. UI code never imports
   supabase-js directly (lint rule, Phase 2).
5. **Edge Functions** contain no business rules. They verify, translate, and call one `app.*` function.
   They must run unchanged on another Deno/Node host.
6. **Realtime** is optional infrastructure. Clients subscribe to `domain_events` inserts as an
   invalidation signal and refetch through the repository layer.

## Consequences
- Moving auth providers means one function change plus JWT verification in the API layer, re-proven by the
  RLS suite.
- Slight indirection cost per statement (one initPlan), measured in Phase 2.
- Developers must not copy Supabase snippets that use `auth.uid()` verbatim. The grep test enforces this.
