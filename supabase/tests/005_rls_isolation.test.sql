-- Hard rule 6: tenant isolation through RLS, evaluated as real authenticated users.
-- Every user of distributor A (lagos-prime), including its retailers, must read ZERO rows owned by
-- distributor B (abuja-central), in EVERY table. Plus positive scoping checks per role.
begin;
create extension if not exists pgtap with schema extensions;
select plan(175);

create function pg_temp.login(p_handle text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', (select id from auth.users where email = p_handle || '@solus.test'),
                      'role', 'authenticated')::text, true);
end;
$$;

-- Fixture: one order for each distributor, so orders/order_lines are non-trivially tested.
insert into public.orders (id, distributor_org_id, retailer_org_id)
select '33333333-3333-4333-8333-333333333333', cr.distributor_org_id, cr.retailer_org_id
from public.customer_relationships cr join public.organisations r on r.id = cr.retailer_org_id
where r.slug = 'retailer-13';
insert into public.order_lines (order_id, sku_id, uom_code, uom_qty, uom_price_kobo)
select '33333333-3333-4333-8333-333333333333', id, 'piece', 5, 25000 from public.skus where code = 'NDL-CHK-70G';
insert into public.orders (id, distributor_org_id, retailer_org_id)
select '44444444-4444-4444-8444-444444444444', cr.distributor_org_id, cr.retailer_org_id
from public.customer_relationships cr join public.organisations r on r.id = cr.retailer_org_id
where r.slug = 'retailer-01';
insert into public.order_lines (order_id, sku_id, uom_code, uom_qty, uom_price_kobo)
select '44444444-4444-4444-8444-444444444444', id, 'piece', 5, 25000 from public.skus where code = 'NDL-CHK-70G';

-- Fixture: a pending join request to B, and a KYC check for a B retailer.
insert into public.join_requests (user_id, org_id, requested_role)
select u.id, o.id, 'driver' from auth.users u, public.organisations o
where u.email = 'ac.agent1@solus.test' and o.slug = 'abuja-central';
insert into public.kyc_checks (org_id, subject_user_id, id_type, outcome, provider, provider_ref, id_hash)
select m.org_id, m.user_id, 'BVN', 'exact_match', 'mock', 'fixture-ref-13', repeat('a', 64)
from public.memberships m join public.organisations o on o.id = m.org_id where o.slug = 'retailer-13';

-- How to key a row of each table, and which rows belong to distributor B (computed as owner).
create temp table table_keys (tbl text primary key, key_expr text not null);
insert into table_keys values
  ('organisations', 'x.id::text'), ('branches', 'x.id::text'), ('territories', 'x.id::text'),
  ('warehouses', 'x.id::text'), ('profiles', 'x.user_id::text'), ('memberships', 'x.id::text'),
  ('customer_relationships', 'x.id::text'),
  ('supply_relationships', 'x.manufacturer_org_id::text || '':'' || x.distributor_org_id::text'),
  ('brands', 'x.id::text'), ('skus', 'x.id::text'), ('sku_uom', 'x.sku_id::text || '':'' || x.uom_code'),
  ('price_lists', 'x.id::text'),
  ('price_list_items', 'x.price_list_id::text || '':'' || x.sku_id::text || '':'' || x.uom_code'),
  ('stock_locations', 'x.id::text'), ('stock_movements', 'x.id::text'),
  ('stock_balances', 'x.location_id::text || '':'' || x.sku_id::text'),
  ('orders', 'x.id::text'), ('order_lines', 'x.id::text'),
  ('accounts', 'x.id::text'), ('journals', 'x.id::text'), ('ledger_entries', 'x.id::text'),
  ('account_balances', 'x.account_id::text'),
  ('join_requests', 'x.id::text'), ('kyc_checks', 'x.id::text');

select is(
  (select array_agg(tablename::text order by 1) from pg_tables
   where schemaname = 'public' and tablename not in (select tbl from table_keys)),
  null, 'isolation test covers every table in public');

create temp table b_owned (tbl text, id text);
with b as (select id from public.organisations where slug = 'abuja-central'),
     b_retailers as (select retailer_org_id as id from public.customer_relationships where distributor_org_id = (select id from b)),
     b_orgs as (select id from b union select id from b_retailers),
     b_users as (select user_id from public.memberships where org_id in (select id from b_orgs)),
     b_accounts as (select id from public.accounts
                    where book_org_id = (select id from b) or holder_org_id in (select id from b_orgs))
insert into b_owned
          select 'organisations', id::text from b_orgs
