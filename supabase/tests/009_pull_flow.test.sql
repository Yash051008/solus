-- Phase 4 pull flow as real users: routing (spec example), split decision, cancellation, idempotency,
-- batching/dispatch/acceptance, e-POD with partial outcomes, cumulative invoicing, returns, shipment
-- blocking, transfer shortages, adjustment SoD, and every ledger invariant afterwards.
begin;
create extension if not exists pgtap with schema extensions;
select plan(39);

create temp table ids as select split_part(email, '@', 1) as handle, id from auth.users;
create temp table ref_ids as
            select 'org' as kind, slug as name, id from public.organisations
  union all select 'wh', name, id from public.warehouses;
create function pg_temp.uid(h text) returns uuid language sql as $$ select id from pg_temp.ids where handle = h $$;
create function pg_temp.org(n text) returns uuid language sql as $$ select id from pg_temp.ref_ids where kind = 'org' and name = n $$;
create function pg_temp.wh(n text) returns uuid language sql as $$ select id from pg_temp.ref_ids where kind = 'wh' and name = n $$;
create function pg_temp.as_user(h text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(h), 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function pg_temp.as_owner() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

-- Fixture SKU (carton = 10 pcs): Ikeja Main (nearest to retailer-01, ~1.7 km) holds 20 ctn,
-- Lekki Depot (~28 km) holds 40 ctn. Spec example: order 30 ctn.
create temp table fx (sku uuid, ikeja_loc uuid, lekki_loc uuid);
insert into public.skus (manufacturer_org_id, brand_id, code, name)
select b.manufacturer_org_id, b.id, 'ROUTE-TEST', 'Routing test SKU' from public.brands b where b.name = 'Sunrise Home';
insert into public.sku_uom (sku_id, uom_code, pieces_per_uom) select id, 'carton', 10 from public.skus where code = 'ROUTE-TEST';
insert into fx select (select id from public.skus where code = 'ROUTE-TEST'),
                      app.warehouse_location(pg_temp.wh('Ikeja Main')), app.warehouse_location(pg_temp.wh('Lekki Depot'));
select app.post_stock_movement(gen_random_uuid(), 'receipt', fx.ikeja_loc, fx.sku, 200) from fx;
select app.post_stock_movement(gen_random_uuid(), 'receipt', fx.lekki_loc, fx.sku, 400) from fx;
create temp table o (name text primary key, id uuid, result jsonb);
grant select, insert, update on fx, o, ids, ref_ids to authenticated;
grant execute on function pg_temp.uid(text), pg_temp.org(text), pg_temp.wh(text), pg_temp.as_user(text), pg_temp.as_owner() to authenticated;

create function pg_temp.lines(ctn int) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('sku_id', (select sku from pg_temp.fx), 'uom_code', 'carton', 'uom_qty', ctn))
$$;
grant execute on function pg_temp.lines(int) to authenticated;

select pg_temp.as_user('lp.admin');
select lives_ok($$ select app.publish_price_list(pg_temp.org('lagos-prime'), 'Routing test', now(),
  jsonb_build_array(jsonb_build_object('sku_id', (select sku from pg_temp.fx), 'uom_code', 'carton', 'price_kobo', '1000000'))) $$,
  'admin publishes a price for the fixture SKU (N10,000 per carton)');

-- Routing ---------------------------------------------------------------------------------------
select pg_temp.as_user('retailer01');
insert into o select 'split', null, app.place_order(pg_temp.org('lagos-prime'), pg_temp.org('retailer-01'), pg_temp.lines(30), 'test:order:split01');
update o set id = (result->>'order_id')::uuid where name = 'split';
select is((select result->>'status' from o where name = 'split'), 'awaiting_split_decision',
          '30 ctn: nearest (20 ctn) cannot cover, next (40 ctn) is beyond the 15 km penalty -> split offered');
select pg_temp.as_owner();
select results_eq(
  $$ select routing_reason, jsonb_array_length(routing_decision->'candidates'),
            routing_decision->'options' ? 'single', routing_decision->'options' ? 'split'
     from public.orders where id = (select id from o where name = 'split') $$,
  $$ values ('distance_penalty_exceeds_threshold', 2, true, true) $$,
  'decision + reason stored: both candidates, single and split options');
