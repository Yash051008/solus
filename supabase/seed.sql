-- Local development seed. SYNTHETIC DATA ONLY (ADR-0001): fictional companies, people and phones.
-- 1 platform, 1 manufacturer, 2 distributors (3 branches, 5 territories, 3 warehouses),
-- 5 agents, 2 drivers, 20 retailers, 15 SKUs, opening stock via the ledger, wallet top-ups via journals.
--
-- Test credentials (local stack only): every seeded user signs in with password  SolusDev-2026!
-- Emails are <handle>@solus.test (see the users list below).

-- Helpers live in pg_temp: they vanish with the session and never reach a migration.
create function pg_temp.point(p_lat double precision, p_lng double precision)
returns extensions.geography
language sql immutable
as $$ select extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography $$;

create function pg_temp.org(p_slug text) returns uuid language sql stable
as $$ select id from public.organisations where slug = p_slug $$;

create function pg_temp.usr(p_handle text) returns uuid language sql stable
as $$ select id from auth.users where email = p_handle || '@solus.test' $$;

create function pg_temp.branch(p_org text, p_name text) returns uuid language sql stable
as $$ select id from public.branches where org_id = pg_temp.org(p_org) and name = p_name $$;

create function pg_temp.territory(p_org text, p_name text) returns uuid language sql stable
as $$ select id from public.territories where org_id = pg_temp.org(p_org) and name = p_name $$;

create function pg_temp.make_user(p_handle text, p_full_name text, p_phone text)
returns uuid
language plpgsql
as $$
declare
  v_id uuid := gen_random_uuid();
  v_email text := p_handle || '@solus.test';
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
    extensions.crypt('SolusDev-2026!', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''
  );
  insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_id, v_id::text, 'email',
          jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true), now(), now(), now());
  insert into public.profiles (user_id, full_name, phone_e164) values (v_id, p_full_name, p_phone);
  return v_id;
end;
$$;

create function pg_temp.member(p_handle text, p_org text, p_role public.member_role,
                               p_branch text default null, p_territory text default null)
returns void
language sql
as $$
  insert into public.memberships (user_id, org_id, org_kind, role, branch_id, territory_id, status)
  select pg_temp.usr(p_handle), o.id, o.kind, p_role,
         case when p_branch is null then null else pg_temp.branch(p_org, p_branch) end,
         case when p_territory is null then null else pg_temp.territory(p_org, p_territory) end,
         'active'
  from public.organisations o where o.slug = p_org
$$;

-- Organisations -------------------------------------------------------------------------------
insert into public.organisations (kind, name, slug, status, location, split_threshold_m) values
  ('platform',     'Solus Platform',                    'solus-platform', 'active', null, null),
  ('manufacturer', 'Sunrise Consumer Goods Plc',        'sunrise',        'active', null, null),
  ('distributor',  'Lagos Prime Distribution Ltd',      'lagos-prime',    'active', pg_temp.point(6.6018, 3.3515), 15000),
  ('distributor',  'Abuja Central Distributors Ltd',    'abuja-central',  'active', pg_temp.point(9.0765, 7.4986), 15000);

insert into public.supply_relationships (manufacturer_org_id, distributor_org_id) values
  (pg_temp.org('sunrise'), pg_temp.org('lagos-prime')),
  (pg_temp.org('sunrise'), pg_temp.org('abuja-central'));

-- Branches, territories, warehouses -----------------------------------------------------------
insert into public.branches (org_id, name) values
  (pg_temp.org('lagos-prime'), 'Ikeja'),
  (pg_temp.org('lagos-prime'), 'Lekki'),
  (pg_temp.org('abuja-central'), 'Wuse');

insert into public.territories (org_id, branch_id, name) values
  (pg_temp.org('lagos-prime'),   pg_temp.branch('lagos-prime', 'Ikeja'),  'Ikeja North'),
  (pg_temp.org('lagos-prime'),   pg_temp.branch('lagos-prime', 'Ikeja'),  'Ikeja South'),
  (pg_temp.org('lagos-prime'),   pg_temp.branch('lagos-prime', 'Lekki'),  'Lekki Phase 1'),
  (pg_temp.org('abuja-central'), pg_temp.branch('abuja-central', 'Wuse'), 'Wuse Zone 4'),
  (pg_temp.org('abuja-central'), pg_temp.branch('abuja-central', 'Wuse'), 'Garki');

