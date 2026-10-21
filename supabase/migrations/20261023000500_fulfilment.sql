-- Fulfilment (Phase 4): batch -> pack -> dispatch (two-party: staff dispatch, driver accepts in their own
-- session) -> delivery with e-POD (photo + geotag + per-line delivered/refused/damaged/missing) ->
-- invoice -> retailer confirm/dispute -> return of refused stock (two-party) -> close when the carrier
-- holds nothing. Shipments are shared with push runs (kind 'push', Phase 5a).

create table public.batches (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organisations (id),
  warehouse_id uuid not null references public.warehouses (id),
  status       text not null default 'open' check (status in ('open', 'packed', 'dispatched')),
  created_by   uuid not null references public.profiles (user_id),
  packed_by    uuid references public.profiles (user_id),
  packed_at    timestamptz,
  created_at   timestamptz not null default now()
);
create index batches_wh_status_idx on public.batches (warehouse_id, status);
alter table public.order_allocations
  add constraint order_allocations_batch_fk foreign key (batch_id) references public.batches (id);

create table public.shipments (
  id                  uuid primary key default gen_random_uuid(),
  org_id              uuid not null references public.organisations (id),
  kind                text not null check (kind in ('delivery', 'push')),
  warehouse_id        uuid not null references public.warehouses (id),
  carrier_location_id uuid not null references public.stock_locations (id),
  batch_id            uuid references public.batches (id),
  status              text not null default 'awaiting_acceptance'
                      check (status in ('awaiting_acceptance', 'open', 'returning', 'reconciling', 'closed', 'cancelled')),
  dispatched_by       uuid not null references public.profiles (user_id),
  accepted_at         timestamptz,
  closed_at           timestamptz,
  status_note         text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint shipments_delivery_has_batch check (kind <> 'delivery' or batch_id is not null)
);
-- ADR-0003 D4: one active shipment per carrier, so the carrier's balance IS the shipment balance.
create unique index shipments_one_active_per_carrier on public.shipments (carrier_location_id)
  where status in ('awaiting_acceptance', 'open', 'returning', 'reconciling');
create unique index shipments_one_live_per_batch on public.shipments (batch_id) where status <> 'cancelled';
create index shipments_wh_status_idx on public.shipments (warehouse_id, status);
create trigger shipments_updated_at before update on public.shipments
  for each row execute function app.tg_set_updated_at();

create table public.deliveries (
  id              uuid primary key default gen_random_uuid(),
  shipment_id     uuid not null references public.shipments (id),
  order_id        uuid not null references public.orders (id),
  recorded_by     uuid not null references public.profiles (user_id),
  recipient_name  text not null check (length(btrim(recipient_name)) between 2 and 120),
  photo_path      text not null,
  lat             double precision not null,
  lng             double precision not null,
  accuracy_m      double precision not null check (accuracy_m >= 0),
  geofence_ok     boolean not null,
  geofence_reason text not null,
  distance_m      integer,
  invoiced_kobo   bigint not null default 0 check (invoiced_kobo >= 0),
  journal_id      uuid references public.journals (id),
  idempotency_key text not null unique check (length(idempotency_key) >= 8),
  recorded_at     timestamptz not null default now(),
  unique (shipment_id, order_id),
  -- Evidence lives at epod/<shipment_id>/<order_id>/<file> (storage policies enforce the same layout).
  constraint deliveries_photo_path_layout check (photo_path like shipment_id::text || '/' || order_id::text || '/%')
);
create index deliveries_order_idx on public.deliveries (order_id);

create table public.delivery_lines (
  id            uuid primary key default gen_random_uuid(),
  delivery_id   uuid not null references public.deliveries (id),
  allocation_id uuid not null unique references public.order_allocations (id),
  delivered     integer not null check (delivered >= 0),
  refused       integer not null check (refused >= 0),
  damaged       integer not null check (damaged >= 0),
  missing       integer not null check (missing >= 0)
);