select is((select count(*)::int from public.stock_movements where ref_kind = 'order' and ref_id = (select id from o where name = 'split')),
          0, 'nothing reserved while awaiting the decision');
select is((select uom_price_kobo from public.order_lines where order_id = (select id from o where name = 'split')),
          1000000::bigint, 'line price comes from the current price list, never the client');

select pg_temp.as_user('lp.bm.lekki');
select throws_ok($$ select app.decide_split((select id from o where name = 'split'), 'split') $$, 'SOL03', null,
                 'only the manager of the shop''s branch (Ikeja) decides');
select pg_temp.as_user('lp.bm.ikeja');
select lives_ok($$ select app.decide_split((select id from o where name = 'split'), 'split') $$, 'Ikeja manager accepts the split');
select pg_temp.as_owner();
select results_eq(
  $$ select w.name, sum(a.qty_pieces)::int from public.order_allocations a join public.warehouses w on w.id = a.warehouse_id
     where a.order_id = (select id from o where name = 'split') group by w.name order by w.name $$,
  $$ values ('Ikeja Main', 200), ('Lekki Depot', 100) $$,
  'split allocates nearest first: 20 ctn Ikeja + 10 ctn Lekki');

select pg_temp.as_user('retailer01');
select lives_ok($$ select app.cancel_order((select id from o where name = 'split'), 'changed my mind') $$, 'retailer cancels before dispatch');
select pg_temp.as_owner();
select results_eq($$ select sum(reserved)::int from public.stock_balances, fx where sku_id = fx.sku $$, $$ values (0) $$,
                  'cancellation releases every reservation');

update public.organisations set split_threshold_m = 50000 where slug = 'lagos-prime';
select pg_temp.as_user('retailer01');
insert into o select 'single', null, app.place_order(pg_temp.org('lagos-prime'), pg_temp.org('retailer-01'), pg_temp.lines(30), 'test:order:single1');
update o set id = (result->>'order_id')::uuid where name = 'single';
select pg_temp.as_owner();
select results_eq(
  $$ select o.status::text, o.routing_reason, w.name from public.orders o
     join public.order_allocations a on a.order_id = o.id join public.warehouses w on w.id = a.warehouse_id
     where o.id = (select id from pg_temp.o where name = 'single') $$,
  $$ values ('reserved', 'nearest_full_cover', 'Lekki Depot') $$,
  'with a 50 km threshold the nearest full-cover warehouse (Lekki) is chosen');

select pg_temp.as_user('retailer01');
select is((app.place_order(pg_temp.org('lagos-prime'), pg_temp.org('retailer-01'), pg_temp.lines(30), 'test:order:single1')->>'order_id')::uuid,
          (select id from o where name = 'single'), 'replaying the idempotency key returns the same order');
select is(app.place_order(pg_temp.org('lagos-prime'), pg_temp.org('retailer-01'), pg_temp.lines(1000), 'test:order:toobig')->>'status',
          'rejected', 'an order the network cannot cover is rejected (and kept, with its reason)');
select pg_temp.as_user('lp.agent3');
select throws_ok($$ select app.place_order(pg_temp.org('lagos-prime'), pg_temp.org('retailer-01'), pg_temp.lines(1), 'test:order:agent3x') $$,
                 'SOL03', null, 'an agent outside the shop''s territory cannot order for it');
select pg_temp.as_user('retailer13');
select throws_ok($$ select app.place_order(pg_temp.org('lagos-prime'), pg_temp.org('retailer-01'), pg_temp.lines(1), 'test:order:r13xxx') $$,
                 'SOL03', null, 'another shop cannot order on this shop''s behalf');

-- Batch, pack, dispatch, accept ---------------------------------------------------------------------
select pg_temp.as_user('lp.wh.ikeja');
select throws_ok($$ select app.create_batch(pg_temp.wh('Lekki Depot'), array[(select id from o where name = 'single')]) $$,
                 'SOL03', null, 'Ikeja staff cannot batch at Lekki');