union all select 'branches', id::text from public.branches where org_id = (select id from b)
union all select 'territories', id::text from public.territories where org_id = (select id from b)
union all select 'warehouses', id::text from public.warehouses where org_id = (select id from b)
union all select 'profiles', user_id::text from b_users
union all select 'memberships', id::text from public.memberships where org_id in (select id from b_orgs)
union all select 'customer_relationships', id::text from public.customer_relationships where distributor_org_id = (select id from b)
union all select 'supply_relationships', manufacturer_org_id::text || ':' || distributor_org_id::text
          from public.supply_relationships where distributor_org_id = (select id from b)
union all select 'price_lists', id::text from public.price_lists where distributor_org_id = (select id from b)
union all select 'price_list_items', i.price_list_id::text || ':' || i.sku_id::text || ':' || i.uom_code
          from public.price_list_items i join public.price_lists pl on pl.id = i.price_list_id
          where pl.distributor_org_id = (select id from b)
union all select 'stock_locations', id::text from public.stock_locations where org_id = (select id from b)
union all select 'stock_movements', id::text from public.stock_movements where org_id = (select id from b)
union all select 'stock_balances', location_id::text || ':' || sku_id::text from public.stock_balances where org_id = (select id from b)
union all select 'orders', id::text from public.orders where distributor_org_id = (select id from b)
union all select 'order_lines', l.id::text from public.order_lines l join public.orders o on o.id = l.order_id
          where o.distributor_org_id = (select id from b)
union all select 'accounts', id::text from b_accounts
union all select 'journals', distinct_j.journal_id::text
          from (select distinct journal_id from public.ledger_entries where account_id in (select id from b_accounts)) distinct_j
union all select 'ledger_entries', id::text from public.ledger_entries where account_id in (select id from b_accounts)
union all select 'account_balances', account_id::text from public.account_balances where account_id in (select id from b_accounts)
union all select 'join_requests', id::text from public.join_requests where org_id = (select id from b)
union all select 'kyc_checks', id::text from public.kyc_checks where org_id in (select id from b_orgs);

select is(
  (select array_agg(k.tbl order by 1) from table_keys k
   where k.tbl not in ('brands', 'skus', 'sku_uom')            -- shared manufacturer catalogue
     and not exists (select 1 from b_owned o where o.tbl = k.tbl)),
  null, 'fixture sanity: distributor B owns rows in every tenant-scoped table (no vacuous passes)');

grant select on table_keys, b_owned to authenticated;

create function pg_temp.assert_sees_no_b_rows(p_who text) returns setof text language plpgsql as $$
declare
  t record;
  n bigint;
begin
  for t in select tbl, key_expr from pg_temp.table_keys order by tbl loop
    execute format('select count(*) from public.%I x where (%s) in (select id from pg_temp.b_owned where tbl = %L)',
                   t.tbl, t.key_expr, t.tbl) into n;
    return next is(n, 0::bigint, format('%s sees 0 distributor-B rows in %s', p_who, t.tbl));
  end loop;
end;
$$;

-- 6 users x 22 tables = 132 isolation assertions ---------------------------------------------
select pg_temp.login('lp.agent1');   set local role authenticated;
select * from pg_temp.assert_sees_no_b_rows('A agent');
reset role;
select pg_temp.login('lp.driver1');  set local role authenticated;
select * from pg_temp.assert_sees_no_b_rows('A driver');
reset role;
select pg_temp.login('lp.wh.ikeja'); set local role authenticated;
select * from pg_temp.assert_sees_no_b_rows('A warehouse staff');
reset role;
select pg_temp.login('lp.bm.ikeja'); set local role authenticated;
select * from pg_temp.assert_sees_no_b_rows('A branch manager');
reset role;
select pg_temp.login('lp.admin');    set local role authenticated;
select * from pg_temp.assert_sees_no_b_rows('A distributor admin');
reset role;
select pg_temp.login('retailer01');  set local role authenticated;
select * from pg_temp.assert_sees_no_b_rows('A retailer');
reset role;

-- Positive scoping: agent ---------------------------------------------------------------------
select pg_temp.login('lp.agent1'); set local role authenticated;
select is((select count(*)::int from public.stock_locations), 1, 'agent sees exactly one stock location (own)');
select is((select count(*)::int from public.stock_balances where location_id not in
            (select sl.id from public.stock_locations sl where sl.user_id = (select app.current_user_id()))),
          0, 'agent sees no other location''s balances');
select is((select count(*)::int from public.organisations where kind = 'retailer'), 4,
          'agent sees the 4 retailers of their own territory only');
