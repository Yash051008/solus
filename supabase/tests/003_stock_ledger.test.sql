-- Inventory ledger invariants (hard rules 1 and 3), proven against the real schema.
begin;
create extension if not exists pgtap with schema extensions;
select plan(31);

create temp table fx as
select
  (select sl.id from public.stock_locations sl join public.warehouses w on w.id = sl.warehouse_id
    where w.name = 'Ikeja Main') as wh,
  (select w.id from public.warehouses w where w.name = 'Ikeja Main') as wh_id,
  (select w.id from public.warehouses w where w.name = 'Wuse Central') as other_dist_wh_id,
  (select sl.id from public.stock_locations sl join auth.users u on u.id = sl.user_id
    where u.email = 'lp.agent1@solus.test') as agent,
  (select id from public.skus where code = 'NDL-CHK-70G') as sku,   -- 40/carton, Ikeja holds 50 ctn = 2000
  (select id from public.skus where code = 'BEV-MLT-330ML') as sku2, -- 24/carton, Ikeja holds 1200
  (select id from public.organisations where slug = 'lagos-prime') as dist,
  (select id from public.organisations where slug = 'retailer-01') as retailer;

select is((select on_hand from public.stock_balances, fx where location_id = fx.wh and sku_id = fx.sku),
          2000, 'seed: Ikeja Main holds 50 cartons x 40 = 2000 pieces of NDL-CHK-70G');

-- Append-only ledger -------------------------------------------------------------------------
select throws_ok($$ update public.stock_movements set qty = qty + 1 $$, 'SOL06', null,
                 'stock_movements: UPDATE rejected');
select throws_ok($$ delete from public.stock_movements $$, 'SOL06', null,
                 'stock_movements: DELETE rejected');
select throws_ok($$ truncate public.stock_movements cascade $$, 'SOL06', null,
                 'stock_movements: TRUNCATE rejected');

-- Projection writable only by the ledger trigger (even the owner role cannot write it) ---------
select throws_ok($$ update public.stock_balances set on_hand = on_hand + 1 $$, 'SOL06', null,
                 'stock_balances: direct UPDATE rejected even for the table owner');
select throws_ok($$ insert into public.stock_balances (location_id, sku_id, org_id, location_kind, on_hand)
                    select fx.agent, fx.sku, fx.dist, 'agent', 5 from fx $$, 'SOL06', null,
                 'stock_balances: direct INSERT rejected');
select throws_ok($$ delete from public.stock_balances $$, 'SOL06', null,
                 'stock_balances: direct DELETE rejected');

-- Movement type vs location kind ---------------------------------------------------------------
select throws_ok($$ select app.post_stock_movement(gen_random_uuid(), 'sale', fx.wh, fx.sku, 1) from fx $$,
                 'SOL05', null, 'sale at a warehouse is rejected');
select throws_ok($$ select app.post_stock_movement(gen_random_uuid(), 'reserve', fx.agent, fx.sku, 1) from fx $$,
                 'SOL05', null, 'reserve at an agent location is rejected');
select throws_ok($$ select app.post_stock_movement(gen_random_uuid(), 'receipt', fx.agent, fx.sku, 1) from fx $$,
                 'SOL05', null, 'receipt at an agent location is rejected');
select throws_ok($$ insert into public.stock_movements
                      (movement_group_id, movement_type, location_id, org_id, sku_id, qty, on_hand_delta, reserved_delta)
                    select gen_random_uuid(), 'sale', fx.agent, fx.dist, fx.sku, 5, 5, 0 from fx $$,
                 '23514', null, 'a sale row that adds stock violates stock_movements_delta_matches_type');

-- Negative stock and oversell are impossible at the database level ----------------------------
select throws_ok($$ select app.post_stock_movement(gen_random_uuid(), 'damage', fx.wh, fx.sku, 2001) from fx $$,
                 '23514', null, 'damaging more than on_hand violates stock_balances_on_hand_nonnegative');
select throws_ok($$ select app.post_stock_movement(gen_random_uuid(), 'reserve', fx.wh, fx.sku, 2001) from fx $$,
                 '23514', null, 'reserving more than on_hand violates stock_balances_reserved_within_on_hand');
select throws_ok($$ select app.post_stock_movement(gen_random_uuid(), 'sale', fx.agent, fx.sku2, 1) from fx $$,
                 '23514', null, 'selling from an agent who carries nothing is rejected');

-- Two-legged handover --------------------------------------------------------------------------
select lives_ok($$
  do $d$
  declare g uuid := gen_random_uuid(); f record;
  begin
    select * into f from pg_temp.fx;
    perform app.post_stock_movement(g, 'handover', f.wh, f.sku, 100, -1, 'test', g);
    perform app.post_stock_movement(g, 'handover', f.agent, f.sku, 100, 1, 'test', g);
    set constraints all immediate;
  end $d$ $$, 'balanced handover warehouse(-100) -> agent(+100) commits');