create table public.order_disputes (
  id         uuid primary key default gen_random_uuid(),
  order_id   uuid not null references public.orders (id),
  raised_by  uuid not null references public.profiles (user_id),
  reason     text not null check (length(btrim(reason)) between 3 and 1000),
  status     text not null default 'open' check (status in ('open', 'resolved')),
  created_at timestamptz not null default now()
);
create index order_disputes_order_idx on public.order_disputes (order_id);

create table public.shipment_returns (
  id           uuid primary key default gen_random_uuid(),
  shipment_id  uuid not null references public.shipments (id),
  sku_id       uuid not null references public.skus (id),
  qty_pieces   integer not null check (qty_pieces > 0),
  counted_by   uuid not null references public.profiles (user_id),
  confirmed_at timestamptz,
  created_at   timestamptz not null default now(),
  unique (shipment_id, sku_id)
);

-- Order status follows its allocations (split orders progress per warehouse).
create function app.refresh_order_status(p_order_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_statuses text[];
  v_delivered bigint;
  v_short bigint;
  v_new public.order_status;
begin
  select array_agg(distinct status) into v_statuses
  from public.order_allocations where order_id = p_order_id and status <> 'released';
  if v_statuses is null then
    return;
  end if;

  if v_statuses = array['delivered'] then
    select coalesce(sum(dl.delivered), 0), coalesce(sum(dl.refused + dl.damaged + dl.missing), 0)
      into v_delivered, v_short
    from public.delivery_lines dl join public.order_allocations a on a.id = dl.allocation_id
    where a.order_id = p_order_id;
    v_new := case when v_short = 0 then 'delivered' when v_delivered = 0 then 'failed_delivery' else 'partially_delivered' end;
  elsif v_statuses <@ array['dispatched', 'delivered'] then
    v_new := 'dispatched';
  elsif v_statuses <@ array['packed', 'dispatched', 'delivered'] then
    v_new := 'packed';
  elsif v_statuses <@ array['batched', 'packed', 'dispatched', 'delivered'] then
    v_new := 'batched';
  else
    v_new := 'reserved';
  end if;
  update public.orders set status = v_new where id = p_order_id and status not in ('cancelled', 'rejected', 'settled');
end;
$$;

create function app.create_batch(p_warehouse_id uuid, p_order_ids uuid[])
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_warehouse_operator(p_warehouse_id, array['branch_manager', 'warehouse_staff']::public.member_role[]);
  v_id  uuid;
  v_order uuid;
begin
  insert into public.batches (org_id, warehouse_id, created_by)
  select org_id, id, v_uid from public.warehouses where id = p_warehouse_id
  returning id into v_id;

  update public.order_allocations
     set status = 'batched', batch_id = v_id
   where warehouse_id = p_warehouse_id and order_id = any(p_order_ids) and status = 'reserved';
  if not found then
    raise exception using errcode = 'SOL05', message = 'none of these orders has reserved stock at this warehouse';
  end if;
  for v_order in select distinct order_id from public.order_allocations where batch_id = v_id loop
    perform app.refresh_order_status(v_order);
  end loop;
  return v_id;
end;
$$;

create function app.mark_batch_packed(p_batch_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := app.require_user();
  v_batch public.batches;
  v_order uuid;
begin
  select * into v_batch from public.batches where id = p_batch_id for update;
  if not found or v_batch.status <> 'open' then
    raise exception using errcode = 'SOL04', message = 'only an open batch can be packed';
  end if;
  perform app.require_warehouse_operator(v_batch.warehouse_id, array['branch_manager', 'warehouse_staff']::public.member_role[]);
  update public.batches set status = 'packed', packed_by = v_uid, packed_at = now() where id = p_batch_id;
  update public.order_allocations set status = 'packed' where batch_id = p_batch_id and status = 'batched';
  for v_order in select distinct order_id from public.order_allocations where batch_id = p_batch_id loop
    perform app.refresh_order_status(v_order);
  end loop;
end;
$$;

-- Staff hand a packed batch to a driver (or agent). Nothing moves until the carrier accepts.
create function app.dispatch_batch(p_batch_id uuid, p_carrier_user_id uuid)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid     uuid := app.require_user();
  v_batch   public.batches;
  v_carrier uuid;
  v_id      uuid;
begin
  select * into v_batch from public.batches where id = p_batch_id for update;
  if not found or v_batch.status <> 'packed' then
    raise exception using errcode = 'SOL04', message = 'only a packed batch can be dispatched';
  end if;
  perform app.require_warehouse_operator(v_batch.warehouse_id, array['branch_manager', 'warehouse_staff']::public.member_role[]);
  if p_carrier_user_id = v_uid then
    raise exception using errcode = 'SOL03', message = 'you cannot dispatch to yourself';
  end if;
  select sl.id into v_carrier
  from public.stock_locations sl
  join public.memberships m on m.user_id = sl.user_id and m.org_id = sl.org_id and m.role::text = sl.kind::text
  where sl.user_id = p_carrier_user_id and sl.org_id = v_batch.org_id and sl.kind in ('driver', 'agent') and m.status = 'active'
  order by (sl.kind = 'driver') desc limit 1;   -- prefer the driver location if the person has both
  if v_carrier is null then
    raise exception using errcode = 'SOL05', message = 'carrier must be an active driver or agent of this distributor';
  end if;
  if exists (select 1 from public.shipments where carrier_location_id = v_carrier
             and status in ('awaiting_acceptance', 'open', 'returning', 'reconciling')) then
    raise exception using errcode = 'SOL04', message = 'this carrier still has an unfinished shipment';
  end if;

  insert into public.shipments (org_id, kind, warehouse_id, carrier_location_id, batch_id, dispatched_by)
  values (v_batch.org_id, 'delivery', v_batch.warehouse_id, v_carrier, p_batch_id, v_uid)
  returning id into v_id;
  return v_id;
end;
$$;

-- The carrier accepts in their own authenticated session: reserved stock is released and handed over
-- (warehouse -> carrier) in one movement group per shipment.
create function app.accept_dispatch(p_shipment_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := app.require_user();
  v_s     public.shipments;
  v_wh    uuid;
  v_alloc record;
  v_order uuid;
begin
  select * into v_s from public.shipments where id = p_shipment_id for update;
  if not found or v_s.status <> 'awaiting_acceptance' then
    raise exception using errcode = 'SOL04', message = 'shipment is not awaiting acceptance';
  end if;
  if (select user_id from public.stock_locations where id = v_s.carrier_location_id) <> v_uid then
    raise exception using errcode = 'SOL03', message = 'only the assigned carrier can accept this shipment';
  end if;
  v_wh := app.warehouse_location(v_s.warehouse_id);

  for v_alloc in
    select sku_id, sum(qty_pieces)::integer as qty from public.order_allocations
    where batch_id = v_s.batch_id and status = 'packed' group by sku_id order by sku_id
  loop
    perform app.post_stock_movement(p_shipment_id, 'release', v_wh, v_alloc.sku_id, v_alloc.qty, null, 'shipment', p_shipment_id, null, null);
    perform app.post_stock_movement(p_shipment_id, 'handover', v_wh, v_alloc.sku_id, v_alloc.qty, -1, 'shipment', p_shipment_id, null, null);
    perform app.post_stock_movement(p_shipment_id, 'handover', v_s.carrier_location_id, v_alloc.sku_id, v_alloc.qty, 1, 'shipment', p_shipment_id, null, null);
  end loop;

  update public.order_allocations set status = 'dispatched' where batch_id = v_s.batch_id and status = 'packed';
  update public.batches set status = 'dispatched' where id = v_s.batch_id;
  update public.shipments set status = 'open', accepted_at = now() where id = p_shipment_id;
  for v_order in select distinct order_id from public.order_allocations where batch_id = v_s.batch_id loop
    perform app.refresh_order_status(v_order);
  end loop;
end;
$$;

create function app.decline_dispatch(p_shipment_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
  v_s   public.shipments;
begin
  select * into v_s from public.shipments where id = p_shipment_id for update;
  if not found or v_s.status <> 'awaiting_acceptance' then
    raise exception using errcode = 'SOL04', message = 'shipment is not awaiting acceptance';
  end if;
  if (select user_id from public.stock_locations where id = v_s.carrier_location_id) <> v_uid then
    raise exception using errcode = 'SOL03', message = 'only the assigned carrier can decline this shipment';
  end if;
  -- Cancelled shipments don't count against the batch (partial unique index), so it can be re-dispatched.
  update public.shipments set status = 'cancelled', status_note = p_reason where id = p_shipment_id;
end;
$$;

-- e-POD. p_lines: [{"allocation_id","delivered","refused","damaged","missing"}], one per allocation of the
-- order in this shipment, each summing to the allocation quantity.
--   delivered -> sale at the carrier; damaged -> damage at the carrier;
--   refused   -> stays with the carrier and returns to the warehouse;
--   missing   -> stays on the carrier's ledger and surfaces at reconciliation (variance, Phase 5a).
-- Invoice: cumulative per order line, so partial deliveries always sum exactly to the line amount.
create function app.record_delivery(
  p_shipment_id uuid, p_order_id uuid, p_lines jsonb,
  p_lat double precision, p_lng double precision, p_accuracy_m double precision,
  p_photo_path text, p_recipient_name text, p_idempotency_key text
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid       uuid := app.require_user();
  v_s         public.shipments;
  v_order     public.orders;
  v_id        uuid;
  v_geo       record;
  v_line      record;
  v_total     bigint := 0;
  v_cum_prev  bigint;
  v_cum_new   bigint;
  v_journal   uuid;
begin
  select id into v_id from public.deliveries where idempotency_key = p_idempotency_key;
  if found then
    return (select jsonb_build_object('delivery_id', d.id, 'invoiced_kobo', d.invoiced_kobo::text,
                                      'geofence_ok', d.geofence_ok, 'geofence_reason', d.geofence_reason, 'replayed', true)
            from public.deliveries d where d.id = v_id);
  end if;

  select * into v_s from public.shipments where id = p_shipment_id for update;
  if not found or v_s.status <> 'open' then
    raise exception using errcode = 'SOL04', message = 'shipment is not open';
  end if;
  if (select user_id from public.stock_locations where id = v_s.carrier_location_id) <> v_uid then
    raise exception using errcode = 'SOL03', message = 'only the carrier can record deliveries for this shipment';
  end if;
  select * into strict v_order from public.orders where id = p_order_id;

  -- Lines must match this order's dispatched allocations in this shipment exactly.
  if exists (
    select 1 from public.order_allocations a
    left join jsonb_array_elements(p_lines) x on (x->>'allocation_id')::uuid = a.id
    where a.batch_id = v_s.batch_id and a.order_id = p_order_id and a.status = 'dispatched'
      and (x is null or (x->>'delivered')::integer + (x->>'refused')::integer
                      + (x->>'damaged')::integer + (x->>'missing')::integer <> a.qty_pieces)
  ) or exists (
    select 1 from jsonb_array_elements(p_lines) x
    left join public.order_allocations a on a.id = (x->>'allocation_id')::uuid
      and a.batch_id = v_s.batch_id and a.order_id = p_order_id and a.status = 'dispatched'
    where a.id is null
  ) or not exists (
    select 1 from public.order_allocations a where a.batch_id = v_s.batch_id and a.order_id = p_order_id and a.status = 'dispatched'
  ) then
    raise exception using errcode = 'SOL05',
      message = 'delivery lines must cover each dispatched allocation of this order once, with delivered+refused+damaged+missing = quantity';
  end if;

  if not exists (select 1 from storage.objects where bucket_id = 'epod' and name = p_photo_path) then
    raise exception using errcode = 'SOL05', message = 'the delivery photo has not been uploaded';
  end if;

  select * into v_geo from app.evaluate_geofence(v_order.distributor_org_id, v_order.retailer_org_id, p_lat, p_lng, p_accuracy_m);

  insert into public.deliveries (shipment_id, order_id, recorded_by, recipient_name, photo_path, lat, lng, accuracy_m,
                                 geofence_ok, geofence_reason, distance_m, idempotency_key)
  values (p_shipment_id, p_order_id, v_uid, p_recipient_name, p_photo_path, p_lat, p_lng, p_accuracy_m,
          v_geo.ok, v_geo.reason, v_geo.distance_m, p_idempotency_key)
  returning id into v_id;

  insert into public.delivery_lines (delivery_id, allocation_id, delivered, refused, damaged, missing)
  select v_id, (x->>'allocation_id')::uuid, (x->>'delivered')::integer, (x->>'refused')::integer,
         (x->>'damaged')::integer, (x->>'missing')::integer
  from jsonb_array_elements(p_lines) x;

  for v_line in
    select a.sku_id, sum(dl.delivered)::integer as delivered, sum(dl.damaged)::integer as damaged
    from public.delivery_lines dl join public.order_allocations a on a.id = dl.allocation_id
    where dl.delivery_id = v_id group by a.sku_id order by a.sku_id
  loop
    if v_line.delivered > 0 then
      perform app.post_stock_movement(v_id, 'sale', v_s.carrier_location_id, v_line.sku_id, v_line.delivered,
                                      null, 'shipment', p_shipment_id, null, null);
    end if;
    if v_line.damaged > 0 then
      perform app.post_stock_movement(v_id, 'damage', v_s.carrier_location_id, v_line.sku_id, v_line.damaged,
                                      null, 'shipment', p_shipment_id, 'damaged at delivery', null);
    end if;
  end loop;

  update public.order_allocations a set status = 'delivered'
    from public.delivery_lines dl where dl.delivery_id = v_id and dl.allocation_id = a.id;

  -- Cumulative invoicing per order line.
  for v_line in
    select l.id, l.qty_pieces, l.line_amount_kobo,
           coalesce(sum(dl.delivered) filter (where dl.delivery_id <> v_id), 0)::bigint as before,
           coalesce(sum(dl.delivered), 0)::bigint as after
    from public.order_lines l
    join public.order_allocations a on a.order_line_id = l.id
    left join public.delivery_lines dl on dl.allocation_id = a.id
    where l.order_id = p_order_id
    group by l.id, l.qty_pieces, l.line_amount_kobo
  loop
    v_cum_prev := app.round_div(v_line.line_amount_kobo * v_line.before, v_line.qty_pieces, 'half_even');
    v_cum_new  := app.round_div(v_line.line_amount_kobo * v_line.after, v_line.qty_pieces, 'half_even');
    v_total := v_total + (v_cum_new - v_cum_prev);
  end loop;

  if v_total > 0 then
    v_journal := app.post_journal(
      'delivery_invoiced', 'delivery:' || v_id,
      jsonb_build_array(
        jsonb_build_object('account_id', app.ensure_account(v_order.distributor_org_id, 'receivables',
                                                            p_counterparty_org_id => v_order.retailer_org_id),
                           'amount_kobo', v_total::text),
        jsonb_build_object('account_id', app.ensure_account(v_order.distributor_org_id, 'sales_revenue'),
                           'amount_kobo', (-v_total)::text)),
      'delivery', v_id, 'goods delivered');
    update public.deliveries set invoiced_kobo = v_total, journal_id = v_journal where id = v_id;
  end if;

  perform app.refresh_order_status(p_order_id);
  return jsonb_build_object('delivery_id', v_id, 'invoiced_kobo', v_total::text,
                            'geofence_ok', v_geo.ok, 'geofence_reason', v_geo.reason, 'replayed', false);
end;
$$;

create function app.confirm_delivery(p_order_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform app.require_role((select retailer_org_id from public.orders where id = p_order_id), array['retailer']::public.member_role[]);
  update public.orders set confirmed_at = now()
   where id = p_order_id and status in ('delivered', 'partially_delivered', 'failed_delivery') and confirmed_at is null;
  if not found then
    raise exception using errcode = 'SOL04', message = 'only a delivered, unconfirmed order can be confirmed';
  end if;
end;
$$;

create function app.dispute_delivery(p_order_id uuid, p_reason text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_role((select retailer_org_id from public.orders where id = p_order_id),
                                 array['retailer']::public.member_role[]);
  v_id  uuid;
begin
  if not exists (select 1 from public.deliveries where order_id = p_order_id) then
    raise exception using errcode = 'SOL04', message = 'nothing has been delivered on this order yet';
  end if;
  insert into public.order_disputes (order_id, raised_by, reason) values (p_order_id, v_uid, p_reason) returning id into v_id;
  return v_id;
end;
$$;

-- Warehouse staff count what comes back: [{"sku_id","qty_pieces"}] (may be empty). Every order in the
-- shipment must have its delivery recorded first.
create function app.start_return(p_shipment_id uuid, p_lines jsonb)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
  v_s   public.shipments;
begin
  select * into v_s from public.shipments where id = p_shipment_id for update;
  if not found or v_s.status <> 'open' then
    raise exception using errcode = 'SOL04', message = 'shipment is not open';
  end if;
  perform app.require_warehouse_operator(v_s.warehouse_id, array['branch_manager', 'warehouse_staff']::public.member_role[]);
  if (select user_id from public.stock_locations where id = v_s.carrier_location_id) = v_uid then
    raise exception using errcode = 'SOL03', message = 'the carrier cannot count their own return';
  end if;
  if exists (select 1 from public.order_allocations where batch_id = v_s.batch_id and status = 'dispatched') then
    raise exception using errcode = 'SOL04', message = 'record every delivery on this shipment before the return';
  end if;
  if exists (
    select 1 from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) x
    left join public.stock_balances b on b.location_id = v_s.carrier_location_id and b.sku_id = (x->>'sku_id')::uuid
    where (x->>'qty_pieces')::integer <= 0 or coalesce(b.on_hand, 0) < (x->>'qty_pieces')::integer
  ) then
    raise exception using errcode = 'SOL05', message = 'returned quantities must be positive and not exceed what the carrier holds';
  end if;

  insert into public.shipment_returns (shipment_id, sku_id, qty_pieces, counted_by)
  select p_shipment_id, (x->>'sku_id')::uuid, (x->>'qty_pieces')::integer, v_uid
  from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) x;
  update public.shipments set status = 'returning' where id = p_shipment_id;
end;
$$;

-- The carrier agrees with the count in their own session: return legs are posted. If the carrier then
-- holds nothing, the shipment closes; otherwise it stays 'reconciling' (variance handling: Phase 5a).
create function app.confirm_return(p_shipment_id uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid       uuid := app.require_user();
  v_s         public.shipments;
  v_wh        uuid;
  v_line      record;
  v_remaining bigint;
begin
  select * into v_s from public.shipments where id = p_shipment_id for update;
  if not found or v_s.status <> 'returning' then
    raise exception using errcode = 'SOL04', message = 'shipment has no return awaiting confirmation';
  end if;
  if (select user_id from public.stock_locations where id = v_s.carrier_location_id) <> v_uid then
    raise exception using errcode = 'SOL03', message = 'only the carrier can confirm the return count';
  end if;
  v_wh := app.warehouse_location(v_s.warehouse_id);
  for v_line in select sku_id, qty_pieces from public.shipment_returns where shipment_id = p_shipment_id order by sku_id loop
    perform app.post_stock_movement(p_shipment_id, 'return', v_s.carrier_location_id, v_line.sku_id, v_line.qty_pieces, -1, 'shipment', p_shipment_id, null, null);
    perform app.post_stock_movement(p_shipment_id, 'return', v_wh, v_line.sku_id, v_line.qty_pieces, 1, 'shipment', p_shipment_id, null, null);
  end loop;
  update public.shipment_returns set confirmed_at = now() where shipment_id = p_shipment_id;

  select coalesce(sum(on_hand), 0) into v_remaining from public.stock_balances where location_id = v_s.carrier_location_id;
  update public.shipments
     set status = case when v_remaining = 0 then 'closed' else 'reconciling' end,
         closed_at = case when v_remaining = 0 then now() end,
         status_note = case when v_remaining = 0 then null else format('%s pieces unaccounted for: variance review required', v_remaining) end
   where id = p_shipment_id;
  return case when v_remaining = 0 then 'closed' else 'reconciling' end;
end;
$$;

-- Close once the carrier holds nothing (after variance resolution in Phase 5a).
create function app.close_shipment(p_shipment_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_s public.shipments;
begin
  select * into v_s from public.shipments where id = p_shipment_id for update;
  if not found or v_s.status <> 'reconciling' then
    raise exception using errcode = 'SOL04', message = 'only a reconciling shipment can be closed';
  end if;
  perform app.require_warehouse_operator(v_s.warehouse_id, array['branch_manager']::public.member_role[]);
  if exists (select 1 from public.stock_balances where location_id = v_s.carrier_location_id and on_hand <> 0) then
    raise exception using errcode = 'SOL04', message = 'the carrier still holds unreconciled stock; resolve the variance first';
  end if;
  update public.shipments set status = 'closed', closed_at = now(), status_note = null where id = p_shipment_id;
end;
$$;

-- picked_up = sold + returned + damaged + remaining, per shipment and SKU (remaining = unreconciled).
create view public.v_shipment_reconciliation with (security_invoker = true) as
select s.id as shipment_id, s.org_id, s.status, m.sku_id,
       sum(m.qty) filter (where m.movement_type = 'handover' and m.on_hand_delta > 0) as picked_up,
       coalesce(sum(m.qty) filter (where m.movement_type = 'sale'), 0) as sold,
       coalesce(sum(m.qty) filter (where m.movement_type = 'return' and m.on_hand_delta < 0), 0) as returned,
       coalesce(sum(m.qty) filter (where m.movement_type = 'damage'), 0) as damaged,
       sum(m.on_hand_delta) as remaining
from public.shipments s
join public.stock_movements m on m.ref_kind = 'shipment' and m.ref_id = s.id and m.location_id = s.carrier_location_id
group by s.id, s.org_id, s.status, m.sku_id;

-- Global stock conservation per SKU: what exists = what came in - what went out - what is in transit.
create function app.check_stock_conservation()
returns table (sku_id uuid, on_hand_total bigint, expected bigint)
language sql stable security definer set search_path = ''
as $$
  with m as (
    select sku_id,
           sum(case when movement_type = 'receipt' then qty else 0 end)
         + sum(case when movement_type = 'adjustment' then on_hand_delta else 0 end)
         - sum(case when movement_type in ('sale', 'damage') then qty else 0 end)
         - (sum(case when movement_type = 'transfer_out' then qty else 0 end)
            - sum(case when movement_type = 'transfer_in' then qty else 0 end)) as expected
    from public.stock_movements group by sku_id
  ), b as (
    select sku_id, sum(on_hand)::bigint as on_hand_total from public.stock_balances group by sku_id
  )
  select coalesce(m.sku_id, b.sku_id), coalesce(b.on_hand_total, 0), coalesce(m.expected, 0)
  from m full join b on b.sku_id = m.sku_id
  where coalesce(b.on_hand_total, 0) <> coalesce(m.expected, 0)
$$;
