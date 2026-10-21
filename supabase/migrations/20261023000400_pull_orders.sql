-- Pull orders: placement, nearest-warehouse routing, allocation-based reservation, split decisions,
-- cancellation (Phase 4). An allocation = (order line, warehouse, pieces) and is the unit of fulfilment.

alter table public.orders
  add column placed_by_role   public.member_role,
  add column cancelled_reason text,
  add column confirmed_at     timestamptz;

create table public.order_allocations (
  id            uuid primary key default gen_random_uuid(),
  order_id      uuid not null references public.orders (id),
  order_line_id uuid not null references public.order_lines (id),
  sku_id        uuid not null references public.skus (id),
  warehouse_id  uuid not null references public.warehouses (id),
  qty_pieces    integer not null check (qty_pieces > 0),
  status        text not null default 'reserved'
                check (status in ('reserved', 'batched', 'packed', 'dispatched', 'delivered', 'released')),
  batch_id      uuid,
  created_at    timestamptz not null default now()
);
create index order_allocations_order_idx on public.order_allocations (order_id);
create index order_allocations_wh_status_idx on public.order_allocations (warehouse_id, status);
create index order_allocations_batch_idx on public.order_allocations (batch_id);

-- Internal. Reserves p_allocations = [{"order_line_id","warehouse_id","qty_pieces"}] for a locked order.
-- Every line must be fully allocated; balance rows are locked (location, sku) ascending and re-checked.
create function app.reserve_allocations(p_order_id uuid, p_allocations jsonb)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_order public.orders;
  v_need  record;
  v_avail integer;
  v_alloc record;
begin
  select * into strict v_order from public.orders where id = p_order_id;

  if exists (
    select 1 from public.order_lines l
    left join (select (a->>'order_line_id')::uuid as line_id, sum((a->>'qty_pieces')::integer) as qty
               from jsonb_array_elements(p_allocations) a group by 1) x on x.line_id = l.id
    where l.order_id = p_order_id and coalesce(x.qty, 0) <> l.qty_pieces
  ) or exists (
    select 1 from jsonb_array_elements(p_allocations) a
    left join public.order_lines l on l.id = (a->>'order_line_id')::uuid and l.order_id = p_order_id
    left join public.warehouses w on w.id = (a->>'warehouse_id')::uuid
                                 and w.org_id = v_order.distributor_org_id and w.active
    where l.id is null or w.id is null or (a->>'qty_pieces')::integer <= 0
  ) then
    raise exception using errcode = 'SOL05',
      message = 'allocations must cover every order line exactly, from active warehouses of the distributor';
  end if;

  for v_need in
    select app.warehouse_location((a->>'warehouse_id')::uuid) as location_id, l.sku_id,
           sum((a->>'qty_pieces')::integer)::integer as qty
    from jsonb_array_elements(p_allocations) a
    join public.order_lines l on l.id = (a->>'order_line_id')::uuid
    group by 1, 2
    order by 1, 2
  loop
    select available into v_avail from public.stock_balances
     where location_id = v_need.location_id and sku_id = v_need.sku_id
       for update;
    if coalesce(v_avail, 0) < v_need.qty then
      raise exception using errcode = 'SOL01', message = 'insufficient_stock',
        detail = format('sku %s at location %s: need %s, available %s',
                        v_need.sku_id, v_need.location_id, v_need.qty, coalesce(v_avail, 0));
    end if;
  end loop;

  for v_alloc in
    select (a->>'order_line_id')::uuid as line_id, (a->>'warehouse_id')::uuid as warehouse_id,
           (a->>'qty_pieces')::integer as qty, l.sku_id
    from jsonb_array_elements(p_allocations) a
    join public.order_lines l on l.id = (a->>'order_line_id')::uuid
    order by 2, 4
  loop
    insert into public.order_allocations (order_id, order_line_id, sku_id, warehouse_id, qty_pieces)
    values (p_order_id, v_alloc.line_id, v_alloc.sku_id, v_alloc.warehouse_id, v_alloc.qty);
    perform app.post_stock_movement(p_order_id, 'reserve', app.warehouse_location(v_alloc.warehouse_id),
                                    v_alloc.sku_id, v_alloc.qty, null, 'order', p_order_id, null, null);
  end loop;

  -- Single-source lines record their warehouse directly (split lines leave it null; see allocations).
  update public.order_lines l
     set warehouse_id = x.warehouse_id
    from (select order_line_id, min(warehouse_id::text)::uuid as warehouse_id
          from public.order_allocations where order_id = p_order_id and status = 'reserved'
          group by order_line_id having count(distinct warehouse_id) = 1) x
   where l.id = x.order_line_id;

  update public.orders set status = 'reserved' where id = p_order_id;
