-- Offline agent sync (hard rule 4): events with client UUIDs, idempotent replay, seq ordering, rejection into
-- the review queue (never dropped), accept-into-variance, close blocking, and resolution.
begin;
create extension if not exists pgtap with schema extensions;
select plan(28);

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
create temp table t (name text primary key, id uuid, j jsonb);
grant select, insert, update on ids, ref_ids, t to authenticated;
create function pg_temp.id(n text) returns uuid language sql as $$ select id from pg_temp.t where name = n $$;
create function pg_temp.sku() returns uuid language sql as $$ select pg_temp.ref('sku', 'HOM-DET-500G') $$;
-- A sale event for retailer-07 (Ikeja South, at the shop) or wherever given.
create function pg_temp.sale(p_seq int, p_qty int, p_lat float8 default 6.5800, p_lng float8 default 3.3480) returns jsonb language sql as $$
  select jsonb_build_object('event_id', md5('ev' || p_seq || p_qty || p_lat)::uuid, 'seq', p_seq, 'type', 'sale.recorded',
    'client_ts', '2026-10-22T10:00:00Z', 'lat', p_lat, 'lng', p_lng, 'accuracy_m', 6,
    'payload', jsonb_build_object('shipment_id', pg_temp.id('ship'), 'retailer_id', pg_temp.ref('org', 'retailer-07'),
      'lines', jsonb_build_array(jsonb_build_object('sku_id', pg_temp.sku(), 'qty_pieces', p_qty))))
$$;
create function pg_temp.carried() returns int language sql as $$
  select coalesce(sum(b.on_hand), 0)::int from public.stock_balances b join public.stock_locations sl on sl.id = b.location_id
  where sl.user_id = pg_temp.uid('lp.agent2') and b.sku_id = pg_temp.sku() $$;
grant execute on all functions in schema pg_temp to authenticated;
grant execute on function pg_temp.uid(text), pg_temp.ref(text, text), pg_temp.as_user(text), pg_temp.as_owner(), pg_temp.id(text),
  pg_temp.sku(), pg_temp.sale(int, int, float8, float8), pg_temp.carried() to authenticated;

-- Fixture: lp.agent2 carries 50 pcs via request -> approve -> OTP handover.
select pg_temp.as_user('lp.agent2');
insert into t select 'req', app.request_stock(pg_temp.ref('wh', 'Ikeja Main'),
  jsonb_build_array(jsonb_build_object('sku_id', pg_temp.sku(), 'uom_code', 'piece', 'uom_qty', 50))), null;
select pg_temp.as_user('lp.bm.ikeja');
insert into t select 'ship', app.decide_stock_request(pg_temp.id('req'), true), null;
select pg_temp.as_user('lp.wh.ikeja');
insert into t select 'c', app.start_handover(pg_temp.id('ship')), null;
select pg_temp.as_owner();
update t set j = jsonb_build_object('code', (select code from app.issue_otp_code(pg_temp.id('c')))) where name = 'c';
select pg_temp.as_user('lp.wh.ikeja');
select app.verify_otp(pg_temp.id('c'), (select j->>'code' from t where name = 'c'));

-- Device + airplane-mode batch -----------------------------------------------------------------------
select pg_temp.as_user('lp.agent2');
select is(app.register_device('aaaaaaaa-0000-4000-8000-000000000001', pg_temp.ref('org', 'lagos-prime')), 0::bigint, 'device registered at seq 0');
insert into t select 'batch1', null, jsonb_build_array(
  jsonb_build_object('event_id', 'bbbbbbbb-0000-4000-8000-000000000001', 'seq', 1, 'type', 'visit.checked_in', 'lat', 6.5800, 'lng', 3.3480,
                     'accuracy_m', 6, 'client_ts', '2026-10-22T09:55:00Z', 'payload', jsonb_build_object('retailer_id', pg_temp.ref('org', 'retailer-07'))),
  pg_temp.sale(2, 20), pg_temp.sale(3, 40), pg_temp.sale(4, 5));
insert into t select 'res1', null, app.sync_agent_events('aaaaaaaa-0000-4000-8000-000000000001', (select j from t where name = 'batch1'));
select is((select array_agg(e->>'status' order by ord) from t, jsonb_array_elements(j) with ordinality x(e, ord) where name = 'res1'),
          array['accepted', 'accepted', 'rejected', 'accepted'], 'visit + 20 accepted, 40 rejected (only 30 carried), 5 accepted');
select is((select j->2->>'reason' from t where name = 'res1'), 'insufficient_carried_stock', 'rejection carries a reason code');
select is(pg_temp.carried(), 25, 'carried = 50 - 20 - 5');
select pg_temp.as_owner();
select is((select count(*)::int from public.review_items where reason = 'insufficient_carried_stock' and status = 'open'
           and agent_user_id = pg_temp.uid('lp.agent2')), 1, 'the rejected sale is in the review queue, not dropped');
select is((select geofence_ok from public.agent_visits where event_id = 'bbbbbbbb-0000-4000-8000-000000000001'), true, 'visit recorded with geofence result');

select pg_temp.as_user('lp.agent2');
select is((select array_agg(e->>'status') from jsonb_array_elements(app.sync_agent_events('aaaaaaaa-0000-4000-8000-000000000001',
             (select j from t where name = 'batch1'))) e), array['duplicate', 'duplicate', 'duplicate', 'duplicate'],
          're-sending the whole batch is idempotent');
