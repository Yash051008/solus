-- RLS, audit and grants for Phase 4 tables, views and commands. Also narrows order visibility for
-- branch staff to their branch (a Phase 2 simplification) and gives carriers sight of what they carry.

create function app.visible_warehouse_ids()
returns uuid[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(distinct w.id), '{}')
  from public.warehouses w
  join public.memberships m on m.org_id = w.org_id
  where m.user_id = app.current_user_id() and m.status = 'active'
    and (m.role = 'distributor_admin'
         or (m.role in ('branch_manager', 'warehouse_staff') and m.branch_id = w.branch_id))
$$;

create function app.my_carrier_location_ids()
returns uuid[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(sl.id), '{}') from public.stock_locations sl
  join public.memberships m on m.user_id = sl.user_id and m.org_id = sl.org_id and m.role::text = sl.kind::text
  where sl.user_id = app.current_user_id() and sl.kind in ('agent', 'driver') and m.status = 'active'
$$;

create function app.visible_shipment_ids()
returns uuid[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(distinct s.id), '{}') from public.shipments s
  where s.warehouse_id = any(app.visible_warehouse_ids())
     or s.carrier_location_id = any(app.my_carrier_location_ids())
$$;

-- Orders: admin (all of the org); BM/warehouse staff (allocated to their warehouses, or BM: shops in their
-- branch territories); agent (shops in their territory, own distributor); retailer (own); carrier
-- (orders in their shipments).
create function app.visible_order_ids()
returns uuid[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(distinct x.id), '{}') from (
    select o.id from public.orders o
    where o.distributor_org_id = any(app.my_org_ids_with_role(array['distributor_admin']::public.member_role[]))
    union
    select a.order_id from public.order_allocations a where a.warehouse_id = any(app.visible_warehouse_ids())
    union
    select o.id from public.orders o
    join public.customer_relationships cr on cr.distributor_org_id = o.distributor_org_id and cr.retailer_org_id = o.retailer_org_id
    join public.territories t on t.id = cr.territory_id
    where t.branch_id = any(app.my_branch_ids(array['branch_manager']::public.member_role[]))
    union
    select o.id from public.orders o
    join public.customer_relationships cr on cr.distributor_org_id = o.distributor_org_id and cr.retailer_org_id = o.retailer_org_id
    join public.memberships m on m.territory_id = cr.territory_id and m.org_id = o.distributor_org_id
    where m.user_id = app.current_user_id() and m.role = 'agent' and m.status = 'active'
    union
    select o.id from public.orders o
    where o.retailer_org_id = any(app.my_org_ids_with_role(array['retailer']::public.member_role[]))
    union
    select a.order_id from public.order_allocations a
    join public.shipments s on s.batch_id = a.batch_id
    where s.carrier_location_id = any(app.my_carrier_location_ids())
  ) x
$$;

-- Carriers also need to see the shops they deliver to.
create or replace function app.visible_retailer_ids()
returns uuid[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(distinct x.id), '{}') from (
    select unnest(app.my_org_ids_with_role(array['retailer']::public.member_role[])) as id
    union
    select cr.retailer_org_id
    from public.customer_relationships cr
    where cr.distributor_org_id = any(app.my_org_ids_with_role(array['distributor_admin']::public.member_role[]))
    union
    select cr.retailer_org_id
    from public.customer_relationships cr
    join public.territories t on t.id = cr.territory_id
    where t.branch_id = any(app.my_branch_ids(array['branch_manager']::public.member_role[]))
    union
    select cr.retailer_org_id
    from public.customer_relationships cr
    join public.memberships m on m.territory_id = cr.territory_id and m.org_id = cr.distributor_org_id
    where m.user_id = app.current_user_id() and m.status = 'active' and m.role = 'agent'
    union
    select o.retailer_org_id
    from public.orders o
    join public.order_allocations a on a.order_id = o.id
    join public.shipments s on s.batch_id = a.batch_id
    where s.carrier_location_id = any(app.my_carrier_location_ids())
      and s.status in ('awaiting_acceptance', 'open', 'returning', 'reconciling')
  ) x
$$;

-- Orders policy: replace the Phase 2 org-wide staff rule with the scoped helper.
drop policy orders_select on public.orders;
create policy orders_select on public.orders for select to authenticated using (
  (select app.is_platform_admin()) or id = any((select app.visible_order_ids())::uuid[])
);

alter table public.receipts enable row level security;
alter table public.adjustment_requests enable row level security;
alter table public.transfers enable row level security;
alter table public.transfer_lines enable row level security;
alter table public.order_allocations enable row level security;
alter table public.batches enable row level security;
alter table public.shipments enable row level security;
alter table public.deliveries enable row level security;
alter table public.delivery_lines enable row level security;
alter table public.order_disputes enable row level security;
alter table public.shipment_returns enable row level security;

create policy receipts_select on public.receipts for select to authenticated using (
  (select app.is_platform_admin()) or warehouse_id = any((select app.visible_warehouse_ids())::uuid[]));
create policy adjustment_requests_select on public.adjustment_requests for select to authenticated using (
  (select app.is_platform_admin()) or location_id = any((select app.visible_location_ids())::uuid[]));
create policy transfers_select on public.transfers for select to authenticated using (
  (select app.is_platform_admin())
  or from_warehouse_id = any((select app.visible_warehouse_ids())::uuid[])
  or to_warehouse_id = any((select app.visible_warehouse_ids())::uuid[]));