insert into public.warehouses (org_id, branch_id, name, location) values
  (pg_temp.org('lagos-prime'),   pg_temp.branch('lagos-prime', 'Ikeja'),  'Ikeja Main',   pg_temp.point(6.6050, 3.3490)),
  (pg_temp.org('lagos-prime'),   pg_temp.branch('lagos-prime', 'Lekki'),  'Lekki Depot',  pg_temp.point(6.4400, 3.5300)),
  (pg_temp.org('abuja-central'), pg_temp.branch('abuja-central', 'Wuse'), 'Wuse Central', pg_temp.point(9.0579, 7.4951));

-- Users and memberships -----------------------------------------------------------------------
select pg_temp.make_user(h, n, p) from (values
  ('platform.admin', 'Platform Admin',           '+2348000000001'),
  ('sunrise.admin',  'Sunrise Admin',            '+2348000000002'),
  ('lp.admin',       'Lagos Prime Admin',        '+2348000000010'),
  ('lp.bm.ikeja',    'Ikeja Branch Manager',     '+2348000000011'),
  ('lp.bm.lekki',    'Lekki Branch Manager',     '+2348000000012'),
  ('lp.wh.ikeja',    'Ikeja Warehouse Staff',    '+2348000000013'),
  ('lp.wh.lekki',    'Lekki Warehouse Staff',    '+2348000000014'),
  ('lp.agent1',      'Agent Ikeja North',        '+2348000000015'),
  ('lp.agent2',      'Agent Ikeja South',        '+2348000000016'),
  ('lp.agent3',      'Agent Lekki',              '+2348000000017'),
  ('lp.driver1',     'Driver Ikeja',             '+2348000000018'),
  ('ac.admin',       'Abuja Central Admin',      '+2348000000020'),
  ('ac.bm.wuse',     'Wuse Branch Manager',      '+2348000000021'),
  ('ac.wh.wuse',     'Wuse Warehouse Staff',     '+2348000000022'),
  ('ac.agent1',      'Agent Wuse Zone 4',        '+2348000000023'),
  ('ac.agent2',      'Agent Garki',              '+2348000000024'),
  ('ac.driver1',     'Driver Wuse',              '+2348000000025')
) as u(h, n, p);

select pg_temp.member('platform.admin', 'solus-platform', 'platform_admin');
select pg_temp.member('sunrise.admin',  'sunrise',        'manufacturer_admin');
select pg_temp.member('lp.admin',    'lagos-prime', 'distributor_admin');
select pg_temp.member('lp.bm.ikeja', 'lagos-prime', 'branch_manager',  'Ikeja');
select pg_temp.member('lp.bm.lekki', 'lagos-prime', 'branch_manager',  'Lekki');
select pg_temp.member('lp.wh.ikeja', 'lagos-prime', 'warehouse_staff', 'Ikeja');
select pg_temp.member('lp.wh.lekki', 'lagos-prime', 'warehouse_staff', 'Lekki');
select pg_temp.member('lp.agent1',   'lagos-prime', 'agent',  'Ikeja', 'Ikeja North');
select pg_temp.member('lp.agent2',   'lagos-prime', 'agent',  'Ikeja', 'Ikeja South');
select pg_temp.member('lp.agent3',   'lagos-prime', 'agent',  'Lekki', 'Lekki Phase 1');
select pg_temp.member('lp.driver1',  'lagos-prime', 'driver', 'Ikeja');
select pg_temp.member('ac.admin',    'abuja-central', 'distributor_admin');
select pg_temp.member('ac.bm.wuse',  'abuja-central', 'branch_manager',  'Wuse');
select pg_temp.member('ac.wh.wuse',  'abuja-central', 'warehouse_staff', 'Wuse');
select pg_temp.member('ac.agent1',   'abuja-central', 'agent',  'Wuse', 'Wuse Zone 4');
select pg_temp.member('ac.agent2',   'abuja-central', 'agent',  'Wuse', 'Garki');
select pg_temp.member('ac.driver1',  'abuja-central', 'driver', 'Wuse');

