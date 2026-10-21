-- Push flow (Phase 5a): agent stock request -> approval -> OTP handover -> geofenced sales -> OTP-verified
-- return with damage -> variance cases (pending until a manager writes off or charges the agent) ->
-- shipment closes only when the carrier holds nothing and no case is pending.

create table public.stock_requests (
  id                  uuid primary key default gen_random_uuid(),
  org_id              uuid not null references public.organisations (id),
  warehouse_id        uuid not null references public.warehouses (id),
  agent_user_id       uuid not null references public.profiles (user_id),
  carrier_location_id uuid not null references public.stock_locations (id),
  status              text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  note                text check (length(note) <= 500),
  decided_by          uuid references public.profiles (user_id),
  decided_at          timestamptz,
  decision_reason     text,
  shipment_id         uuid references public.shipments (id),
  created_at          timestamptz not null default now()
);
create index stock_requests_wh_status_idx on public.stock_requests (warehouse_id, status);

create table public.stock_request_lines (
  id           uuid primary key default gen_random_uuid(),
  request_id   uuid not null references public.stock_requests (id),
  sku_id       uuid not null references public.skus (id),
  qty_pieces   integer not null check (qty_pieces > 0),
  qty_approved integer check (qty_approved >= 0 and qty_approved <= qty_pieces),
  unique (request_id, sku_id)
);

create table public.shipment_lines (
  id          uuid primary key default gen_random_uuid(),
  shipment_id uuid not null references public.shipments (id),
  sku_id      uuid not null references public.skus (id),
  qty_pieces  integer not null check (qty_pieces > 0),
  unique (shipment_id, sku_id)
);

create table public.push_sales (
  id              uuid primary key default gen_random_uuid(),
  shipment_id     uuid not null references public.shipments (id),
  retailer_org_id uuid not null references public.organisations (id),
  agent_user_id   uuid not null references public.profiles (user_id),
  lat             double precision not null,
  lng             double precision not null,
  accuracy_m      double precision not null,
  distance_m      integer,
  total_kobo      bigint not null check (total_kobo > 0),
  journal_id      uuid references public.journals (id),
  idempotency_key text not null unique check (length(idempotency_key) >= 8),
  created_at      timestamptz not null default now()
);
create index push_sales_shipment_idx on public.push_sales (shipment_id);

create table public.push_sale_lines (
  id              uuid primary key default gen_random_uuid(),
  sale_id         uuid not null references public.push_sales (id),
  sku_id          uuid not null references public.skus (id),
  qty_pieces      integer not null check (qty_pieces > 0),
  unit_price_kobo bigint not null check (unit_price_kobo > 0),
  amount_kobo     bigint generated always as (qty_pieces::bigint * unit_price_kobo) stored
);

alter table public.shipment_returns
  add column damaged integer not null default 0 check (damaged >= 0),
  drop constraint shipment_returns_qty_pieces_check,
  add constraint shipment_returns_something_counted check (qty_pieces >= 0 and qty_pieces + damaged > 0);

create table public.variance_cases (
  id                  uuid primary key default gen_random_uuid(),
  shipment_id         uuid not null references public.shipments (id),
  org_id              uuid not null references public.organisations (id),
  carrier_user_id     uuid not null references public.profiles (user_id),
  sku_id              uuid not null references public.skus (id),
  qty_pieces          integer not null check (qty_pieces > 0),
  value_kobo          bigint not null check (value_kobo >= 0),
  status              text not null default 'pending' check (status in ('pending', 'written_off', 'charged_to_agent')),
  raised_journal_id   uuid references public.journals (id),
  resolved_journal_id uuid references public.journals (id),
  resolved_by         uuid references public.profiles (user_id),
  resolution_note     text,
  created_at          timestamptz not null default now(),
  resolved_at         timestamptz,
  unique (shipment_id, sku_id)
);
create index variance_cases_org_status_idx on public.variance_cases (org_id, status);