create policy transfer_lines_select on public.transfer_lines for select to authenticated using (
  transfer_id in (select t.id from public.transfers t));
create policy order_allocations_select on public.order_allocations for select to authenticated using (
  (select app.is_platform_admin()) or order_id = any((select app.visible_order_ids())::uuid[]));
create policy batches_select on public.batches for select to authenticated using (
  (select app.is_platform_admin()) or warehouse_id = any((select app.visible_warehouse_ids())::uuid[])
  or id in (select s.batch_id from public.shipments s));
create policy shipments_select on public.shipments for select to authenticated using (
  (select app.is_platform_admin()) or id = any((select app.visible_shipment_ids())::uuid[]));
create policy deliveries_select on public.deliveries for select to authenticated using (
  (select app.is_platform_admin()) or shipment_id = any((select app.visible_shipment_ids())::uuid[])
  or order_id = any((select app.visible_order_ids())::uuid[]));
create policy delivery_lines_select on public.delivery_lines for select to authenticated using (
  delivery_id in (select d.id from public.deliveries d));
create policy order_disputes_select on public.order_disputes for select to authenticated using (
  (select app.is_platform_admin()) or order_id = any((select app.visible_order_ids())::uuid[]));
create policy shipment_returns_select on public.shipment_returns for select to authenticated using (
  (select app.is_platform_admin()) or shipment_id = any((select app.visible_shipment_ids())::uuid[]));

select audit.attach(t::regclass) from unnest(array[
  'public.receipts', 'public.adjustment_requests', 'public.transfers', 'public.transfer_lines',
  'public.order_allocations', 'public.batches', 'public.shipments', 'public.deliveries',
  'public.delivery_lines', 'public.order_disputes', 'public.shipment_returns']) t;

revoke all on public.receipts, public.adjustment_requests, public.transfers, public.transfer_lines,
  public.order_allocations, public.batches, public.shipments, public.deliveries, public.delivery_lines,
  public.order_disputes, public.shipment_returns, public.v_current_prices, public.v_transfer_in_transit,
  public.v_orders, public.v_shipment_reconciliation from anon, authenticated;
grant select on public.receipts, public.adjustment_requests, public.transfers, public.transfer_lines,
  public.order_allocations, public.batches, public.shipments, public.deliveries, public.delivery_lines,
  public.order_disputes, public.shipment_returns, public.v_current_prices, public.v_transfer_in_transit,
  public.v_orders, public.v_shipment_reconciliation to authenticated;

revoke all on all functions in schema app from public, anon, authenticated;
grant execute on function
  -- RLS helpers
  app.current_user_id(), app.is_platform_admin(), app.my_org_ids(),
  app.my_org_ids_with_role(public.member_role[]), app.my_branch_ids(public.member_role[]),
  app.visible_location_ids(), app.visible_retailer_ids(), app.visible_distributor_ids(),
  app.visible_manufacturer_ids(), app.visible_user_ids(), app.visible_account_ids(),
  app.account_normal_side(public.account_type),
  app.visible_warehouse_ids(), app.my_carrier_location_ids(), app.visible_shipment_ids(), app.visible_order_ids(),
  -- Phase 3 commands
  app.onboard_organisation(public.org_kind, text, text, uuid),
  app.update_distributor_settings(uuid, integer, integer, integer),
  app.create_branch(uuid, text), app.create_territory(uuid, text, jsonb),
  app.create_warehouse(uuid, text, double precision, double precision), app.set_warehouse_active(uuid, boolean),
  app.upsert_my_profile(text, text), app.registration_directory(),
  app.register_retailer(text, text, text, double precision, double precision, integer, uuid),
  app.request_distributor(uuid, uuid), app.decide_customer(uuid, boolean, uuid, text),
  app.request_to_join(uuid, public.member_role, text, text, text),
  app.decide_join_request(uuid, boolean, uuid, uuid, text), app.kyc_level(uuid),
  app.check_geofence(uuid, uuid, double precision, double precision, double precision),
  -- Phase 4 commands
  app.create_brand(uuid, text), app.create_sku(uuid, uuid, text, text, integer),
  app.add_sku_uom(uuid, text, integer), app.set_sku_active(uuid, boolean),
  app.publish_price_list(uuid, text, timestamptz, jsonb),
  app.record_receipt(uuid, text, jsonb, text),
  app.request_adjustment(uuid, uuid, integer, text), app.decide_adjustment(uuid, boolean, text),
  app.create_transfer(uuid, uuid, jsonb), app.dispatch_transfer(uuid),
  app.receive_transfer(uuid, jsonb), app.resolve_transfer_shortage(uuid, text),
  app.place_order(uuid, uuid, jsonb, text), app.decide_split(uuid, text), app.cancel_order(uuid, text),
  app.create_batch(uuid, uuid[]), app.mark_batch_packed(uuid), app.dispatch_batch(uuid, uuid),
  app.accept_dispatch(uuid), app.decline_dispatch(uuid, text),
  app.record_delivery(uuid, uuid, jsonb, double precision, double precision, double precision, text, text, text),
  app.confirm_delivery(uuid), app.dispute_delivery(uuid, text),
  app.start_return(uuid, jsonb), app.confirm_return(uuid), app.close_shipment(uuid)
to authenticated;

grant execute on function app.record_kyc_result(uuid, uuid, text, text, text, text, text) to service_role;