-- Retailers: 12 for Lagos Prime, 8 for Abuja Central -------------------------------------------
do $$
declare
  r record;
  v_org uuid;
begin
  for r in select * from (values
    ( 1, 'lagos-prime',   'Ikeja North',   6.6200, 3.3450),
    ( 2, 'lagos-prime',   'Ikeja North',   6.6250, 3.3550),
    ( 3, 'lagos-prime',   'Ikeja North',   6.6150, 3.3600),
    ( 4, 'lagos-prime',   'Ikeja North',   6.6300, 3.3500),
    ( 5, 'lagos-prime',   'Ikeja South',   6.5900, 3.3400),
    ( 6, 'lagos-prime',   'Ikeja South',   6.5850, 3.3550),
    ( 7, 'lagos-prime',   'Ikeja South',   6.5800, 3.3480),
    ( 8, 'lagos-prime',   'Ikeja South',   6.5950, 3.3620),
    ( 9, 'lagos-prime',   'Lekki Phase 1', 6.4480, 3.4720),
    (10, 'lagos-prime',   'Lekki Phase 1', 6.4520, 3.4800),
    (11, 'lagos-prime',   'Lekki Phase 1', 6.4430, 3.4650),
    (12, 'lagos-prime',   'Lekki Phase 1', 6.4600, 3.4900),
    (13, 'abuja-central', 'Wuse Zone 4',   9.0800, 7.4700),
    (14, 'abuja-central', 'Wuse Zone 4',   9.0830, 7.4750),
    (15, 'abuja-central', 'Wuse Zone 4',   9.0780, 7.4680),
    (16, 'abuja-central', 'Wuse Zone 4',   9.0850, 7.4800),
    (17, 'abuja-central', 'Garki',         9.0300, 7.4900),
    (18, 'abuja-central', 'Garki',         9.0350, 7.4950),
    (19, 'abuja-central', 'Garki',         9.0280, 7.4850),
    (20, 'abuja-central', 'Garki',         9.0320, 7.5000)
  ) as t(n, dist, terr, lat, lng)
  loop
    insert into public.organisations (kind, name, slug, status, location)
    values ('retailer', format('Retail Shop %s', lpad(r.n::text, 2, '0')),
            format('retailer-%s', lpad(r.n::text, 2, '0')), 'active', pg_temp.point(r.lat, r.lng))
    returning id into v_org;

    perform pg_temp.make_user(format('retailer%s', lpad(r.n::text, 2, '0')),
                              format('Shop Owner %s', lpad(r.n::text, 2, '0')),
                              format('+234801000%s', lpad(r.n::text, 4, '0')));
    perform pg_temp.member(format('retailer%s', lpad(r.n::text, 2, '0')),
                           format('retailer-%s', lpad(r.n::text, 2, '0')), 'retailer');

    insert into public.customer_relationships (distributor_org_id, retailer_org_id, territory_id, credit_limit_kobo, status)
    values (pg_temp.org(r.dist), v_org, pg_temp.territory(r.dist, r.terr),
            case when r.n % 3 = 0 then 50000000 else 0 end,   -- every 3rd retailer: N500,000 credit
            'active');
  end loop;
end;
$$;

-- Catalogue: 4 brands, 15 SKUs ----------------------------------------------------------------
insert into public.brands (manufacturer_org_id, name)
select pg_temp.org('sunrise'), b from unnest(array['Sunrise Noodles', 'Sunrise Dairy', 'Sunrise Drinks', 'Sunrise Home']) b;

do $$
declare
  s record;
  v_sku uuid;
