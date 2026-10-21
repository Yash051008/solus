-- Phase 3 commands, executed as real authenticated users: org structure, registration + approval
-- (with separation of duties), KYC recording rules, and the fail-closed geofence.
begin;
create extension if not exists pgtap with schema extensions;
select plan(52);

create function pg_temp.as_user(p_handle text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', (select id from pg_temp.ids where handle = p_handle),
                      'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;
create function pg_temp.as_owner() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end;
$$;
create function pg_temp.new_user(p_handle text) returns uuid language sql as $$
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
          p_handle || '@solus.test', '', now(), now())
  returning id
$$;
-- Id lookups must not depend on the caller's RLS: they read snapshots refreshed as owner.
create temp table ref_ids (kind text, name text, id uuid);
create function pg_temp.refresh_ids() returns void language sql as $$
  delete from pg_temp.ref_ids;
  insert into pg_temp.ref_ids
            select 'org', slug, id from public.organisations
  union all select 'branch', name, id from public.branches
  union all select 'territory', name, id from public.territories;
$$;
create function pg_temp.org(p_slug text) returns uuid language sql as $$
  select id from pg_temp.ref_ids where kind = 'org' and name = p_slug
$$;
create function pg_temp.branch(p_name text) returns uuid language sql as $$
  select id from pg_temp.ref_ids where kind = 'branch' and name = p_name
$$;
create function pg_temp.territory(p_name text) returns uuid language sql as $$
  select id from pg_temp.ref_ids where kind = 'territory' and name = p_name
$$;

select pg_temp.new_user('newshop');
select pg_temp.new_user('newagent');
select pg_temp.new_user('newbm');
-- auth.users is not readable by clients: resolve ids up front.
create temp table ids as select split_part(email, '@', 1) as handle, id from auth.users;
create function pg_temp.uid(p_handle text) returns uuid language sql as $$
  select id from pg_temp.ids where handle = p_handle
$$;
grant select on ids, ref_ids to authenticated;
select pg_temp.refresh_ids();
grant execute on function pg_temp.as_user(text), pg_temp.as_owner(), pg_temp.org(text), pg_temp.branch(text),
  pg_temp.territory(text), pg_temp.uid(text) to authenticated;

-- Org structure ---------------------------------------------------------------------------------
select pg_temp.as_user('lp.admin');
select lives_ok($$ select app.create_branch(pg_temp.org('lagos-prime'), 'Yaba') $$, 'distributor admin creates a branch');
select pg_temp.as_user('lp.bm.ikeja');
select throws_ok($$ select app.create_branch(pg_temp.org('lagos-prime'), 'Surulere') $$, 'SOL03', null,
                 'a branch manager cannot create branches');
select pg_temp.as_user('ac.admin');
select throws_ok($$ select app.create_branch(pg_temp.org('lagos-prime'), 'Ajah') $$, 'SOL03', null,
                 'another distributor''s admin cannot create branches here');

select pg_temp.as_owner(); select pg_temp.refresh_ids();
select pg_temp.as_user('lp.bm.ikeja');
select lives_ok($$ select app.create_territory(pg_temp.branch('Ikeja'), 'Ikeja GRA',
  '{"type":"Polygon","coordinates":[[[3.34,6.57],[3.36,6.57],[3.36,6.59],[3.34,6.59],[3.34,6.57]]]}'::jsonb) $$,
  'branch manager creates a territory with a boundary in their own branch');
select throws_ok($$ select app.create_territory(pg_temp.branch('Lekki'), 'Lekki Phase 2') $$, 'SOL03', null,
                 'branch manager cannot create territories in another branch');
select throws_ok($$ select app.create_territory(pg_temp.branch('Ikeja'), 'Bow Tie',
  '{"type":"Polygon","coordinates":[[[3.30,6.50],[3.32,6.52],[3.32,6.50],[3.30,6.52],[3.30,6.50]]]}'::jsonb) $$,
  'SOL05', null, 'a self-intersecting boundary is rejected');