select pg_temp.as_user('lp.wh.lekki');
insert into o select 'batch', app.create_batch(pg_temp.wh('Lekki Depot'), array[(select id from o where name = 'single')]), null;
select throws_ok($$ select app.dispatch_batch((select id from o where name = 'batch'), pg_temp.uid('lp.driver1')) $$,
                 'SOL04', null, 'an unpacked batch cannot be dispatched');
select lives_ok($$ select app.mark_batch_packed((select id from o where name = 'batch')) $$, 'batch packed');
insert into o select 'ship', app.dispatch_batch((select id from o where name = 'batch'), pg_temp.uid('lp.driver1')), null;
select pg_temp.as_user('lp.agent1');
select throws_ok($$ select app.accept_dispatch((select id from o where name = 'ship')) $$, 'SOL03', null,
                 'only the assigned carrier can accept');
select pg_temp.as_user('lp.driver1');
select lives_ok($$ select app.accept_dispatch((select id from o where name = 'ship')) $$, 'driver accepts in their own session');
select pg_temp.as_owner();
select results_eq(
  $$ select (select on_hand from public.stock_balances b, fx where b.location_id = fx.lekki_loc and b.sku_id = fx.sku),
            (select reserved from public.stock_balances b, fx where b.location_id = fx.lekki_loc and b.sku_id = fx.sku),
            (select b.on_hand from public.stock_balances b join public.stock_locations sl on sl.id = b.location_id, fx
              where sl.user_id = pg_temp.uid('lp.driver1') and b.sku_id = fx.sku) $$,
  $$ values (100, 0, 300) $$,
  'acceptance releases the reservation and hands 300 pcs from Lekki to the driver');

-- e-POD -------------------------------------------------------------------------------------------
create temp table d as
select (select id from o where name = 'ship') as ship, (select id from o where name = 'single') as ord,
       (select id from public.order_allocations where order_id = (select id from o where name = 'single')) as alloc,
       (select id from o where name = 'ship')::text || '/' || (select id from o where name = 'single')::text || '/pod.jpg' as photo;
grant select on d to authenticated;
select pg_temp.as_user('lp.driver1');
select throws_ok($$ select app.record_delivery(d.ship, d.ord,
                      jsonb_build_array(jsonb_build_object('allocation_id', d.alloc, 'delivered', 291, 'refused', 5, 'damaged', 3, 'missing', 1)),
                      6.6200, 3.3450, 8, d.photo, 'Shop Owner', 'test:delivery:0001') from d $$,
                 'SOL05', 'the delivery photo has not been uploaded', 'no photo, no delivery');
select pg_temp.as_owner();
insert into storage.objects (bucket_id, name, owner_id) select 'epod', photo, pg_temp.uid('lp.driver1')::text from d;
select pg_temp.as_user('lp.driver1');
select throws_ok($$ select app.record_delivery(d.ship, d.ord,
                      jsonb_build_array(jsonb_build_object('allocation_id', d.alloc, 'delivered', 291, 'refused', 5, 'damaged', 3, 'missing', 0)),
                      6.6200, 3.3450, 8, d.photo, 'Shop Owner', 'test:delivery:0001') from d $$,
                 'SOL05', null, 'outcomes must add up to the allocated quantity');
select is((select app.record_delivery(d.ship, d.ord,
             jsonb_build_array(jsonb_build_object('allocation_id', d.alloc, 'delivered', 291, 'refused', 5, 'damaged', 3, 'missing', 1)),
             6.6200, 3.3450, 8, d.photo, 'Shop Owner', 'test:delivery:0001') ->> 'invoiced_kobo' from d),
          '29100000', 'invoice = 291/300 of N300,000 = N291,000.00 (exact, via round_div)');