select is((select on_hand from public.stock_balances, fx where location_id = fx.agent and sku_id = fx.sku),
          100, 'agent now carries 100 pieces');
select is((select on_hand from public.stock_balances, fx where location_id = fx.wh and sku_id = fx.sku),
          1900, 'warehouse now holds 1900 pieces');

select throws_ok($$
  do $d$
  declare g uuid := gen_random_uuid(); f record;
  begin
    select * into f from pg_temp.fx;
    perform app.post_stock_movement(g, 'handover', f.wh, f.sku, 10, -1, 'test', g);
    set constraints all immediate;
  end $d$ $$, 'SOL06', null, 'a one-legged handover fails the group-balance check at commit');

select throws_ok($$ select app.post_stock_movement(gen_random_uuid(), 'handover', fx.wh, fx.sku, 10, 1) from fx $$,
                 'SOL05', null, 'a handover that adds stock to the warehouse is rejected');

select throws_ok($$ select app.post_stock_movement(gen_random_uuid(), 'sale', fx.agent, fx.sku, 101) from fx $$,
                 '23514', null, 'agent cannot sell more than carried (101 > 100)');

-- Orders: carton -> piece conversion happens in the database ------------------------------------
insert into public.orders (id, distributor_org_id, retailer_org_id, status)
select '11111111-1111-4111-8111-111111111111', fx.dist, fx.retailer, 'placed' from fx;
insert into public.order_lines (order_id, sku_id, uom_code, uom_qty, uom_price_kobo)
select '11111111-1111-4111-8111-111111111111', fx.sku, 'carton', 2, 970000 from fx;

select is((select qty_pieces from public.order_lines where order_id = '11111111-1111-4111-8111-111111111111'),
          80, '2 cartons x 40 converted to 80 pieces by the database');
select throws_ok($$ insert into public.order_lines (order_id, sku_id, uom_code, uom_qty, qty_pieces, uom_price_kobo)
                    select '11111111-1111-4111-8111-111111111111', fx.sku, 'carton', 1, 41, 970000 from fx $$,
                 'SOL05', null, 'caller-supplied qty_pieces that disagrees with sku_uom is rejected');
select throws_ok($$ update public.order_lines set uom_qty = 3
                    where order_id = '11111111-1111-4111-8111-111111111111' $$,
                 'SOL04', null, 'order line quantities are immutable');
select throws_ok($$ update public.sku_uom set pieces_per_uom = 50 where uom_code = 'carton' $$,
                 'SOL04', null, 'conversion factors are immutable');

-- Atomic reservation -------------------------------------------------------------------------
select lives_ok($$ select app.reserve_order('11111111-1111-4111-8111-111111111111', fx.wh_id) from fx $$,
                'reserve_order reserves an order that fits');
select results_eq(
  $$ select reserved, available from public.stock_balances, fx where location_id = fx.wh and sku_id = fx.sku $$,
  $$ values (80, 1820) $$,
  'warehouse shows 80 reserved, 1820 available');
select throws_ok($$ select app.reserve_order('11111111-1111-4111-8111-111111111111', fx.wh_id) from fx $$,
                 'SOL04', null, 'an order cannot be reserved twice');

-- All-or-nothing: second line cannot be covered -> nothing reserved, order still placed
insert into public.orders (id, distributor_org_id, retailer_org_id, status)
select '22222222-2222-4222-8222-222222222222', fx.dist, fx.retailer, 'placed' from fx;
insert into public.order_lines (order_id, sku_id, uom_code, uom_qty, uom_price_kobo)
select '22222222-2222-4222-8222-222222222222'::uuid, fx.sku2, 'carton', 1, 1164000 from fx
union all
select '22222222-2222-4222-8222-222222222222', fx.sku, 'carton', 100, 970000 from fx;  -- 4000 > 1820

select throws_ok($$ select app.reserve_order('22222222-2222-4222-8222-222222222222', fx.wh_id) from fx $$,
                 'SOL01', 'insufficient_stock', 'an order that cannot be fully covered raises insufficient_stock');
select is((select count(*)::int from public.stock_movements
           where ref_kind = 'order' and ref_id = '22222222-2222-4222-8222-222222222222'),
          0, 'no partial reservation was written for the failed order');

select throws_ok($$ select app.reserve_order('22222222-2222-4222-8222-222222222222', fx.other_dist_wh_id) from fx $$,
                 'SOL05', null, 'cannot reserve at another distributor''s warehouse');

-- Rebuild from ledger -------------------------------------------------------------------------
select is_empty($$ select * from app.check_stock_projection() $$,
                'stock_balances rebuilt from stock_movements matches the projection exactly');

select * from finish();
rollback;