begin
  for s in select * from (values
    ('NDL-CHK-70G',   'Sunrise Noodles', 'Chicken Noodles 70g',          'carton', 40),
    ('NDL-ONI-70G',   'Sunrise Noodles', 'Onion Noodles 70g',            'carton', 40),
    ('NDL-JMB-120G',  'Sunrise Noodles', 'Jumbo Noodles 120g',           'carton', 24),
    ('DRY-EVP-160G',  'Sunrise Dairy',   'Evaporated Milk 160g',         'carton', 48),
    ('DRY-PWD-400G',  'Sunrise Dairy',   'Powdered Milk Tin 400g',       'carton', 12),
    ('DRY-PWD-16G',   'Sunrise Dairy',   'Powdered Milk Sachet 16g',     'carton', 210),
    ('DRY-YGT-500ML', 'Sunrise Dairy',   'Yoghurt Drink 500ml',          'carton', 12),
    ('BEV-MLT-330ML', 'Sunrise Drinks',  'Malt Drink Can 330ml',         'carton', 24),
    ('BEV-COL-50CL',  'Sunrise Drinks',  'Cola PET 50cl',                'carton', 12),
    ('BEV-WTR-75CL',  'Sunrise Drinks',  'Table Water 75cl',             'carton', 12),
    ('BEV-JCE-1L',    'Sunrise Drinks',  'Orange Juice 1L',              'carton', 12),
    ('HOM-DET-500G',  'Sunrise Home',    'Detergent Powder 500g',        'carton', 20),
    ('HOM-DET-2KG',   'Sunrise Home',    'Detergent Powder 2kg',         'carton', 6),
    ('HOM-SOP-150G',  'Sunrise Home',    'Bath Soap 150g',               'carton', 72),
    ('HOM-BLC-1L',    'Sunrise Home',    'Bleach 1L',                    'carton', 12)
  ) as t(code, brand, name, uom, factor)
  loop
    insert into public.skus (manufacturer_org_id, brand_id, code, name)
    select pg_temp.org('sunrise'), b.id, s.code, s.name
    from public.brands b where b.manufacturer_org_id = pg_temp.org('sunrise') and b.name = s.brand
    returning id into v_sku;
    insert into public.sku_uom (sku_id, uom_code, pieces_per_uom) values (v_sku, s.uom, s.factor);
  end loop;
end;
$$;

-- Price lists: piece price + carton price (carton slightly cheaper than factor x piece) --------
insert into public.price_lists (distributor_org_id, name, effective_from)
select pg_temp.org(d), 'Standard', '2026-10-01T00:00:00Z' from unnest(array['lagos-prime', 'abuja-central']) d;

insert into public.price_list_items (price_list_id, sku_id, uom_code, price_kobo)
select pl.id, s.id, u.uom_code,
       case when u.uom_code = 'piece'
            then p.piece_kobo
            else app.round_div(p.piece_kobo::bigint * u.pieces_per_uom * 97, 100, 'half_even')  -- 3% carton discount
       end
from public.price_lists pl
cross join public.skus s
join public.sku_uom u on u.sku_id = s.id
join (values
  ('NDL-CHK-70G', 25000), ('NDL-ONI-70G', 25000), ('NDL-JMB-120G', 40000), ('DRY-EVP-160G', 50000),
  ('DRY-PWD-400G', 350000), ('DRY-PWD-16G', 10000), ('DRY-YGT-500ML', 80000), ('BEV-MLT-330ML', 50000),
  ('BEV-COL-50CL', 30000), ('BEV-WTR-75CL', 20000), ('BEV-JCE-1L', 150000), ('HOM-DET-500G', 120000),
  ('HOM-DET-2KG', 450000), ('HOM-SOP-150G', 60000), ('HOM-BLC-1L', 100000)
) as p(code, piece_kobo) on p.code = s.code;

-- Stock locations: warehouses + carriers ------------------------------------------------------
insert into public.stock_locations (kind, org_id, warehouse_id)
select 'warehouse', w.org_id, w.id from public.warehouses w;

insert into public.stock_locations (kind, org_id, user_id)
select m.role::text::public.location_kind, m.org_id, m.user_id
from public.memberships m where m.role in ('agent', 'driver');

