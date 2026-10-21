-- Phase 6b: catalog-level hardening checks that keep holding as the schema grows.
begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

select is_empty($$
  select n.nspname || '.' || p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where p.prosecdef and n.nspname in ('app', 'private', 'public')
    and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c = 'search_path=""' or c = 'search_path=')
$$, 'every security-definer function pins an empty search_path');

select is_empty($$
  select c.conrelid::regclass::text || ' ' || c.conname from pg_constraint c join pg_namespace n on n.oid = c.connamespace
  where c.contype = 'f' and n.nspname in ('public', 'private')
    and not exists (select 1 from pg_index i where i.indrelid = c.conrelid
      and (i.indkey::int2[])[0:array_length(c.conkey, 1) - 1] @> c.conkey
      and c.conkey @> (i.indkey::int2[])[0:array_length(c.conkey, 1) - 1])
$$, 'every foreign key has a covering index');

select is_empty($$
  select c.oid::regclass::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'private') and c.relkind in ('r', 'p') and not c.relrowsecurity
$$, 'row level security is enabled on every table');

select is_empty($$
  select n.nspname || '.' || p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('app', 'private') and has_function_privilege('anon', p.oid, 'execute')
$$, 'anonymous users can execute nothing in app/private');

select is_empty($$
  select n.nspname || '.' || c.relname || ' ' || pr from pg_class c join pg_namespace n on n.oid = c.relnamespace,
    unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) pr
  where n.nspname = 'public' and c.relkind = 'r'
    and (has_table_privilege('authenticated', c.oid, pr) or has_table_privilege('anon', c.oid, pr))
$$, 'clients never write tables directly (commands only)');

select is_empty($$
  select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'private' and (has_table_privilege('authenticated', c.oid, 'SELECT') or has_table_privilege('anon', c.oid, 'SELECT'))
$$, 'private tables are unreadable by clients');

select * from finish();
rollback;