-- Per-piece value for variance/sales: the piece price, else the carton price divided (half-even).
create function app.piece_price_kobo(p_distributor_id uuid, p_sku_id uuid)
returns bigint
language sql stable security definer set search_path = ''
as $$
  select coalesce(
    app.current_price_kobo(p_distributor_id, p_sku_id, 'piece'),
    (select app.round_div(app.current_price_kobo(p_distributor_id, p_sku_id, u.uom_code), u.pieces_per_uom, 'half_even')
     from public.sku_uom u where u.sku_id = p_sku_id and u.uom_code = 'carton'
       and app.current_price_kobo(p_distributor_id, p_sku_id, 'carton') is not null))
$$;

create function app.request_stock(p_warehouse_id uuid, p_lines jsonb, p_note text default null)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
  v_org uuid;
  v_loc uuid;
  v_id  uuid;
begin
  select org_id into v_org from public.warehouses where id = p_warehouse_id and active;
  if v_org is null then
    raise exception using errcode = 'SOL05', message = 'unknown or inactive warehouse';
  end if;
  perform app.require_role(v_org, array['agent']::public.member_role[]);
  select id into strict v_loc from public.stock_locations where user_id = v_uid and org_id = v_org and kind = 'agent';
  insert into public.stock_requests (org_id, warehouse_id, agent_user_id, carrier_location_id, note)
  values (v_org, p_warehouse_id, v_uid, v_loc, p_note) returning id into v_id;
  insert into public.stock_request_lines (request_id, sku_id, qty_pieces)
  select v_id, p.sku_id, sum(p.qty_pieces)::integer from app.lines_to_pieces(p_lines) p group by p.sku_id;
  return v_id;
end;
$$;

-- p_approved: [{"sku_id","qty_pieces"}] or null to approve as requested. Creates the push shipment.
create function app.decide_stock_request(p_request_id uuid, p_approve boolean, p_approved jsonb default null, p_reason text default null)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
  v_req public.stock_requests;
  v_ship uuid;
begin
  select * into v_req from public.stock_requests where id = p_request_id for update;
  if not found or v_req.status <> 'pending' then
    raise exception using errcode = 'SOL04', message = 'request is not pending';
  end if;
  perform app.require_warehouse_operator(v_req.warehouse_id, array['branch_manager']::public.member_role[]);
  if v_uid = v_req.agent_user_id then
    raise exception using errcode = 'SOL03', message = 'you cannot approve your own stock request';
  end if;
  if not p_approve then
    if nullif(btrim(p_reason), '') is null then
      raise exception using errcode = 'SOL05', message = 'a reason is required to reject';
    end if;
    update public.stock_requests set status = 'rejected', decided_by = v_uid, decided_at = now(), decision_reason = p_reason
     where id = p_request_id;
    return null;
  end if;
  if exists (select 1 from public.shipments where carrier_location_id = v_req.carrier_location_id
             and status in ('awaiting_acceptance', 'open', 'returning', 'reconciling')) then
    raise exception using errcode = 'SOL04', message = 'this agent still has an unfinished shipment';
  end if;

  update public.stock_request_lines l
     set qty_approved = coalesce((select (a->>'qty_pieces')::integer from jsonb_array_elements(p_approved) a
                                  where (a->>'sku_id')::uuid = l.sku_id), case when p_approved is null then l.qty_pieces else 0 end)
   where l.request_id = p_request_id;
  if not exists (select 1 from public.stock_request_lines where request_id = p_request_id and qty_approved > 0) then
    raise exception using errcode = 'SOL05', message = 'approve at least one piece, or reject the request';
  end if;

  insert into public.shipments (org_id, kind, warehouse_id, carrier_location_id, dispatched_by)
  values (v_req.org_id, 'push', v_req.warehouse_id, v_req.carrier_location_id, v_uid)
  returning id into v_ship;
  insert into public.shipment_lines (shipment_id, sku_id, qty_pieces)
  select v_ship, sku_id, qty_approved from public.stock_request_lines where request_id = p_request_id and qty_approved > 0;
  update public.stock_requests set status = 'approved', decided_by = v_uid, decided_at = now(),
         decision_reason = p_reason, shipment_id = v_ship where id = p_request_id;
  return v_ship;
