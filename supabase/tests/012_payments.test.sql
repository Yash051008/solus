-- Phase 5b-1 money flows on the seeded delivered order of retailer-05 (Lagos Prime, invoiced N19,930.00):
-- webhook idempotency, wallet + trade-credit settlement with OTP and limit lock, repayment, cash at delivery,
-- receipt allocation, reconciliation, and ledger invariants.
begin;
create extension if not exists pgtap with schema extensions;
select plan(30);

create temp table ids as select split_part(email, '@', 1) as handle, id from auth.users;
create temp table f as select
  (select id from public.organisations where slug = 'lagos-prime') as lp,
  (select id from public.organisations where slug = 'retailer-05') as shop,
  (select account_number from public.virtual_accounts va join public.organisations o on o.id = va.org_id where o.slug = 'retailer-05') as shop_va,
  (select o.id from public.orders o join public.organisations r on r.id = o.retailer_org_id where r.slug = 'retailer-05' and o.status = 'partially_delivered') as ord,
  (select cr.id from public.customer_relationships cr join public.organisations r on r.id = cr.retailer_org_id where r.slug = 'retailer-05') as rel,
  (select id from public.provider_events where provider_event_id = 'seed-remit-0001') as remit;
create temp table t (name text primary key, j jsonb);
create function pg_temp.uid(h text) returns uuid language sql as $$ select id from pg_temp.ids where handle = h $$;
create function pg_temp.as_user(h text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(h), 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function pg_temp.as_owner() returns void language plpgsql as $$
begin perform set_config('role', 'postgres', true); perform set_config('request.jwt.claims', '', true); end $$;
create function pg_temp.bal(p_type text, p_cp_org uuid default null, p_cp_user uuid default null, p_holder uuid default null) returns bigint language sql as $$
  select coalesce((select b.balance_kobo from public.accounts a join public.account_balances b on b.account_id = a.id
    where a.account_type::text = p_type and a.counterparty_org_id is not distinct from p_cp_org
      and a.counterparty_user_id is not distinct from p_cp_user and a.holder_org_id is not distinct from p_holder), 0) $$;
grant select, insert, update on ids, f, t to authenticated;
grant execute on function pg_temp.uid(text), pg_temp.as_user(text), pg_temp.as_owner() to authenticated;

-- Webhooks ------------------------------------------------------------------------------------------
select is(app.record_provider_event('mock', 'evt-0001', 'TOPUP', f.shop_va, 500000, 'hash-a')->>'status', 'posted', 'transfer into the shop VA is posted') from f;
select is(pg_temp.bal('wallet', null, null, f.shop), -13000000::bigint, 'wallet = N125,000 seed + N5,000 = N130,000 (credit-normal)') from f;
select results_eq($$ select r->>'status', r->>'hash_match' from (select app.record_provider_event('mock', 'evt-0001', 'TOPUP', f.shop_va, 500000, 'hash-a') r from f) x $$,
                  $$ values ('duplicate', 'true') $$, 'the same event again is a duplicate');
select is(pg_temp.bal('wallet', null, null, f.shop), -13000000::bigint, 'no second credit') from f;
select is(app.record_provider_event('mock', 'evt-0001', 'TOPUP', f.shop_va, 999999, 'hash-b')->>'hash_match', 'false', 'a replay with a different payload is flagged') from f;
select is((select hash_conflict and duplicate_count = 2 from public.provider_events where provider_event_id = 'evt-0001'), true, 'conflict and count recorded');
select is(app.record_provider_event('mock', 'evt-0002', 'X', '9999999999', 100, 'h')->>'status', 'unmatched', 'unknown account: stored as unmatched, no money posted');
select pg_temp.as_user('retailer05');
select throws_ok($$ select app.record_provider_event('mock', 'evt-x', 'X', '1', 1, 'h') $$, '42501', null, 'clients cannot post provider events');

-- Settlement ------------------------------------------------------------------------------------------
select is(app.order_amount_due((select ord from f)), 1993000::bigint, 'amount due = invoiced N19,930');
select is(app.start_order_payment((select ord from f), 300000, 0, 'test:pay:wallet01')->>'status', 'settled', 'wallet-only payment settles at once');
select is(app.order_amount_due((select ord from f)), 1693000::bigint, 'due reduced to N16,930');
select throws_ok($$ select app.start_order_payment((select ord from f), 0, 2000000, 'test:pay:toomuch') $$, 'SOL05', null, 'cannot pay more than is due');
insert into t select 'p1', app.start_order_payment((select ord from f), 0, 1200000, 'test:pay:credit01');
select is((select j->>'status' from t where name = 'p1'), 'pending_otp', 'any credit needs the shop''s OTP');
select pg_temp.as_owner();
update t set j = j || jsonb_build_object('code', (select code from app.issue_otp_code((j->>'challenge_id')::uuid))) where name = 'p1';
select pg_temp.as_user('retailer05');
select throws_ok($$ select app.verify_otp((select (j->>'challenge_id')::uuid from t where name = 'p1'), (select j->>'code' from t where name = 'p1')) $$,
                 'SOL04', 'credit_limit_exceeded', 'with a zero limit the credit draw is refused');

select pg_temp.as_user('lp.bm.ikeja');
select throws_ok($$ select app.set_credit_limit((select rel from f), 1000000) $$, 'SOL03', null, 'only the distributor admin sets credit limits');
select pg_temp.as_user('lp.admin');
select lives_ok($$ select app.set_credit_limit((select rel from f), 1000000) $$, 'admin sets a N10,000 limit');

select pg_temp.as_user('retailer05');
insert into t select 'p2', app.start_order_payment((select ord from f), 200000, 1000000, 'test:pay:split001');
select pg_temp.as_owner();
update t set j = j || jsonb_build_object('code', (select code from app.issue_otp_code((j->>'challenge_id')::uuid))) where name = 'p2';
select pg_temp.as_user('retailer05');
select is(app.verify_otp((select (j->>'challenge_id')::uuid from t where name = 'p2'),
            case when (select j->>'code' from t where name = 'p2') = '000000' then '111111' else '000000' end)->>'reason', 'wrong_code', 'a wrong credit code is refused');
select is(app.verify_otp((select (j->>'challenge_id')::uuid from t where name = 'p2'), (select j->>'code' from t where name = 'p2'))->>'result',
          'settled', 'N2,000 wallet + N10,000 credit settle as one journal after the OTP');
select pg_temp.as_owner();
select results_eq($$ select app.order_amount_due(f.ord), pg_temp.bal('trade_credit', f.shop), pg_temp.bal('wallet', null, null, f.shop) from f $$,
                  $$ values (493000::bigint, 1000000::bigint, -12500000::bigint) $$, 'due N4,930; credit drawn N10,000; wallet N125,000 (130,000 - 3,000 - 2,000)');
select pg_temp.as_user('retailer05');
insert into t select 'p3', app.start_order_payment((select ord from f), 0, 1, 'test:pay:over0001');
select pg_temp.as_owner();
update t set j = j || jsonb_build_object('code', (select code from app.issue_otp_code((j->>'challenge_id')::uuid))) where name = 'p3';
select pg_temp.as_user('retailer05');
select throws_ok($$ select app.verify_otp((select (j->>'challenge_id')::uuid from t where name = 'p3'), (select j->>'code' from t where name = 'p3')) $$,
                 'SOL04', 'credit_limit_exceeded', 'not one kobo over the limit');
select lives_ok($$ select app.repay_credit((select lp from f), (select shop from f), 400000, 'test:repay:0001') $$, 'shop repays N4,000 of credit from its wallet');
select pg_temp.as_owner();
select is(pg_temp.bal('trade_credit', f.shop), 600000::bigint, 'credit drawn now N6,000') from f;

-- Cash at delivery, allocation, reconciliation ------------------------------------------------------
select pg_temp.as_user('lp.agent1');
select throws_ok($$ select app.record_delivery_cash((select ord from f), 493000, 'test:cash:0000001') $$, 'SOL03', null, 'only the delivering carrier records cash');
select pg_temp.as_user('lp.driver1');
select lives_ok($$ select app.record_delivery_cash((select ord from f), 493000, 'test:cash:0000001') $$, 'driver records the remaining N4,930 cash');
select pg_temp.as_owner();
select results_eq($$ select o.status::text, pg_temp.bal('cash_in_transit', null, pg_temp.uid('lp.driver1')) from public.orders o, f where o.id = f.ord $$,
                  $$ values ('settled', 493000::bigint) $$, 'order settled; the driver holds N4,930 cash');

select pg_temp.as_user('lp.admin');
select throws_ok($$ select app.allocate_receipt((select remit from f), 'agent_cash', pg_temp.uid('lp.agent1'), 2800001) $$, 'SOL05', null,
                 'cannot allocate more than was received');
select lives_ok($$ select app.allocate_receipt((select remit from f), 'agent_cash', pg_temp.uid('lp.agent1'), 2800000) $$,
                'the N28,000 transfer is allocated to agent 1''s cash');
select pg_temp.as_owner();
select is(pg_temp.bal('cash_in_transit', null, pg_temp.uid('lp.agent1')), 0::bigint, 'agent 1 has remitted all the cash from the seeded push sales');

select pg_temp.as_user('platform.admin');
select results_eq($$ select r->'missing_in_ledger', (r->'missing_in_statement') @> '["seed-remit-0001", "evt-0002"]'::jsonb from (select app.reconcile_provider('mock',
                      jsonb_build_array(jsonb_build_object('provider_event_id', 'evt-0001', 'amount_kobo', '500000'),
                                        jsonb_build_object('provider_event_id', 'evt-lost', 'amount_kobo', '700'))) r) x $$,
                  $$ values ('["evt-lost"]'::jsonb, true) $$,
                  'reconciliation finds the lost webhook and the transfers missing from the statement');
select pg_temp.as_owner();
select is_empty($$ select * from app.check_money_projection() union all select null, null, null from app.check_journals_balanced() $$,
                'balances = ledger and every journal balances per book');

select * from finish();
rollback;
