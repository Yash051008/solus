-- Warehouse staff must see the shops whose orders they pack: add retailers with allocations at the
-- caller's visible warehouses.
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
    union
    select o.retailer_org_id
    from public.orders o
    join public.order_allocations a on a.order_id = o.id
    where a.warehouse_id = any(app.visible_warehouse_ids())
  ) x
$$;