select is(pg_temp.carried(), 25, 'nothing applied twice');
select pg_temp.as_owner();
select is((select count(*)::int from public.push_sales where shipment_id = pg_temp.id('ship')), 2, 'exactly two sales exist');

-- Seq gap, geofence, foreign device ----------------------------------------------------------------
select pg_temp.as_user('lp.agent2');
select is(app.sync_agent_events('aaaaaaaa-0000-4000-8000-000000000001', jsonb_build_array(pg_temp.sale(6, 1)))->0->>'status',
          'deferred', 'seq 6 before seq 5 is deferred (seq_gap), not validated');
select is((select array_agg(e->>'status') from jsonb_array_elements(app.sync_agent_events('aaaaaaaa-0000-4000-8000-000000000001',
             jsonb_build_array(pg_temp.sale(6, 1), pg_temp.sale(5, 2, 6.60, 3.40)))) e),
          array['rejected', 'accepted'], 'once seq 5 arrives both apply in order: 5 rejected (outside geofence), 6 accepted');
select is(pg_temp.carried(), 24, 'only the in-geofence sale moved stock');
select pg_temp.as_user('lp.agent1');
select throws_ok($$ select app.sync_agent_events('aaaaaaaa-0000-4000-8000-000000000001', '[]') $$, 'SOL03', null,
                 'another agent cannot use this device');
select throws_ok($$ select app.register_device('aaaaaaaa-0000-4000-8000-000000000001', pg_temp.ref('org', 'lagos-prime')) $$, 'SOL03', null,
                 'nor register it');

-- Review queue ---------------------------------------------------------------------------------------
select pg_temp.as_owner();
insert into t select 'item_stock', (select id from public.review_items where reason = 'insufficient_carried_stock' and agent_user_id = pg_temp.uid('lp.agent2')), null;
insert into t select 'item_geo', (select id from public.review_items where reason = 'outside_geofence' and agent_user_id = pg_temp.uid('lp.agent2')), null;
select pg_temp.as_user('lp.agent2');
select throws_ok($$ select app.review_accept_into_variance(pg_temp.id('item_stock'), 'x') $$, 'SOL03', null, 'agents cannot review their own events');
select pg_temp.as_user('lp.bm.ikeja');
select is((app.review_accept_into_variance(pg_temp.id('item_stock'), 'agent had 15 extra pcs from a missed handover')->>'unrecorded_pieces')::int,
          16, 'accept into variance: 40 sold vs 24 carried -> 16 pcs unrecorded stock');
select is(pg_temp.carried(), 0, 'the real sale is recorded; carried stock never went negative');
select pg_temp.as_owner();
select results_eq($$ select kind, qty_pieces, status from public.variance_cases where shipment_id = pg_temp.id('ship') $$,
                  $$ values ('unrecorded_stock', 16, 'pending') $$, 'a pending unrecorded_stock case is raised against the agent');
select is((select count(*)::int from public.push_sales where shipment_id = pg_temp.id('ship')), 4, 'the accepted sale exists once (4 sales total)');
select pg_temp.as_user('lp.bm.ikeja');
select lives_ok($$ select app.review_dismiss(pg_temp.id('item_geo'), 'agent confirmed the sale did not happen') $$, 'outside-geofence item dismissed');
select throws_ok($$ select app.review_dismiss(pg_temp.id('item_geo'), 'again') $$, 'SOL04', null, 'a decision is final');

-- Return + close blocking + resolution ---------------------------------------------------------------
select pg_temp.as_user('lp.wh.ikeja');
insert into t select 'r', app.start_push_return(pg_temp.id('ship'), '[]'), null;
select pg_temp.as_owner();
update t set j = jsonb_build_object('code', (select code from app.issue_otp_code(pg_temp.id('r')))) where name = 'r';
select pg_temp.as_user('lp.wh.ikeja');
select is(app.verify_otp(pg_temp.id('r'), (select j->>'code' from t where name = 'r'))->>'result', 'reconciling',
          'nothing left to return, but the pending case keeps the shipment open');
select pg_temp.as_user('lp.bm.ikeja');
select throws_ok($$ select app.close_shipment(pg_temp.id('ship')) $$, 'SOL04', null, 'close is blocked while the case is pending');
select throws_ok($$ select app.resolve_variance((select id from public.variance_cases where shipment_id = pg_temp.id('ship')), 'charge_agent', 'x') $$,
                 'SOL05', null, 'unrecorded stock is resolved by link_handover or write_off, not by charging');
select is(app.resolve_variance((select id from public.variance_cases where shipment_id = pg_temp.id('ship')), 'link_handover', 'found the missed handover slip'),
          'closed', 'linking the missed handover closes the shipment');
select pg_temp.as_owner();
select is((select sum(on_hand_delta)::int from public.stock_movements m join public.stock_locations sl on sl.id = m.location_id
           where sl.user_id = pg_temp.uid('lp.agent2') and m.ref_kind = 'variance_case' and m.movement_type = 'adjustment'), 0,
          'at the agent: the unrecorded_stock placeholder (+16) and its reversal (-16) net to zero');
select is_empty($$ select * from app.check_stock_projection() union all select null, null, null, null, null, null
                   from app.check_stock_conservation() $$, 'stock projection and conservation hold');
select is_empty($$ select * from app.check_money_projection() $$, 'money projection holds');

select * from finish();
rollback;