-- Opening stock through the ledger (receipts): Ikeja 50 ctn, Lekki 20 ctn, Wuse 40 ctn per SKU --
do $$
declare
  w record;
  s record;
  v_group uuid;
begin
  for w in
    select sl.id as location_id, wh.name,
           case wh.name when 'Ikeja Main' then 50 when 'Lekki Depot' then 20 else 40 end as cartons
    from public.stock_locations sl join public.warehouses wh on wh.id = sl.warehouse_id
  loop
    v_group := gen_random_uuid();
    for s in
      select u.sku_id, u.pieces_per_uom from public.sku_uom u where u.uom_code = 'carton' order by u.sku_id
    loop
      perform app.post_stock_movement(v_group, 'receipt', w.location_id, s.sku_id,
                                      w.cartons * s.pieces_per_uom, null, null, null,
                                      'opening stock (seed)', format('seed:receipt:%s:%s', w.location_id, s.sku_id));
    end loop;
  end loop;
end;
$$;

-- Money: chart of accounts + wallet top-ups mirrored from the (mock) partner ---------------------
do $$
declare
  v_platform uuid := pg_temp.org('solus-platform');
  v_clearing uuid;
  d record;
  r record;
  v_wallet uuid;
begin
  v_clearing := app.ensure_account(v_platform, 'provider_clearing', p_provider => 'mockpay');

  for d in select id from public.organisations where kind = 'distributor' loop
    perform app.ensure_account(v_platform, 'wallet', p_holder_org_id => d.id);
    perform app.ensure_account(d.id, 'partner_funds');
    perform app.ensure_account(d.id, 'sales_revenue');
    perform app.ensure_account(d.id, 'variance_offset');
  end loop;

  for r in
    select cr.distributor_org_id, cr.retailer_org_id, o.slug
    from public.customer_relationships cr join public.organisations o on o.id = cr.retailer_org_id
    order by o.slug
  loop
    v_wallet := app.ensure_account(v_platform, 'wallet', p_holder_org_id => r.retailer_org_id);
    perform app.ensure_account(r.distributor_org_id, 'receivables', p_counterparty_org_id => r.retailer_org_id);
    perform app.ensure_account(r.distributor_org_id, 'trade_credit', p_counterparty_org_id => r.retailer_org_id);

    -- va_inflow: N100,000 + N5,000 x n, as if received by bank transfer into the retailer's virtual account.
    perform app.post_journal(
      'va_inflow',
      format('seed:va_inflow:%s', r.slug),
      jsonb_build_array(
        jsonb_build_object('account_id', v_clearing, 'amount_kobo',
                           (10000000 + 500000 * substr(r.slug, 10)::int)::text),
        jsonb_build_object('account_id', v_wallet, 'amount_kobo',
                           (-(10000000 + 500000 * substr(r.slug, 10)::int))::text)
      ),
      'seed', r.retailer_org_id, 'seed wallet top-up'
    );
  end loop;

  for r in
    select m.org_id, m.user_id from public.memberships m where m.role in ('agent', 'driver')
  loop
    perform app.ensure_account(r.org_id, 'cash_in_transit', p_counterparty_user_id => r.user_id);
    perform app.ensure_account(r.org_id, 'variance', p_counterparty_user_id => r.user_id);
    perform app.ensure_account(r.org_id, 'receivables', p_counterparty_user_id => r.user_id);
  end loop;
end;
$$;

-- Phase 4 demo flows, executed through the real app.* commands as the acting users (so every seed run
-- also proves the pull flow end to end). Uses SKUs/shops the pgTAP fixtures don't count against.
create function pg_temp.act_as(p_handle text) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', pg_temp.usr(p_handle), 'role', 'authenticated')::text, false)
$$;
create function pg_temp.sku(p_code text) returns uuid language sql stable as $$ select id from public.skus where code = p_code $$;
create function pg_temp.wh(p_name text) returns uuid language sql stable as $$ select id from public.warehouses where name = p_name $$;

do $$
declare
  r record;
  v_order jsonb;
  v_order_id uuid;
  v_batch uuid;
  v_shipment uuid;
  v_lines jsonb;
  v_photo text;