select is((select count(*)::int from public.skus), 15, 'agent can read the full manufacturer catalogue');
select is((select count(*)::int from public.orders), 1, 'agent sees the order of a retailer in their territory');
select is((select count(*)::int from public.accounts where counterparty_user_id <> (select app.current_user_id())
                                                     or counterparty_user_id is null),
          0, 'agent sees only accounts where they are the counterparty');
reset role;

select pg_temp.login('lp.agent3'); set local role authenticated;
select is((select count(*)::int from public.orders), 0, 'an agent of another territory does not see that order');
reset role;

-- Branch manager / admin ----------------------------------------------------------------------
select pg_temp.login('lp.bm.ikeja'); set local role authenticated;
select is((select count(*)::int from public.stock_locations), 4,
          'Ikeja branch manager sees Ikeja warehouse + 3 Ikeja carriers');
select is((select count(*)::int from public.organisations where kind = 'retailer'), 8,
          'Ikeja branch manager sees the 8 retailers of Ikeja territories');
reset role;
select pg_temp.login('lp.admin'); set local role authenticated;
select is((select count(*)::int from public.stock_locations), 6, 'distributor admin sees all 6 of their locations');
select is((select count(*)::int from public.organisations where kind = 'retailer'), 12,
          'distributor admin sees all 12 of their retailers');
select is((select count(*)::int from public.accounts
           where account_type = 'wallet' and holder_org_id <> all((select app.my_org_ids())::uuid[])),
          0, 'distributor admin cannot see customers'' wallets (a retailer may pay other distributors from it)');
reset role;

-- Retailer --------------------------------------------------------------------------------------
select pg_temp.login('retailer01'); set local role authenticated;
select is((select count(*)::int from public.organisations where kind = 'retailer'), 1, 'retailer sees only itself');
select is((select array_agg(account_type::text order by account_type::text) from public.accounts),
          array['receivables', 'trade_credit', 'wallet'], 'retailer sees own wallet, receivable and credit only');
select is((select count(*)::int from public.stock_balances), 0, 'retailer sees no stock balances');
select is((select count(*)::int from public.profiles), 1, 'retailer sees only its own profile');
select is((select count(*)::int from public.price_list_items) > 0, true, 'retailer can read its distributor''s prices');
reset role;

-- Manufacturer: aggregates only, no retailer PII, no ledgers -----------------------------------
select pg_temp.login('sunrise.admin'); set local role authenticated;
select is((select count(*)::int from public.organisations where kind = 'distributor'), 2,
          'manufacturer sees its 2 supplied distributors');
select is((select count(*)::int from public.organisations where kind = 'retailer'), 0, 'manufacturer sees no retailers');
select is((select count(*)::int from public.profiles), 1, 'manufacturer sees only its own profile (no retailer PII)');
select is((select count(*)::int from public.accounts) + (select count(*)::int from public.stock_balances), 0,
          'manufacturer sees no accounts and no stock balances');
reset role;

-- Platform admin ------------------------------------------------------------------------------
select pg_temp.login('platform.admin'); set local role authenticated;
select is((select count(*)::int from public.organisations), 24, 'platform admin sees all 24 organisations');
reset role;

-- Writes are impossible for clients ---------------------------------------------------------
select pg_temp.login('lp.admin'); set local role authenticated;
select throws_ok($$ insert into public.stock_movements (movement_group_id, movement_type, location_id, org_id, sku_id,
                      qty, on_hand_delta, reserved_delta)
                    select gen_random_uuid(), 'receipt', id, org_id, (select id from public.skus limit 1), 1, 1, 0
                    from public.stock_locations limit 1 $$,
                 '42501', null, 'client cannot insert into stock_movements');
select throws_ok($$ update public.stock_balances set on_hand = 0 $$, '42501', null, 'client cannot update stock_balances');
select throws_ok($$ update public.customer_relationships set credit_limit_kobo = 1 $$, '42501', null,
                 'client cannot update credit limits directly');
select throws_ok($$ select count(*) from audit.audit_log $$, '42501', null, 'client cannot read the audit log');
select throws_ok($$ select app.post_journal('x', 'xxxxxxxxxx', '[]'::jsonb) $$, '42501', null,
                 'client cannot call ledger primitives');
select throws_ok($$ select app.reserve_order(gen_random_uuid(), gen_random_uuid()) $$, '42501', null,
                 'client cannot call reserve_order directly');
reset role;

set local role anon;
select throws_ok($$ select count(*) from public.organisations $$, '42501', null, 'anon cannot read anything');
reset role;

select * from finish();
rollback;