select pg_temp.as_owner();
select results_eq(
  $$ select o.status::text, dl.geofence_ok, (select sum(-amount_kobo) from public.ledger_entries e
       join public.accounts a on a.id = e.account_id where e.journal_id = dl.journal_id and a.account_type = 'sales_revenue')
     from public.orders o join public.deliveries dl on dl.order_id = o.id where o.id = (select ord from d) $$,
  $$ values ('partially_delivered', true, 29100000::numeric) $$,
  'order partially delivered, geofence passed, revenue journal posted');

-- Return + reconciliation -------------------------------------------------------------------------
select pg_temp.as_user('lp.driver1');
select throws_ok($$ select app.start_return((select ship from d), jsonb_build_array(jsonb_build_object('sku_id', (select sku from fx), 'qty_pieces', 5))) $$,
                 'SOL03', null, 'the driver cannot count their own return');
select pg_temp.as_user('lp.wh.lekki');
select lives_ok($$ select app.start_return((select ship from d), jsonb_build_array(jsonb_build_object('sku_id', (select sku from fx), 'qty_pieces', 5))) $$,
                'warehouse counts the 5 refused pieces');
select pg_temp.as_user('lp.driver1');
select is(app.confirm_return((select ship from d)), 'reconciling',
          'the 1 missing piece keeps the shipment open for variance review (not closed)');
select pg_temp.as_owner();
select results_eq($$ select picked_up, sold, returned, damaged, remaining from public.v_shipment_reconciliation
                     where shipment_id = (select ship from d) $$,
                  $$ values (300::bigint, 291::bigint, 5::bigint, 3::bigint, 1::bigint) $$,
                  'picked_up 300 = sold 291 + returned 5 + damaged 3 + remaining 1');
select pg_temp.as_user('lp.bm.lekki');
select throws_ok($$ select app.close_shipment((select ship from d)) $$, 'SOL04', null,
                 'a shipment cannot close while the carrier still holds unreconciled stock');

-- Transfer shortage + adjustment SoD --------------------------------------------------------------
select pg_temp.as_user('lp.bm.ikeja');
insert into o select 'xfer', app.create_transfer(pg_temp.wh('Ikeja Main'), pg_temp.wh('Lekki Depot'), pg_temp.lines(1)), null;
select pg_temp.as_user('lp.wh.ikeja');
select app.dispatch_transfer((select id from o where name = 'xfer'));
select pg_temp.as_user('lp.wh.lekki');
select is(app.receive_transfer((select id from o where name = 'xfer'),
            jsonb_build_array(jsonb_build_object('sku_id', (select sku from fx), 'received', 8, 'damaged', 1))),
          'short', '8 received + 1 damaged of 10: transfer is short');
select throws_ok($$ select app.resolve_transfer_shortage((select id from o where name = 'xfer'), 'lost') $$, 'SOL03', null,
                 'warehouse staff cannot write off a transit loss');
select pg_temp.as_user('lp.bm.lekki');
select lives_ok($$ select app.resolve_transfer_shortage((select id from o where name = 'xfer'), 'fell off the truck at Ojota') $$,
                'Lekki manager resolves the shortage');
select pg_temp.as_owner();
select is((select coalesce(sum(in_transit), 0)::int from public.v_transfer_in_transit where transfer_id = (select id from o where name = 'xfer')),
          0, 'nothing left in transit');

select pg_temp.as_user('lp.bm.lekki');
insert into o select 'adj', app.request_adjustment(pg_temp.wh('Lekki Depot'), (select sku from fx), -3, 'cycle count'), null;
select throws_ok($$ select app.decide_adjustment((select id from o where name = 'adj'), true) $$, 'SOL03', null,
                 'nobody approves their own adjustment');

-- Invariants after the whole flow -------------------------------------------------------------------
select pg_temp.as_owner();
select is_empty($$ select * from app.check_stock_projection() $$, 'stock projection = ledger');
select is_empty($$ select * from app.check_stock_conservation() $$, 'stock conserved: receipts - sales - damage - adjustments - in transit');
select is_empty($$ select * from app.check_money_projection() $$, 'account balances = ledger');
select is_empty($$ select * from app.check_journals_balanced() $$, 'every journal balances per book');

select * from finish();
rollback;
