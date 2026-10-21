-- Phase 5a push flow as real users: request/approval SoD, OTP rules (hashed, bound, expiring,
-- attempt-limited, re-issue limited, initiator-only), geofenced sales, OTP-bound returns, variance
-- cases, close blocking, write-off and charge-to-agent resolutions, and ledger invariants.
begin;
create extension if not exists pgtap with schema extensions;
select plan(39);

create temp table ids as select split_part(email, '@', 1) as handle, id from auth.users;
create temp table ref_ids as select 'org' as kind, slug as name, id from public.organisations
  union all select 'wh', name, id from public.warehouses union all select 'sku', code, id from public.skus;
create function pg_temp.uid(h text) returns uuid language sql as $$ select id from pg_temp.ids where handle = h $$;
create function pg_temp.ref(k text, n text) returns uuid language sql as $$ select id from pg_temp.ref_ids where kind = k and name = n $$;
create function pg_temp.as_user(h text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(h), 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function pg_temp.as_owner() returns void language plpgsql as $$
begin perform set_config('role', 'postgres', true); perform set_config('request.jwt.claims', '', true); end $$;
create temp table t (name text primary key, id uuid, code text);
grant select, insert, update on ids, ref_ids, t to authenticated;
grant execute on function pg_temp.uid(text), pg_temp.ref(text, text), pg_temp.as_user(text), pg_temp.as_owner() to authenticated;
create function pg_temp.sku() returns uuid language sql as $$ select pg_temp.ref('sku', 'HOM-DET-500G') $$;
create function pg_temp.id(n text) returns uuid language sql as $$ select id from pg_temp.t where name = n $$;
grant execute on function pg_temp.sku(), pg_temp.id(text) to authenticated;
create function pg_temp.carried() returns int language sql as $$
  select coalesce(sum(b.on_hand), 0)::int from public.stock_balances b join public.stock_locations sl on sl.id = b.location_id
  where sl.user_id = pg_temp.uid('lp.agent2') and b.sku_id = pg_temp.sku() $$;

-- Request + approval ---------------------------------------------------------------------------------
select pg_temp.as_user('lp.agent2');
insert into t select 'req', app.request_stock(pg_temp.ref('wh', 'Ikeja Main'),
  jsonb_build_array(jsonb_build_object('sku_id', pg_temp.sku(), 'uom_code', 'piece', 'uom_qty', 60)), 'route');
select pg_temp.as_user('lp.bm.lekki');
select throws_ok($$ select app.decide_stock_request(pg_temp.id('req'), true) $$, 'SOL03', null, 'Lekki manager cannot approve an Ikeja request');
select pg_temp.as_user('lp.bm.ikeja');
insert into t select 'ship', app.decide_stock_request(pg_temp.id('req'), true,
  jsonb_build_array(jsonb_build_object('sku_id', pg_temp.sku(), 'qty_pieces', 50)), 'only 50 today');
select pg_temp.as_owner();
select results_eq($$ select kind, status, (select qty_pieces from public.shipment_lines where shipment_id = s.id) from public.shipments s where id = pg_temp.id('ship') $$,
                  $$ values ('push', 'awaiting_acceptance', 50) $$, 'partial approval creates a push shipment for 50 pcs');
select pg_temp.as_user('lp.agent2');
insert into t select 'req2', app.request_stock(pg_temp.ref('wh', 'Ikeja Main'),
  jsonb_build_array(jsonb_build_object('sku_id', pg_temp.sku(), 'uom_code', 'piece', 'uom_qty', 5)));
select pg_temp.as_user('lp.bm.ikeja');
select throws_ok($$ select app.decide_stock_request(pg_temp.id('req2'), true) $$, 'SOL04', null, 'one unfinished shipment per agent');

-- OTP handover ---------------------------------------------------------------------------------------
select pg_temp.as_user('lp.agent2');
select throws_ok($$ select app.start_handover(pg_temp.id('ship')) $$, 'SOL03', null, 'the agent cannot start their own handover');
select pg_temp.as_user('lp.wh.ikeja');
insert into t select 'c1', app.start_handover(pg_temp.id('ship'));
select is(app.verify_otp(pg_temp.id('c1'), '000000')->>'reason', 'code_not_sent', 'nothing verifies before a code is sent');
select throws_ok($$ select * from app.issue_otp_code(pg_temp.id('c1')) $$, '42501', null, 'clients cannot obtain codes');
select throws_ok($$ select * from private.otp_challenges $$, '42501', null, 'clients cannot read challenges');
select pg_temp.as_owner();
update t set code = (select code from app.issue_otp_code(pg_temp.id('c1'))) where name = 'c1';
select ok((select code_hash like '$2%' and code_hash <> (select code from t where name = 'c1') from private.otp_challenges where id = pg_temp.id('c1')),
          'only a bcrypt hash is stored, never the code');
select pg_temp.as_user('lp.wh.ikeja');
select results_eq($$ select v->>'reason', (v->>'attempts_left')::int from (select app.verify_otp(pg_temp.id('c1'),
                      case when (select code from t where name = 'c1') = '111111' then '222222' else '111111' end) v) x $$,
                  $$ values ('wrong_code', 4) $$, 'a wrong code fails and reports attempts left');
select pg_temp.as_owner();
select is((select attempts from private.otp_challenges where id = pg_temp.id('c1')), 1, 'the failed attempt is persisted (not rolled back)');
select pg_temp.as_user('lp.bm.ikeja');
select throws_ok($$ select app.verify_otp(pg_temp.id('c1'), (select code from t where name = 'c1')) $$, 'SOL03', null,
                 'only the initiator can enter the code');
select pg_temp.as_user('lp.wh.ikeja');
select app.verify_otp(pg_temp.id('c1'), 'bad') from generate_series(1, 4);
select is(app.verify_otp(pg_temp.id('c1'), (select code from t where name = 'c1'))->>'reason', 'locked',
          'after 5 wrong codes the challenge is locked, even for the right code');
select is(pg_temp.carried(), 0, 'nothing moved while locked');

insert into t select 'c2', app.start_handover(pg_temp.id('ship'));
select pg_temp.as_owner();
select app.issue_otp_code(pg_temp.id('c2'));
update private.otp_challenges set expires_at = now() - interval '1 second' where id = pg_temp.id('c2');
select pg_temp.as_user('lp.wh.ikeja');
select is(app.verify_otp(pg_temp.id('c2'), '123456')->>'reason', 'expired', 'an expired code fails');

insert into t select 'c3', app.start_handover(pg_temp.id('ship'));
select pg_temp.as_owner();
select app.issue_otp_code(pg_temp.id('c3')); select app.issue_otp_code(pg_temp.id('c3'));
update t set code = (select code from app.issue_otp_code(pg_temp.id('c3'))) where name = 'c3';
select throws_ok($$ select * from app.issue_otp_code(pg_temp.id('c3')) $$, 'SOL04', null, 'at most 3 codes per challenge');
select pg_temp.as_user('lp.wh.ikeja');
select is(app.verify_otp(pg_temp.id('c3'), (select code from t where name = 'c3'))->>'result', 'open', 'the latest code verifies and opens the shipment');
select is(pg_temp.carried(), 50, 'agent now carries 50 pcs');
select is(app.verify_otp(pg_temp.id('c3'), (select code from t where name = 'c3'))->>'reason', 'verified', 'a code cannot be replayed');

-- Geofenced push sales ---------------------------------------------------------------------------------
select pg_temp.as_user('lp.agent2');
select throws_ok($$ select app.record_push_sale(pg_temp.id('ship'), pg_temp.ref('org', 'retailer-07'),
                      jsonb_build_array(jsonb_build_object('sku_id', pg_temp.sku(), 'qty_pieces', 5)), 6.60, 3.40, 5, 'test:ps:far0001') $$,
                 'SOL05', 'outside_geofence', 'a sale away from the shop is rejected');
select throws_ok($$ select app.record_push_sale(pg_temp.id('ship'), pg_temp.ref('org', 'retailer-07'),
                      jsonb_build_array(jsonb_build_object('sku_id', pg_temp.sku(), 'qty_pieces', 51)), 6.5800, 3.3480, 5, 'test:ps:big0001') $$,
                 'SOL01', 'insufficient_carried_stock', 'cannot sell more than carried');
select throws_ok($$ select app.record_push_sale(pg_temp.id('ship'), pg_temp.ref('org', 'retailer-01'),
                      jsonb_build_array(jsonb_build_object('sku_id', pg_temp.sku(), 'qty_pieces', 1)), 6.62, 3.345, 5, 'test:ps:terr001') $$,
                 'SOL03', 'unknown_retailer', 'cannot sell to a shop outside the agent''s territory');
insert into t select 'sale', (app.record_push_sale(pg_temp.id('ship'), pg_temp.ref('org', 'retailer-07'),
  jsonb_build_array(jsonb_build_object('sku_id', pg_temp.sku(), 'qty_pieces', 30)), 6.5800, 3.3480, 5, 'test:ps:ok00001')->>'sale_id')::uuid;
select is((app.record_push_sale(pg_temp.id('ship'), pg_temp.ref('org', 'retailer-07'),
             jsonb_build_array(jsonb_build_object('sku_id', pg_temp.sku(), 'qty_pieces', 30)), 6.5800, 3.3480, 5, 'test:ps:ok00001')->>'sale_id')::uuid,
          pg_temp.id('sale'), 'replaying a sale returns the original');
select is(pg_temp.carried(), 20, '30 sold once, 20 left');
select pg_temp.as_owner();
select is((select b.balance_kobo from public.account_balances b join public.accounts a on a.id = b.account_id
           where a.account_type = 'cash_in_transit' and a.counterparty_user_id = pg_temp.uid('lp.agent2')),
          3600000::bigint, 'cash in transit = 30 x N1,200 = N36,000');

-- OTP-bound return -> variance -----------------------------------------------------------------------
select pg_temp.as_user('lp.agent2');
select throws_ok($$ select app.start_push_return(pg_temp.id('ship'), '[]') $$, 'SOL03', null, 'the agent cannot count their own return');
select pg_temp.as_user('lp.wh.ikeja');
insert into t select 'r1', app.start_push_return(pg_temp.id('ship'),
  jsonb_build_array(jsonb_build_object('sku_id', pg_temp.sku(), 'qty_pieces', 15, 'damaged', 3)));
select pg_temp.as_owner();
update t set code = (select code from app.issue_otp_code(pg_temp.id('r1'))) where name = 'r1';
update public.shipment_returns set qty_pieces = 17 where shipment_id = pg_temp.id('ship');
select pg_temp.as_user('lp.wh.ikeja');
select throws_ok($$ select app.verify_otp(pg_temp.id('r1'), (select code from t where name = 'r1')) $$, 'SOL04', null,
                 'the OTP is bound to the exact count: a changed count cannot be confirmed');
select pg_temp.as_owner();
update public.shipment_returns set qty_pieces = 15 where shipment_id = pg_temp.id('ship');
select pg_temp.as_user('lp.wh.ikeja');
select is(app.verify_otp(pg_temp.id('r1'), (select code from t where name = 'r1'))->>'result', 'reconciling',
          '50 picked = 30 sold + 15 returned + 3 damaged + 2 unaccounted -> reconciling');
select pg_temp.as_owner();
select results_eq($$ select qty_pieces, value_kobo, status from public.variance_cases where shipment_id = pg_temp.id('ship') $$,
                  $$ values (2, 240000::bigint, 'pending') $$, 'variance case: 2 pcs, N2,400, pending');
select is((select b.balance_kobo from public.account_balances b join public.accounts a on a.id = b.account_id
           where a.account_type = 'variance' and a.counterparty_user_id = pg_temp.uid('lp.agent2')),
          240000::bigint, 'pending variance shows on the agent''s variance account');
select pg_temp.as_user('lp.bm.ikeja');
select throws_ok($$ select app.close_shipment(pg_temp.id('ship')) $$, 'SOL04', null, 'cannot close while variance is pending');
select pg_temp.as_user('lp.wh.ikeja');
select throws_ok($$ select app.resolve_variance((select id from public.variance_cases where shipment_id = pg_temp.id('ship')), 'write_off', 'x') $$,
                 'SOL03', null, 'warehouse staff cannot resolve variance');
select pg_temp.as_user('lp.bm.ikeja');
select is(app.resolve_variance((select id from public.variance_cases where shipment_id = pg_temp.id('ship')), 'write_off', 'breakage on route'),
          'closed', 'manager writes it off and the shipment closes');
select pg_temp.as_owner();
select results_eq($$ select pg_temp.carried(), (select b.balance_kobo from public.account_balances b join public.accounts a on a.id = b.account_id
                       where a.account_type = 'variance' and a.counterparty_user_id = pg_temp.uid('lp.agent2')) $$,
                  $$ values (0, 0::bigint) $$, 'write-off clears both the stock and the variance account');

-- Seeded case (lp.agent1): charge the agent
select pg_temp.as_user('lp.bm.ikeja');
select is(app.resolve_variance((select vc.id from public.variance_cases vc where vc.carrier_user_id = pg_temp.uid('lp.agent1')), 'charge_agent', 'agent accepted liability'),
          'closed', 'charging the agent closes the seeded shipment');
select pg_temp.as_owner();
select is((select b.balance_kobo from public.account_balances b join public.accounts a on a.id = b.account_id
           where a.account_type = 'receivables' and a.counterparty_user_id = pg_temp.uid('lp.agent1')),
          80000::bigint, 'the agent now owes N800 (2 x N400)');

select is_empty($$ select * from app.check_stock_projection() $$, 'stock projection = ledger');
select is_empty($$ select * from app.check_stock_conservation() $$, 'stock conserved');
select is_empty($$ select * from app.check_money_projection() $$, 'account balances = ledger');
select is_empty($$ select * from app.check_journals_balanced() $$, 'every journal balances per book');

select * from finish();
rollback;