select pg_temp.as_user('lp.admin');
select lives_ok($$ select app.create_warehouse(pg_temp.branch('Yaba'), 'Yaba Store', 6.5095, 3.3711) $$,
                'admin creates a warehouse');
select is((select count(*)::int from public.stock_locations sl join public.warehouses w on w.id = sl.warehouse_id
           where w.name = 'Yaba Store'), 1, 'the new warehouse gets its stock location');
select throws_ok($$ select app.create_warehouse(pg_temp.branch('Yaba'), 'Nowhere', 95, 3.37) $$, 'SOL05', null,
                 'invalid coordinates are rejected');
select throws_ok($$ select app.set_warehouse_active((select id from public.warehouses where name = 'Ikeja Main'), false) $$,
                 'SOL04', null, 'a warehouse holding stock cannot be deactivated');
select lives_ok($$ select app.set_warehouse_active((select id from public.warehouses where name = 'Yaba Store'), false) $$,
                'an empty warehouse can be deactivated');
select pg_temp.as_user('lp.bm.ikeja');
select throws_ok($$ select app.update_distributor_settings(pg_temp.org('lagos-prime'), 1000, 300, 30) $$, 'SOL03', null,
                 'only the distributor admin changes distributor settings');

-- Retailer registration --------------------------------------------------------------------------
select pg_temp.as_owner();
select set_config('role', 'authenticated', true);   -- authenticated role, but no user in the JWT
select throws_ok($$ select app.register_retailer('Ghost Shop', 'Ghost', '+2348000000999', 6.45, 3.48, 10,
                      pg_temp.org('lagos-prime')) $$, 'SOL03', 'authentication required', 'registration requires a signed-in user');

select pg_temp.as_user('newshop');
select is((select count(*)::int from app.registration_directory()), 2, 'a newcomer sees the 2 active distributors');
select throws_ok($$ select app.register_retailer('Bad Shop', 'X', '+2348000000998', 6.45, 300, 10, pg_temp.org('lagos-prime')) $$,
                 'SOL05', null, 'registration with invalid coordinates is rejected');
select lives_ok($$ select app.register_retailer('Lekki Corner Store', 'Ada Obi', '+2348011112222', 6.4510, 3.4790, 12,
                      pg_temp.org('lagos-prime')) $$, 'a new user registers a shop');
select throws_ok($$ select app.register_retailer('Second Shop', 'Ada Obi', '+2348011112222', 6.45, 3.48, 12, pg_temp.org('lagos-prime')) $$,
                 'SOL04', null, 'one shop per account');

select pg_temp.as_owner();
create temp table shop as
select o.id as org_id, cr.id as cr_id, cr.territory_id, cr.status::text as cr_status, o.status::text as org_status
from public.organisations o join public.customer_relationships cr on cr.retailer_org_id = o.id
where o.name = 'Lekki Corner Store';
grant select on shop to authenticated;
select results_eq($$ select cr_status, org_status, territory_id from shop $$,
                  $$ values ('pending', 'pending', pg_temp.territory('Lekki Phase 1')) $$,
                  'shop and relationship are pending, territory suggested from the nearest warehouse');

select pg_temp.as_user('newshop');
select is((select count(*)::int from public.organisations where kind = 'retailer'), 1, 'the new shop owner sees their own shop');

select pg_temp.as_user('lp.bm.ikeja');
select throws_ok($$ select app.decide_customer((select cr_id from shop), true) $$, 'SOL03', null,
                 'Ikeja branch manager cannot approve a customer in a Lekki territory');
select pg_temp.as_user('ac.admin');
select throws_ok($$ select app.decide_customer((select cr_id from shop), true) $$, 'SOL03', null,
                 'another distributor cannot approve this customer');
select pg_temp.as_user('lp.bm.lekki');
select lives_ok($$ select app.decide_customer((select cr_id from shop), true) $$, 'Lekki branch manager approves the customer');
select throws_ok($$ select app.decide_customer((select cr_id from shop), true) $$, 'SOL04', null, 'a decision cannot be repeated');