end;
$$;

-- Warehouse staff start the handover: availability is checked now and again at verification.
create function app.start_handover(p_shipment_id uuid)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := app.require_user();
  v_s     public.shipments;
  v_agent uuid;
begin
  select * into v_s from public.shipments where id = p_shipment_id for update;
  if not found or v_s.kind <> 'push' or v_s.status <> 'awaiting_acceptance' then
    raise exception using errcode = 'SOL04', message = 'shipment is not awaiting handover';
  end if;
  perform app.require_warehouse_operator(v_s.warehouse_id, array['branch_manager', 'warehouse_staff']::public.member_role[]);
  select user_id into strict v_agent from public.stock_locations where id = v_s.carrier_location_id;
  if v_agent = v_uid then
    raise exception using errcode = 'SOL03', message = 'you cannot hand stock over to yourself';
  end if;
  if exists (
    select 1 from public.shipment_lines l
    left join public.stock_balances b on b.location_id = app.warehouse_location(v_s.warehouse_id) and b.sku_id = l.sku_id
    where l.shipment_id = p_shipment_id and coalesce(b.available, 0) < l.qty_pieces
  ) then
    raise exception using errcode = 'SOL01', message = 'insufficient_stock', detail = 'the warehouse cannot cover this handover';
  end if;
  return app.open_otp_challenge('handover', 'shipment', p_shipment_id, v_uid, v_agent);
end;
$$;