end;
$$;

-- Phase 2 entry point kept: reserve every line at one warehouse.
create or replace function app.reserve_order(p_order_id uuid, p_warehouse_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_order public.orders;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception using errcode = 'SOL05', message = format('order %s not found', p_order_id);
  end if;
  if v_order.status not in ('placed', 'awaiting_split_decision') then
    raise exception using errcode = 'SOL04',
      message = format('order %s is %s; only placed orders can be reserved', p_order_id, v_order.status);
  end if;
  if not exists (select 1 from public.order_lines where order_id = p_order_id) then
    raise exception using errcode = 'SOL05', message = format('order %s has no lines', p_order_id);
  end if;
  if not exists (select 1 from public.warehouses where id = p_warehouse_id and org_id = v_order.distributor_org_id and active) then
    raise exception using errcode = 'SOL05',
      message = format('warehouse %s is not an active warehouse of the order''s distributor', p_warehouse_id);
  end if;
  perform app.reserve_allocations(p_order_id, (
    select jsonb_agg(jsonb_build_object('order_line_id', l.id, 'warehouse_id', p_warehouse_id, 'qty_pieces', l.qty_pieces))
    from public.order_lines l where l.order_id = p_order_id));
end;
$$;

-- Routing (internal; caller holds the order row lock). Locks every candidate balance row first, so the
-- decision is made on data no concurrent order can change.
--   1. Nearest warehouse that can cover the WHOLE order, if its extra distance over the nearest warehouse
--      is within the distributor's split threshold -> reserve there.
--   2. Otherwise, if a greedy nearest-first split covers the order -> awaiting_split_decision
--      (options: split, plus single if a full-cover warehouse exists).
--   3. Otherwise -> rejected (nothing reserved).
-- The decision, candidates and reason are stored on the order.
create function app.route_and_reserve(p_order_id uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_order      public.orders;
  v_point      extensions.geography;
  v_threshold  integer;
  v_candidates jsonb;
  v_nearest    integer;
  v_full       jsonb;
  v_split      jsonb := '[]'::jsonb;
  v_used       jsonb := '{}'::jsonb;
  v_line       record;
  v_cand       jsonb;
  v_remaining  integer;
  v_avail      integer;
  v_take       integer;
  v_key        text;
  v_rule       text;
  v_status     text;
begin
  select * into strict v_order from public.orders where id = p_order_id;
  select o.location into v_point from public.organisations o where o.id = v_order.retailer_org_id;
  select coalesce(split_threshold_m, 15000) into v_threshold from public.organisations where id = v_order.distributor_org_id;

  perform 1 from public.stock_balances b
   where b.location_id in (select sl.id from public.stock_locations sl join public.warehouses w on w.id = sl.warehouse_id
                           where w.org_id = v_order.distributor_org_id and w.active)
     and b.sku_id in (select sku_id from public.order_lines where order_id = p_order_id)
   order by b.location_id, b.sku_id
     for update;

  with need as (
    select sku_id, sum(qty_pieces)::integer as qty from public.order_lines where order_id = p_order_id group by sku_id
  )
  select jsonb_agg(c order by c.distance_m, c.name) into v_candidates from (
    select w.id as warehouse_id, w.name,
           round(extensions.st_distance(w.location, v_point))::integer as distance_m,
           bool_and(coalesce(b.available, 0) >= n.qty) as can_cover
    from public.warehouses w
    join public.stock_locations sl on sl.warehouse_id = w.id
    cross join need n
    left join public.stock_balances b on b.location_id = sl.id and b.sku_id = n.sku_id
    where w.org_id = v_order.distributor_org_id and w.active
    group by w.id, w.name, w.location
  ) c;

  if v_candidates is null then
    v_rule := 'no_active_warehouse';
  else
    v_nearest := (v_candidates->0->>'distance_m')::integer;
    select c into v_full from jsonb_array_elements(v_candidates) c where (c->>'can_cover')::boolean limit 1;

    -- Greedy nearest-first split proposal (per line, honouring what earlier lines already took).
    for v_line in select id, sku_id, qty_pieces from public.order_lines where order_id = p_order_id order by created_at, id loop
      v_remaining := v_line.qty_pieces;
      for v_cand in select c from jsonb_array_elements(v_candidates) c loop
        exit when v_remaining = 0;
        v_key := (v_cand->>'warehouse_id') || ':' || v_line.sku_id;
        select coalesce(b.available, 0) - coalesce((v_used->>v_key)::integer, 0) into v_avail
          from (select 1) one
          left join public.stock_balances b
            on b.location_id = app.warehouse_location((v_cand->>'warehouse_id')::uuid) and b.sku_id = v_line.sku_id;
        v_take := least(greatest(v_avail, 0), v_remaining);
        if v_take > 0 then
          v_split := v_split || jsonb_build_object('order_line_id', v_line.id, 'warehouse_id', v_cand->>'warehouse_id', 'qty_pieces', v_take);
          v_used := v_used || jsonb_build_object(v_key, coalesce((v_used->>v_key)::integer, 0) + v_take);
          v_remaining := v_remaining - v_take;
        end if;
      end loop;
      if v_remaining > 0 then
        v_split := null;
        exit;
      end if;
    end loop;

    if v_full is not null and ((v_full->>'distance_m')::integer - v_nearest <= v_threshold
        or v_split is null
        or not exists (select 1 from jsonb_array_elements(v_split) s where s->>'warehouse_id' <> v_full->>'warehouse_id')) then
      v_rule := 'nearest_full_cover';
      perform app.reserve_order(p_order_id, (v_full->>'warehouse_id')::uuid);
    elsif v_split is not null then
      v_rule := case when v_full is null then 'no_single_warehouse_can_cover' else 'distance_penalty_exceeds_threshold' end;
    else
      v_rule := 'insufficient_stock_in_network';
    end if;
  end if;

  v_status := case
    when v_rule = 'nearest_full_cover' then 'reserved'
    when v_rule in ('no_single_warehouse_can_cover', 'distance_penalty_exceeds_threshold') then 'awaiting_split_decision'
    else 'rejected' end;

  update public.orders
     set status = v_status::public.order_status,
         routing_reason = v_rule,
         routing_decision = jsonb_build_object(
           'rule', v_rule,
           'threshold_m', v_threshold,
           'nearest_distance_m', v_nearest,
           'candidates', coalesce(v_candidates, '[]'::jsonb),
           'chosen_warehouse_id', case when v_rule = 'nearest_full_cover' then v_full->>'warehouse_id' end,
           'penalty_m', case when v_full is not null then (v_full->>'distance_m')::integer - v_nearest end,
           'options', case when v_status = 'awaiting_split_decision'
                           then jsonb_strip_nulls(jsonb_build_object(
                                  'single', case when v_full is not null then jsonb_build_object('warehouse_id', v_full->>'warehouse_id') end,
                                  'split', v_split))
                      end,
           'decided_at', now())
   where id = p_order_id;
  return v_status;
end;
$$;

-- Place a pull order: retailer for their own shop, or an agent for a shop in their territory.
-- Lines: [{"sku_id","uom_code","uom_qty"}]. Prices come from the distributor's current price list,
-- never from the client. Idempotent on p_idempotency_key.
create function app.place_order(p_distributor_id uuid, p_retailer_org_id uuid, p_lines jsonb, p_idempotency_key text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid    uuid := app.require_user();
  v_role   public.member_role;
  v_id     uuid;
  v_line   record;
  v_price  bigint;
  v_status text;
  v_replay jsonb;
begin
  if app.has_role(p_retailer_org_id, array['retailer']::public.member_role[]) then
    v_role := 'retailer';
  elsif app.has_role(p_distributor_id, array['agent']::public.member_role[])
        and p_retailer_org_id = any(app.visible_retailer_ids()) then
    v_role := 'agent';
  else
    raise exception using errcode = 'SOL03', message = 'only the shop owner or an agent covering the shop can place this order';
  end if;
  if not exists (select 1 from public.customer_relationships
                 where distributor_org_id = p_distributor_id and retailer_org_id = p_retailer_org_id and status = 'active') then
    raise exception using errcode = 'SOL04', message = 'this shop is not an approved customer of the distributor';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then
    raise exception using errcode = 'SOL05', message = 'an idempotency key (8+ chars) is required';
  end if;

  insert into public.orders (distributor_org_id, retailer_org_id, placed_by_user_id, placed_by_role, idempotency_key)
  values (p_distributor_id, p_retailer_org_id, v_uid, v_role, p_idempotency_key)
  on conflict (idempotency_key) do nothing
  returning id into v_id;

  if v_id is null then   -- replay: return the original order, never a second one
    select jsonb_build_object('order_id', o.id, 'status', o.status, 'routing_reason', o.routing_reason, 'replayed', true)
      into v_replay
      from public.orders o
     where o.idempotency_key = p_idempotency_key and o.retailer_org_id = p_retailer_org_id;
    if v_replay is null then
      raise exception using errcode = 'SOL02', message = 'idempotency key already used for a different shop';
    end if;
    return v_replay;
  end if;

  for v_line in select * from app.lines_to_pieces(p_lines) order by line_no loop
    v_price := app.current_price_kobo(p_distributor_id, v_line.sku_id, v_line.uom_code);
    if v_price is null then
      raise exception using errcode = 'SOL05', message = format('no current price for sku %s per %s', v_line.sku_id, v_line.uom_code);
    end if;
    insert into public.order_lines (order_id, sku_id, uom_code, uom_qty, uom_price_kobo)
    values (v_id, v_line.sku_id, v_line.uom_code, v_line.uom_qty, v_price);
  end loop;

  v_status := app.route_and_reserve(v_id);
  return jsonb_build_object('order_id', v_id, 'status', v_status,
                            'routing_reason', (select routing_reason from public.orders where id = v_id), 'replayed', false);
end;
$$;

-- A branch manager (of the shop's territory branch) or admin picks single-source or split.
create function app.decide_split(p_order_id uuid, p_choice text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid    uuid := app.require_user();
  v_order  public.orders;
  v_branch uuid;
  v_option jsonb;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.status <> 'awaiting_split_decision' then
    raise exception using errcode = 'SOL04', message = 'order is not awaiting a split decision';
  end if;
  select t.branch_id into v_branch from public.customer_relationships cr join public.territories t on t.id = cr.territory_id
   where cr.distributor_org_id = v_order.distributor_org_id and cr.retailer_org_id = v_order.retailer_org_id;
  perform app.require_branch_manager(v_branch);

  v_option := v_order.routing_decision -> 'options' -> p_choice;
  if v_option is null then
    raise exception using errcode = 'SOL05', message = format('option %s is not available for this order', p_choice);
  end if;

  if p_choice = 'single' then
    perform app.reserve_order(p_order_id, (v_option->>'warehouse_id')::uuid);
  else
    perform app.reserve_allocations(p_order_id, v_option);
  end if;
  update public.orders
     set routing_decision = routing_decision || jsonb_build_object('decision', p_choice, 'decided_by', v_uid, 'decided_at', now())
   where id = p_order_id;
end;
$$;

-- Cancel before dispatch: releases every reserved/batched/packed allocation in one transaction.
create function app.cancel_order(p_order_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_order public.orders;
  v_alloc record;
begin
  perform app.require_user();
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception using errcode = 'SOL05', message = 'order not found';
  end if;
  if not (app.has_role(v_order.retailer_org_id, array['retailer']::public.member_role[])
          or app.has_role(v_order.distributor_org_id, array['distributor_admin', 'branch_manager']::public.member_role[])) then
    raise exception using errcode = 'SOL03', message = 'only the shop owner or the distributor''s managers can cancel';
  end if;
  if v_order.status not in ('placed', 'awaiting_split_decision', 'reserved', 'batched', 'packed') then
    raise exception using errcode = 'SOL04', message = format('a %s order can no longer be cancelled', v_order.status);
  end if;
  if exists (select 1 from public.order_allocations where order_id = p_order_id and status = 'dispatched') then
    raise exception using errcode = 'SOL04', message = 'part of this order has already been dispatched';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception using errcode = 'SOL05', message = 'a reason is required';
  end if;

  for v_alloc in
    select id, sku_id, warehouse_id, qty_pieces from public.order_allocations
    where order_id = p_order_id and status in ('reserved', 'batched', 'packed') order by warehouse_id, sku_id
  loop
    perform app.post_stock_movement(p_order_id, 'release', app.warehouse_location(v_alloc.warehouse_id),
                                    v_alloc.sku_id, v_alloc.qty_pieces, null, 'order', p_order_id, 'order cancelled', null);
    update public.order_allocations set status = 'released' where id = v_alloc.id;
  end loop;
  update public.orders set status = 'cancelled', cancelled_reason = p_reason where id = p_order_id;
end;
$$;

create view public.v_orders with (security_invoker = true) as
select o.id, o.distributor_org_id, o.retailer_org_id, o.status, o.routing_reason, o.routing_decision,
       o.placed_by_role, o.created_at, o.confirmed_at, o.cancelled_reason,
       coalesce((select sum(l.line_amount_kobo) from public.order_lines l where l.order_id = o.id), 0)::bigint as total_kobo
from public.orders o;