select pg_temp.as_owner();
select results_eq(
  $$ select cr.status::text, o.status::text, (select count(*)::int from public.accounts a
       where a.book_org_id = cr.distributor_org_id and a.counterparty_org_id = o.id)
     from public.customer_relationships cr join public.organisations o on o.id = cr.retailer_org_id
     where cr.id = (select cr_id from shop) $$,
  $$ values ('active', 'active', 2) $$,
  'approval activates shop + relationship and opens receivable and trade-credit accounts');

select pg_temp.as_user('newshop');
select lives_ok($$ select app.request_distributor((select org_id from shop), pg_temp.org('abuja-central')) $$,
                'retailer asks a second distributor to serve them');
select pg_temp.as_user('ac.bm.wuse');
select throws_ok($$ select app.decide_customer((select id from public.customer_relationships
                      where retailer_org_id = (select org_id from shop) and status = 'pending'), false) $$,
                 'SOL05', null, 'rejection requires a reason');
select lives_ok($$ select app.decide_customer((select id from public.customer_relationships
                      where retailer_org_id = (select org_id from shop) and status = 'pending'), false, null, 'outside coverage') $$,
                'Wuse branch manager rejects with a reason');

-- Separation of duties: a branch manager who also owns a shop cannot approve it.
select pg_temp.as_user('lp.bm.lekki');
select lives_ok($$ select app.register_retailer('Manager Side Shop', 'Lekki BM', '+2348000000012', 6.4520, 3.4810, 8,
                      pg_temp.org('lagos-prime')) $$, 'a branch manager may own a shop');
select throws_ok($$ select app.decide_customer((select cr.id from public.customer_relationships cr
                      join public.organisations o on o.id = cr.retailer_org_id where o.name = 'Manager Side Shop'), true) $$,
                 'SOL03', 'you cannot approve your own shop', 'but cannot approve their own shop');

-- Join requests -------------------------------------------------------------------------------
select pg_temp.as_user('newagent');
select lives_ok($$ select app.request_to_join(pg_temp.org('lagos-prime'), 'agent', 'New Agent', '+2348022223333') $$,
                'a new user requests to join as an agent');
select throws_ok($$ select app.request_to_join(pg_temp.org('lagos-prime'), 'agent', 'New Agent', '+2348022223333') $$,
                 '23505', null, 'only one pending request per role');
select pg_temp.as_user('lp.bm.ikeja');
select is((select count(*)::int from public.profiles where user_id = pg_temp.uid('newagent')), 1,
          'an approver can see the applicant''s profile');
select pg_temp.as_user('ac.admin');
select is((select count(*)::int from public.profiles where user_id = pg_temp.uid('newagent')), 0,
          'another distributor cannot see the applicant');
select pg_temp.as_user('lp.bm.ikeja');
select throws_ok($$ select app.decide_join_request((select id from public.join_requests where status = 'pending' and requested_role = 'agent'),
                      true, pg_temp.branch('Lekki'), pg_temp.territory('Lekki Phase 1')) $$,
                 'SOL03', null, 'Ikeja branch manager cannot place an agent in the Lekki branch');
select throws_ok($$ select app.decide_join_request((select id from public.join_requests where status = 'pending' and requested_role = 'agent'),
                      true, pg_temp.branch('Ikeja'), null) $$,
                 '23514', null, 'an agent cannot be approved without a territory');
select throws_ok($$ select app.decide_join_request((select id from public.join_requests where status = 'pending' and requested_role = 'agent'),
                      true, pg_temp.branch('Ikeja'), pg_temp.territory('Lekki Phase 1')) $$,
                 '23503', null, 'an agent''s territory must belong to their branch');
select lives_ok($$ select app.decide_join_request((select id from public.join_requests where status = 'pending' and requested_role = 'agent'),
                     true, pg_temp.branch('Ikeja'), pg_temp.territory('Ikeja North')) $$,
                'Ikeja branch manager approves the agent into Ikeja North');
