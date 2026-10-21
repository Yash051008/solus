-- Structural guarantees: RLS everywhere, no client write grants, internal functions not callable
-- by clients, auth.uid() only behind the seam, audit attached to every business table.
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

select is(
  (select array_agg(tablename::text order by tablename) from pg_tables
   where schemaname = 'public' and not rowsecurity),
  null,
  'RLS is enabled on every table in public'
);

select is(
  (select array_agg(format('%s:%s:%s', grantee, table_name, privilege_type) order by 1)
   from information_schema.role_table_grants
   where table_schema = 'public' and grantee in ('anon', 'authenticated', 'public')
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER')),
  null,
  'anon/authenticated hold no write privilege on any public table'
);

select is(
  (select array_agg(format('%s:%s', grantee, table_name) order by 1)
   from information_schema.role_table_grants
   where table_schema = 'public' and grantee = 'anon'),
  null,
  'anon holds no privilege at all on public tables'
);

select is(
  (select array_agg(format('%s:%s.%s', grantee, table_schema, table_name) order by 1)
   from information_schema.role_table_grants
   where table_schema in ('audit', 'private') and grantee in ('anon', 'authenticated', 'service_role')),
  null,
  'no client or service role privilege on audit/private tables'
);

select is(
  (select array_agg(format('service_role:%s:%s', table_name, privilege_type) order by 1)
   from information_schema.role_table_grants
   where table_schema = 'public' and grantee = 'service_role'
     and table_name in ('stock_movements', 'stock_balances', 'journals', 'ledger_entries', 'account_balances')
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')),
  null,
  'service_role cannot write ledgers or projections directly'
);

select is(
  (select array_agg(p.oid::regprocedure::text order by 1)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('app', 'audit', 'private', 'public')
     and has_function_privilege('authenticated', p.oid, 'execute')
     and p.proname not in (
       'current_user_id', 'is_platform_admin', 'my_org_ids', 'my_org_ids_with_role', 'my_branch_ids',
       'visible_location_ids', 'visible_retailer_ids', 'visible_distributor_ids', 'visible_manufacturer_ids',
       'visible_user_ids', 'visible_account_ids', 'account_normal_side')),
  null,
  'authenticated can execute only the RLS helper functions (no ledger primitives)'
);

select is(
  (select array_agg(p.oid::regprocedure::text order by 1)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('app', 'audit', 'private', 'public')
     and p.prosrc ilike '%auth.uid%'
     and p.oid <> 'app.current_user_id()'::regprocedure),
  null,
  'auth.uid() appears in no function except app.current_user_id() (ADR-0004 seam)'
);

select is(
  (select array_agg(format('%s.%s', tablename, policyname) order by 1)
   from pg_policies
   where coalesce(qual, '') ilike '%auth.uid%' or coalesce(with_check, '') ilike '%auth.uid%'),
  null,
  'no RLS policy references auth.uid() directly'
);

select is(
  (select array_agg(t.tablename::text order by 1)
   from pg_tables t
   where t.schemaname = 'public'
     and t.tablename not in ('stock_balances', 'account_balances')
     and not exists (
       select 1 from pg_trigger tg
       where tg.tgrelid = format('public.%I', t.tablename)::regclass and tg.tgname = 'audit_log')),
  null,
  'every business table (all but the two projections) has the audit trigger'
);

select * from finish();
rollback;