begin
  for r in select * from (values
    ('lagos-prime',   'retailer05', 'retailer-05', 'Ikeja Main',   'lp.wh.ikeja', 'lp.driver1', 6.5900, 3.3400, 4, 'retailer06', 'retailer-06'),
    ('abuja-central', 'retailer14', 'retailer-14', 'Wuse Central', 'ac.wh.wuse',  'ac.driver1', 9.0830, 7.4750, 2, 'retailer15', 'retailer-15')
  ) as t(dist, shop_user, shop_slug, wh_name, staff, driver, lat, lng, refused, pending_user, pending_slug)
  loop
    -- Inbound receipt
    perform pg_temp.act_as(r.staff);
    perform app.record_receipt(pg_temp.wh(r.wh_name), 'GRN-SEED-' || r.dist,
      jsonb_build_array(jsonb_build_object('sku_id', pg_temp.sku('DRY-PWD-400G'), 'uom_code', 'carton', 'uom_qty', 10)),
      'seed:receipt:' || r.dist);
    -- Pending adjustment (needs a branch manager's approval)
    perform app.request_adjustment(pg_temp.wh(r.wh_name), pg_temp.sku('HOM-SOP-150G'), -2, 'cycle count: 2 bars crushed');

    -- Retailer places an order: 2 cartons onion noodles + 6 cola
    perform pg_temp.act_as(r.shop_user);
    v_order := app.place_order(pg_temp.org(r.dist), pg_temp.org(r.shop_slug), jsonb_build_array(
      jsonb_build_object('sku_id', pg_temp.sku('NDL-ONI-70G'), 'uom_code', 'carton', 'uom_qty', 2),
      jsonb_build_object('sku_id', pg_temp.sku('BEV-COL-50CL'), 'uom_code', 'piece', 'uom_qty', 6)),
      'seed:order:' || r.dist);
    v_order_id := (v_order->>'order_id')::uuid;
    if v_order->>'status' <> 'reserved' then
      raise exception 'seed order for % not reserved: %', r.dist, v_order;
    end if;

    -- Warehouse batches, packs, dispatches; driver accepts in their own session
    perform pg_temp.act_as(r.staff);
    v_batch := app.create_batch(pg_temp.wh(r.wh_name), array[v_order_id]);
    perform app.mark_batch_packed(v_batch);
    v_shipment := app.dispatch_batch(v_batch, pg_temp.usr(r.driver));
    perform pg_temp.act_as(r.driver);
    perform app.accept_dispatch(v_shipment);

    -- e-POD: photo object (stands in for the app upload), then the delivery with refused/damaged goods
    v_photo := v_shipment || '/' || v_order_id || '/seed-epod.jpg';
    insert into storage.objects (bucket_id, name, owner_id) values ('epod', v_photo, pg_temp.usr(r.driver)::text);
    select jsonb_agg(jsonb_build_object(
             'allocation_id', a.id,
             'delivered', a.qty_pieces - case when a.sku_id = pg_temp.sku('NDL-ONI-70G') then r.refused
                                             when a.sku_id = pg_temp.sku('BEV-COL-50CL') then 1 else 0 end,
             'refused', case when a.sku_id = pg_temp.sku('NDL-ONI-70G') then r.refused else 0 end,
             'damaged', case when a.sku_id = pg_temp.sku('BEV-COL-50CL') then 1 else 0 end,
             'missing', 0))
      into v_lines
      from public.order_allocations a where a.order_id = v_order_id;
    perform app.record_delivery(v_shipment, v_order_id, v_lines, r.lat, r.lng, 8, v_photo, 'Shop Owner', 'seed:delivery:' || r.dist);

    -- Retailer disputes the refusal; warehouse counts the return; driver confirms -> shipment closes
    perform pg_temp.act_as(r.shop_user);
    perform app.dispute_delivery(v_order_id, format('%s noodle packs refused: dented carton', r.refused));
    perform pg_temp.act_as(r.staff);
    perform app.start_return(v_shipment, jsonb_build_array(
      jsonb_build_object('sku_id', pg_temp.sku('NDL-ONI-70G'), 'qty_pieces', r.refused)));
    perform pg_temp.act_as(r.driver);
    if app.confirm_return(v_shipment) <> 'closed' then
      raise exception 'seed shipment for % did not close', r.dist;
    end if;

    -- A second order left reserved, for the fulfilment screens
    perform pg_temp.act_as(r.pending_user);
    perform app.place_order(pg_temp.org(r.dist), pg_temp.org(r.pending_slug), jsonb_build_array(
      jsonb_build_object('sku_id', pg_temp.sku('DRY-EVP-160G'), 'uom_code', 'carton', 'uom_qty', 1)),
      'seed:order2:' || r.dist);
  end loop;

  -- Lagos Prime transfer Ikeja -> Lekki (received in full)
  perform pg_temp.act_as('lp.bm.ikeja');
  v_order_id := app.create_transfer(pg_temp.wh('Ikeja Main'), pg_temp.wh('Lekki Depot'),
    jsonb_build_array(jsonb_build_object('sku_id', pg_temp.sku('BEV-WTR-75CL'), 'uom_code', 'carton', 'uom_qty', 5)));
  perform pg_temp.act_as('lp.wh.ikeja');
  perform app.dispatch_transfer(v_order_id);
  perform pg_temp.act_as('lp.wh.lekki');
  perform app.receive_transfer(v_order_id, jsonb_build_array(
    jsonb_build_object('sku_id', pg_temp.sku('BEV-WTR-75CL'), 'received', 60, 'damaged', 0)));

  perform set_config('request.jwt.claims', '', false);
end;
$$;

-- Phase 5a demo: the spec's push example per distributor (100 picked, 70 sold, 25 returned, 3 damaged
-- -> 2 pcs variance pending), through real OTP issue + verify.
do $$
declare
  r record;
  v_req uuid;
  v_ship uuid;
  v_chal uuid;
  v_code text;
  v_res jsonb;
  v_sku uuid := pg_temp.sku('NDL-JMB-120G');
