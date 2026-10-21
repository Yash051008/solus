-- Hard rule 8: every business-table change is audited with the acting user; the audit log is append-only.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

select set_config('request.jwt.claims',
  json_build_object('sub', (select id from auth.users where email = 'lp.admin@solus.test'))::text, true);

create temp table marker as select coalesce(max(id), 0) as last_id from audit.audit_log;

insert into public.branches (org_id, name)
select id, 'Audit Test Branch' from public.organisations where slug = 'lagos-prime';
update public.branches set name = 'Audit Test Branch Renamed' where name = 'Audit Test Branch';

select results_eq(
  $$ select op, actor_user_id from audit.audit_log
     where table_name = 'public.branches' and id > (select last_id from marker) order by id $$,
  $$ values ('INSERT'::text, (select id from auth.users where email = 'lp.admin@solus.test')),
            ('UPDATE'::text, (select id from auth.users where email = 'lp.admin@solus.test')) $$,
  'insert and update on a business table are audited with the acting user');

select is(
  (select old_row ->> 'name' || ' -> ' || (new_row ->> 'name') from audit.audit_log
   where table_name = 'public.branches' and op = 'UPDATE' and id > (select last_id from marker)),
  'Audit Test Branch -> Audit Test Branch Renamed',
  'the update records both the old and new row');

select lives_ok($$
  select app.post_stock_movement(gen_random_uuid(), 'receipt', sl.id, s.id, 12, null, null, null, 'audit test')
  from public.stock_locations sl join public.warehouses w on w.id = sl.warehouse_id, public.skus s
  where w.name = 'Lekki Depot' and s.code = 'HOM-BLC-1L' $$, 'a ledger write succeeds');
select is(
  (select count(*)::int from audit.audit_log
   where table_name = 'public.stock_movements' and id > (select last_id from marker)
     and new_row ->> 'reason' = 'audit test'),
  1, 'ledger rows are audited too');
select is(
  (select count(*)::int from audit.audit_log
   where table_name in ('public.stock_balances', 'public.account_balances')),
  0, 'projections are not audited (they are derived from audited ledgers)');

select throws_ok($$ update audit.audit_log set actor_user_id = null $$, 'SOL06', null,
                 'audit_log: UPDATE rejected even for the owner');
select throws_ok($$ delete from audit.audit_log $$, 'SOL06', null, 'audit_log: DELETE rejected even for the owner');
select throws_ok($$ truncate audit.audit_log $$, 'SOL06', null, 'audit_log: TRUNCATE rejected even for the owner');

select * from finish();
rollback;