-- Internal, run by verify_otp: warehouse -> agent, one movement group (CHECKs forbid taking reserved stock).
create function app.complete_push_handover(p_shipment_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_s    public.shipments;
  v_wh   uuid;
  v_line record;
begin
  select * into v_s from public.shipments where id = p_shipment_id for update;
  if v_s.status <> 'awaiting_acceptance' then
    raise exception using errcode = 'SOL04', message = 'shipment is not awaiting handover';
  end if;
  v_wh := app.warehouse_location(v_s.warehouse_id);
  for v_line in select sku_id, qty_pieces from public.shipment_lines where shipment_id = p_shipment_id order by sku_id loop
    perform app.post_stock_movement(p_shipment_id, 'handover', v_wh, v_line.sku_id, v_line.qty_pieces, -1, 'shipment', p_shipment_id, null, null);
    perform app.post_stock_movement(p_shipment_id, 'handover', v_s.carrier_location_id, v_line.sku_id, v_line.qty_pieces, 1, 'shipment', p_shipment_id, null, null);
  end loop;
  update public.shipments set status = 'open', accepted_at = now() where id = p_shipment_id;
end;
$$;

-- Internal core of a push sale (the online command below and, in Phase 5b, offline sync events).
-- Fails closed: geofence must pass, carried stock must cover, price must exist.
create function app.apply_push_sale(
  p_shipment_id uuid, p_agent_user_id uuid, p_retailer_org_id uuid, p_lines jsonb,
  p_lat double precision, p_lng double precision, p_accuracy_m double precision, p_idempotency_key text
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_s     public.shipments;
  v_geo   record;
  v_id    uuid;
  v_line  record;
  v_price bigint;
  v_total bigint := 0;
  v_jid   uuid;
begin
  select id into v_id from public.push_sales where idempotency_key = p_idempotency_key;
  if found then
    return (select jsonb_build_object('sale_id', id, 'total_kobo', total_kobo::text, 'replayed', true)
            from public.push_sales where id = v_id);
  end if;
  select * into v_s from public.shipments where id = p_shipment_id for update;
  if not found or v_s.kind <> 'push' or v_s.status <> 'open' then
    raise exception using errcode = 'SOL04', message = 'shipment_closed';
  end if;
  if (select user_id from public.stock_locations where id = v_s.carrier_location_id) <> p_agent_user_id then
    raise exception using errcode = 'SOL03', message = 'not_owner';
  end if;
  select * into v_geo from app.evaluate_geofence(v_s.org_id, p_retailer_org_id, p_lat, p_lng, p_accuracy_m);
  if not v_geo.ok then
    raise exception using errcode = 'SOL05', message = 'outside_geofence', detail = v_geo.reason;
  end if;
  if exists (
    select 1 from (select (x->>'sku_id')::uuid as sku_id, sum((x->>'qty_pieces')::integer) as qty
                   from jsonb_array_elements(p_lines) x group by 1) n
    left join public.stock_balances b on b.location_id = v_s.carrier_location_id and b.sku_id = n.sku_id
    where n.qty <= 0 or coalesce(b.on_hand, 0) < n.qty
  ) then
    raise exception using errcode = 'SOL01', message = 'insufficient_carried_stock';
  end if;

  insert into public.push_sales (shipment_id, retailer_org_id, agent_user_id, lat, lng, accuracy_m, distance_m, total_kobo, idempotency_key)
  values (p_shipment_id, p_retailer_org_id, p_agent_user_id, p_lat, p_lng, p_accuracy_m, v_geo.distance_m, 1, p_idempotency_key)
  returning id into v_id;
  for v_line in select (x->>'sku_id')::uuid as sku_id, sum((x->>'qty_pieces')::integer)::integer as qty
                from jsonb_array_elements(p_lines) x group by 1 order by 1 loop
    v_price := app.piece_price_kobo(v_s.org_id, v_line.sku_id);
    if v_price is null then
      raise exception using errcode = 'SOL05', message = 'price_mismatch', detail = format('no price for sku %s', v_line.sku_id);
    end if;
    insert into public.push_sale_lines (sale_id, sku_id, qty_pieces, unit_price_kobo) values (v_id, v_line.sku_id, v_line.qty, v_price);
    perform app.post_stock_movement(v_id, 'sale', v_s.carrier_location_id, v_line.sku_id, v_line.qty, null, 'shipment', p_shipment_id, null, null);
    v_total := v_total + v_line.qty::bigint * v_price;
  end loop;

  v_jid := app.post_journal('cash_collected', 'push_sale:' || v_id, jsonb_build_array(
    jsonb_build_object('account_id', app.ensure_account(v_s.org_id, 'cash_in_transit', p_counterparty_user_id => p_agent_user_id),
                       'amount_kobo', v_total::text),
    jsonb_build_object('account_id', app.ensure_account(v_s.org_id, 'sales_revenue'), 'amount_kobo', (-v_total)::text)),
    'push_sale', v_id, 'cash sale by agent');
  update public.push_sales set total_kobo = v_total, journal_id = v_jid where id = v_id;
  return jsonb_build_object('sale_id', v_id, 'total_kobo', v_total::text, 'replayed', false);
end;
$$;

create function app.record_push_sale(
  p_shipment_id uuid, p_retailer_org_id uuid, p_lines jsonb,
  p_lat double precision, p_lng double precision, p_accuracy_m double precision, p_idempotency_key text
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
begin
  if not (p_retailer_org_id = any(app.visible_retailer_ids())) then
    raise exception using errcode = 'SOL03', message = 'unknown_retailer';
  end if;
  return app.apply_push_sale(p_shipment_id, v_uid, p_retailer_org_id, p_lines, p_lat, p_lng, p_accuracy_m, p_idempotency_key);
end;
$$;

-- Staff count the push return: [{"sku_id","qty_pieces","damaged"}]. The OTP binds this exact count.
create function app.start_push_return(p_shipment_id uuid, p_lines jsonb)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := app.require_user();
  v_s     public.shipments;
  v_agent uuid;
  v_hash  text;
begin
  select * into v_s from public.shipments where id = p_shipment_id for update;
  if not found or v_s.kind <> 'push' or v_s.status not in ('open', 'returning') then
    raise exception using errcode = 'SOL04', message = 'shipment is not open for a return';
  end if;
  perform app.require_warehouse_operator(v_s.warehouse_id, array['branch_manager', 'warehouse_staff']::public.member_role[]);
  select user_id into strict v_agent from public.stock_locations where id = v_s.carrier_location_id;
  if v_agent = v_uid then
    raise exception using errcode = 'SOL03', message = 'the agent cannot count their own return';
  end if;
  if exists (
    select 1 from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) x
    left join public.stock_balances b on b.location_id = v_s.carrier_location_id and b.sku_id = (x->>'sku_id')::uuid
    where coalesce((x->>'qty_pieces')::integer, 0) < 0 or coalesce((x->>'damaged')::integer, 0) < 0
       or coalesce(b.on_hand, 0) < coalesce((x->>'qty_pieces')::integer, 0) + coalesce((x->>'damaged')::integer, 0)
  ) then
    raise exception using errcode = 'SOL05', message = 'returned + damaged cannot exceed what the agent carries';
  end if;

  delete from public.shipment_returns where shipment_id = p_shipment_id and confirmed_at is null;
  insert into public.shipment_returns (shipment_id, sku_id, qty_pieces, damaged, counted_by)
  select p_shipment_id, (x->>'sku_id')::uuid, coalesce((x->>'qty_pieces')::integer, 0), coalesce((x->>'damaged')::integer, 0), v_uid
  from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) x
  where coalesce((x->>'qty_pieces')::integer, 0) + coalesce((x->>'damaged')::integer, 0) > 0;
  update public.shipments set status = 'returning' where id = p_shipment_id;

  select md5(coalesce(string_agg(format('%s:%s:%s', sku_id, qty_pieces, damaged), ',' order by sku_id), ''))
    into v_hash from public.shipment_returns where shipment_id = p_shipment_id and confirmed_at is null;
  return app.open_otp_challenge('return', 'shipment', p_shipment_id, v_uid, v_agent, v_hash);
end;
$$;

-- Internal: after a return, whatever the carrier still holds becomes pending variance cases (valued at
-- the per-piece price) with a variance_raised journal each. Closes the shipment if nothing remains.
create function app.settle_carrier(p_shipment_id uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_s     public.shipments;
  v_agent uuid;
  v_rem   record;
  v_value bigint;
  v_case  uuid;
  v_jid   uuid;
  v_total bigint := 0;
begin
  select * into strict v_s from public.shipments where id = p_shipment_id;
  select user_id into strict v_agent from public.stock_locations where id = v_s.carrier_location_id;
  for v_rem in select sku_id, on_hand from public.stock_balances
               where location_id = v_s.carrier_location_id and on_hand > 0 order by sku_id loop
    v_total := v_total + v_rem.on_hand;
    v_value := coalesce(app.piece_price_kobo(v_s.org_id, v_rem.sku_id), 0) * v_rem.on_hand;
    insert into public.variance_cases (shipment_id, org_id, carrier_user_id, sku_id, qty_pieces, value_kobo)
    values (p_shipment_id, v_s.org_id, v_agent, v_rem.sku_id, v_rem.on_hand, v_value)
    on conflict (shipment_id, sku_id) do nothing
    returning id into v_case;
    if v_case is not null and v_value > 0 then
      v_jid := app.post_journal('variance_raised', 'variance_raised:' || v_case, jsonb_build_array(
        jsonb_build_object('account_id', app.ensure_account(v_s.org_id, 'variance', p_counterparty_user_id => v_agent), 'amount_kobo', v_value::text),
        jsonb_build_object('account_id', app.ensure_account(v_s.org_id, 'variance_offset'), 'amount_kobo', (-v_value)::text)),
        'variance_case', v_case, 'unreconciled stock after return');
      update public.variance_cases set raised_journal_id = v_jid where id = v_case;
    end if;
  end loop;

  if v_total = 0 then
    update public.shipments set status = 'closed', closed_at = now(), status_note = null where id = p_shipment_id;
    return 'closed';
  end if;
  update public.shipments
     set status = 'reconciling', status_note = format('%s pieces unaccounted for: variance pending approval', v_total)
   where id = p_shipment_id;
  return 'reconciling';
end;
$$;

-- Internal, run by verify_otp after the agent agrees with the count.
create function app.complete_push_return(p_shipment_id uuid, p_payload_hash text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_s    public.shipments;
  v_wh   uuid;
  v_line record;
  v_hash text;
begin
  select * into v_s from public.shipments where id = p_shipment_id for update;
  if v_s.status <> 'returning' then
    raise exception using errcode = 'SOL04', message = 'shipment has no return awaiting confirmation';
  end if;
  select md5(coalesce(string_agg(format('%s:%s:%s', sku_id, qty_pieces, damaged), ',' order by sku_id), ''))
    into v_hash from public.shipment_returns where shipment_id = p_shipment_id and confirmed_at is null;
  if v_hash is distinct from p_payload_hash then
    raise exception using errcode = 'SOL04', message = 'the return count changed after the code was sent; recount';
  end if;
  v_wh := app.warehouse_location(v_s.warehouse_id);
  for v_line in select sku_id, qty_pieces, damaged from public.shipment_returns
                where shipment_id = p_shipment_id and confirmed_at is null order by sku_id loop
    if v_line.qty_pieces > 0 then
      perform app.post_stock_movement(p_shipment_id, 'return', v_s.carrier_location_id, v_line.sku_id, v_line.qty_pieces, -1, 'shipment', p_shipment_id, null, null);
      perform app.post_stock_movement(p_shipment_id, 'return', v_wh, v_line.sku_id, v_line.qty_pieces, 1, 'shipment', p_shipment_id, null, null);
    end if;
    if v_line.damaged > 0 then
      perform app.post_stock_movement(p_shipment_id, 'damage', v_s.carrier_location_id, v_line.sku_id, v_line.damaged, null, 'shipment', p_shipment_id, 'reported damaged at return', null);
    end if;
  end loop;
  update public.shipment_returns set confirmed_at = now() where shipment_id = p_shipment_id and confirmed_at is null;
  return app.settle_carrier(p_shipment_id);
end;
$$;

-- Delivery runs now raise variance cases too, instead of only a note.
create or replace function app.confirm_return(p_shipment_id uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid  uuid := app.require_user();
  v_s    public.shipments;
  v_wh   uuid;
  v_line record;
begin
  select * into v_s from public.shipments where id = p_shipment_id for update;
  if not found or v_s.status <> 'returning' or v_s.kind <> 'delivery' then
    raise exception using errcode = 'SOL04', message = 'shipment has no delivery return awaiting confirmation';
  end if;
  if (select user_id from public.stock_locations where id = v_s.carrier_location_id) <> v_uid then
    raise exception using errcode = 'SOL03', message = 'only the carrier can confirm the return count';
  end if;
  v_wh := app.warehouse_location(v_s.warehouse_id);
  for v_line in select sku_id, qty_pieces, damaged from public.shipment_returns
                where shipment_id = p_shipment_id and confirmed_at is null order by sku_id loop
    if v_line.qty_pieces > 0 then
      perform app.post_stock_movement(p_shipment_id, 'return', v_s.carrier_location_id, v_line.sku_id, v_line.qty_pieces, -1, 'shipment', p_shipment_id, null, null);
      perform app.post_stock_movement(p_shipment_id, 'return', v_wh, v_line.sku_id, v_line.qty_pieces, 1, 'shipment', p_shipment_id, null, null);
    end if;
    if v_line.damaged > 0 then
      perform app.post_stock_movement(p_shipment_id, 'damage', v_s.carrier_location_id, v_line.sku_id, v_line.damaged, null, 'shipment', p_shipment_id, 'reported damaged at return', null);
    end if;
  end loop;
  update public.shipment_returns set confirmed_at = now() where shipment_id = p_shipment_id and confirmed_at is null;
  return app.settle_carrier(p_shipment_id);
end;
$$;

-- A manager (not the carrier) resolves a pending case: the units leave the carrier's ledger as an
-- adjustment, and the money side is cleared (written off) or turned into a receivable from the agent.
create function app.resolve_variance(p_case_id uuid, p_decision text, p_note text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
  v_c   public.variance_cases;
  v_s   public.shipments;
  v_entries jsonb;
  v_jid uuid;
begin
  select * into v_c from public.variance_cases where id = p_case_id for update;
  if not found or v_c.status <> 'pending' then
    raise exception using errcode = 'SOL04', message = 'variance case is not pending';
  end if;
  select * into strict v_s from public.shipments where id = v_c.shipment_id for update;
  perform app.require_warehouse_operator(v_s.warehouse_id, array['branch_manager']::public.member_role[]);
  if v_uid = v_c.carrier_user_id then
    raise exception using errcode = 'SOL03', message = 'you cannot resolve variance on your own shipment';
  end if;
  if p_decision not in ('write_off', 'charge_agent') then
    raise exception using errcode = 'SOL05', message = 'decision must be write_off or charge_agent';
  end if;
  if nullif(btrim(p_note), '') is null then
    raise exception using errcode = 'SOL05', message = 'a note is required';
  end if;

  perform app.post_stock_movement(p_case_id, 'adjustment', v_s.carrier_location_id, v_c.sku_id, v_c.qty_pieces, -1,
                                  'variance_case', p_case_id, p_decision || ': ' || p_note, null);
  if v_c.value_kobo > 0 then
    v_entries := jsonb_build_array(
      jsonb_build_object('account_id', app.ensure_account(v_s.org_id, 'variance_offset'), 'amount_kobo', v_c.value_kobo::text),
      jsonb_build_object('account_id', app.ensure_account(v_s.org_id, 'variance', p_counterparty_user_id => v_c.carrier_user_id), 'amount_kobo', (-v_c.value_kobo)::text));
    if p_decision = 'charge_agent' then
      v_entries := v_entries || jsonb_build_array(
        jsonb_build_object('account_id', app.ensure_account(v_s.org_id, 'receivables', p_counterparty_user_id => v_c.carrier_user_id), 'amount_kobo', v_c.value_kobo::text),
        jsonb_build_object('account_id', app.ensure_account(v_s.org_id, 'sales_revenue'), 'amount_kobo', (-v_c.value_kobo)::text));
    end if;
    v_jid := app.post_journal(case when p_decision = 'write_off' then 'variance_written_off' else 'variance_charged' end,
                              'variance_resolved:' || p_case_id, v_entries, 'variance_case', p_case_id, p_note);
  end if;
  update public.variance_cases
     set status = case when p_decision = 'write_off' then 'written_off' else 'charged_to_agent' end,
         resolved_journal_id = v_jid, resolved_by = v_uid, resolution_note = p_note, resolved_at = now()
   where id = p_case_id;

  if not exists (select 1 from public.variance_cases where shipment_id = v_s.id and status = 'pending')
     and not exists (select 1 from public.stock_balances where location_id = v_s.carrier_location_id and on_hand <> 0) then
    update public.shipments set status = 'closed', closed_at = now(), status_note = null where id = v_s.id;
    return 'closed';
  end if;
  return 'pending';
end;
$$;

-- close_shipment also refuses while any variance case is pending.
create or replace function app.close_shipment(p_shipment_id uuid)
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
  if exists (select 1 from public.variance_cases where shipment_id = p_shipment_id and status = 'pending')
     or exists (select 1 from public.stock_balances where location_id = v_s.carrier_location_id and on_hand <> 0) then
    raise exception using errcode = 'SOL04', message = 'the carrier still holds unreconciled stock; resolve the variance first';
  end if;
  update public.shipments set status = 'closed', closed_at = now(), status_note = null where id = p_shipment_id;
end;
$$;