begin
  for r in select * from (values
    ('lp.agent1', 'lp.bm.ikeja', 'lp.wh.ikeja', 'Ikeja Main',   'retailer-02', 6.6250, 3.3550),
    ('ac.agent1', 'ac.bm.wuse',  'ac.wh.wuse',  'Wuse Central', 'retailer-16', 9.0850, 7.4800)
  ) as t(agent, bm, staff, wh_name, shop_slug, lat, lng)
  loop
    perform pg_temp.act_as(r.agent);
    v_req := app.request_stock(pg_temp.wh(r.wh_name),
      jsonb_build_array(jsonb_build_object('sku_id', v_sku, 'uom_code', 'piece', 'uom_qty', 100)), 'morning route');
    perform pg_temp.act_as(r.bm);
    v_ship := app.decide_stock_request(v_req, true);

    perform pg_temp.act_as(r.staff);
    v_chal := app.start_handover(v_ship);
    select code into v_code from app.issue_otp_code(v_chal);       -- what the SMS adapter would send
    v_res := app.verify_otp(v_chal, v_code);
    if not (v_res->>'ok')::boolean then raise exception 'seed handover OTP failed: %', v_res; end if;

    perform pg_temp.act_as(r.agent);
    perform app.record_push_sale(v_ship, pg_temp.org(r.shop_slug),
      jsonb_build_array(jsonb_build_object('sku_id', v_sku, 'qty_pieces', 70)), r.lat, r.lng, 7, 'seed:push_sale:' || r.agent);

    perform pg_temp.act_as(r.staff);
    v_chal := app.start_push_return(v_ship, jsonb_build_array(jsonb_build_object('sku_id', v_sku, 'qty_pieces', 25, 'damaged', 3)));
    select code into v_code from app.issue_otp_code(v_chal);
    v_res := app.verify_otp(v_chal, v_code);
    if v_res->>'result' <> 'reconciling' then raise exception 'seed push return expected reconciling: %', v_res; end if;
  end loop;
  perform set_config('request.jwt.claims', '', false);
end;
$$;