select pg_temp.as_owner();
select results_eq(
  $$ select (select count(*)::int from public.memberships m join auth.users u on u.id = m.user_id
              where u.email = 'newagent@solus.test' and m.role = 'agent' and m.status = 'active'),
            (select count(*)::int from public.stock_locations sl join auth.users u on u.id = sl.user_id
              where u.email = 'newagent@solus.test'),
            (select count(*)::int from public.accounts a join auth.users u on u.id = a.counterparty_user_id
              where u.email = 'newagent@solus.test') $$,
  $$ values (1, 1, 3) $$,
  'approved agent gets an active membership, a stock location and cash/variance/receivable accounts');

select pg_temp.as_user('newbm');
select lives_ok($$ select app.request_to_join(pg_temp.org('lagos-prime'), 'branch_manager', 'New BM', '+2348033334444') $$,
                'a user requests to become a branch manager');
select pg_temp.as_user('lp.bm.ikeja');
select throws_ok($$ select app.decide_join_request((select id from public.join_requests where requested_role = 'branch_manager'),
                      true, pg_temp.branch('Ikeja')) $$, 'SOL03', null, 'a branch manager cannot appoint branch managers');
select pg_temp.as_user('lp.admin');
select lives_ok($$ select app.request_to_join(pg_temp.org('lagos-prime'), 'agent', 'Lagos Prime Admin', '+2348000000010') $$,
                'an admin files a request for an extra role');
select throws_ok($$ select app.decide_join_request((select id from public.join_requests
                      where user_id = pg_temp.uid('lp.admin')), true, pg_temp.branch('Ikeja'), pg_temp.territory('Ikeja North')) $$,
                 'SOL03', 'you cannot decide your own request', 'nobody decides their own join request');

-- KYC recording (service_role only; see 001 for the grant check) ---------------------------------
select pg_temp.as_owner();
select is((app.record_kyc_result((select org_id from shop), (select id from auth.users where email = 'newshop@solus.test'),
           'BVN', 'exact_match', 'mock', 'ref-bvn-1', repeat('b', 64)) ->> 'kyc_level')::int, 1, 'BVN exact match -> level 1');
select is((app.record_kyc_result((select org_id from shop), (select id from auth.users where email = 'newshop@solus.test'),
           'BVN', 'exact_match', 'mock', 'ref-bvn-1', repeat('b', 64)) ->> 'kyc_level')::int, 1, 'replay of the same provider ref is idempotent');
select is((select count(*)::int from public.kyc_checks where provider_ref = 'ref-bvn-1'), 1, 'the replay stored nothing new');
select is((app.record_kyc_result((select org_id from shop), (select id from auth.users where email = 'newshop@solus.test'),
           'NIN', 'partial_match', 'mock', 'ref-nin-1', repeat('c', 64)) ->> 'kyc_level')::int, 1, 'NIN partial match does not raise the level');
select is((app.record_kyc_result((select org_id from shop), (select id from auth.users where email = 'newshop@solus.test'),
           'NIN', 'exact_match', 'mock', 'ref-nin-2', repeat('c', 64)) ->> 'kyc_level')::int, 2, 'NIN exact match -> level 2');
select is((app.record_kyc_result(pg_temp.org('retailer-01'), (select id from auth.users where email = 'retailer01@solus.test'),
           'BVN', 'exact_match', 'mock', 'ref-bvn-r01', repeat('b', 64)) ->> 'same_identity_other_shops')::int, 1,
          'the same BVN exact-matched for another shop is surfaced');
select throws_ok($$ select app.record_kyc_result(pg_temp.org('retailer-02'), (select id from auth.users where email = 'newshop@solus.test'),
                      'BVN', 'exact_match', 'mock', 'ref-x', repeat('d', 64)) $$, 'SOL05', null,
                 'a KYC result must belong to the shop''s owner');
select throws_ok($$ update public.kyc_checks set outcome = 'exact_match' $$, 'SOL06', null, 'kyc_checks is append-only');
select pg_temp.as_user('newshop');
select throws_ok($$ select id_hash from public.kyc_checks $$, '42501', null, 'clients cannot read the identity digest');
select is((select array_agg(outcome order by checked_at, outcome) from public.kyc_checks), array['exact_match', 'exact_match', 'partial_match'],
          'the shop owner can read their own outcomes');

select * from finish();
rollback;
