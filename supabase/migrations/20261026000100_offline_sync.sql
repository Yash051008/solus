-- Offline agent sync (hard rule 4, Phase 5b-2). Devices send EVENTS with client UUIDs and a per-device
-- monotonic seq. Each event is applied in its own subtransaction; rejections are stored with a reason and
-- open a review item (never dropped). Replays return the stored result. A seq gap defers later events.

create table public.agent_devices (
  device_id     uuid primary key,
  user_id       uuid not null references public.profiles (user_id),
  org_id        uuid not null references public.organisations (id),
  last_seq      bigint not null default 0,
  registered_at timestamptz not null default now(),
  last_sync_at  timestamptz
);
create index agent_devices_user_idx on public.agent_devices (user_id);

create table public.sync_events (
  event_id      uuid primary key,
  device_id     uuid not null references public.agent_devices (device_id),
  agent_user_id uuid not null references public.profiles (user_id),
  org_id        uuid not null references public.organisations (id),
  seq           bigint not null check (seq > 0),
  type          text not null,
  client_ts     timestamptz,
  lat           double precision,
  lng           double precision,
  accuracy_m    double precision,
  payload       jsonb not null,
  status        text not null check (status in ('accepted', 'rejected')),
  reason        text,
  result        jsonb,
  recorded_at   timestamptz not null default now(),
  unique (device_id, seq)
);
create index sync_events_agent_idx on public.sync_events (agent_user_id, recorded_at desc);

create table public.agent_visits (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null unique references public.sync_events (event_id) deferrable initially deferred,
  agent_user_id uuid not null references public.profiles (user_id),
  org_id        uuid not null references public.organisations (id),
  retailer_org_id uuid not null references public.organisations (id),
  geofence_ok   boolean not null,
  geofence_reason text not null,
  distance_m    integer,
  visited_at    timestamptz not null,
  recorded_at   timestamptz not null default now()
);
create index agent_visits_agent_idx on public.agent_visits (agent_user_id, visited_at desc);

create table public.review_items (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null unique references public.sync_events (event_id),
  org_id        uuid not null references public.organisations (id),
  agent_user_id uuid not null references public.profiles (user_id),
  reason        text not null,
  status        text not null default 'open' check (status in ('open', 'accepted', 'accepted_into_variance', 'dismissed')),
  decided_by    uuid references public.profiles (user_id),
  decision_note text,
  decided_at    timestamptz,
  created_at    timestamptz not null default now()
);
create index review_items_org_status_idx on public.review_items (org_id, status);

-- Variance kinds: 'shortfall' (carrier holds stock that isn't accounted for) and 'unrecorded_stock'
-- (a real sale exceeded the ledger's carried stock and was accepted into variance).
alter table public.variance_cases
  add column kind text not null default 'shortfall' check (kind in ('shortfall', 'unrecorded_stock')),
  drop constraint variance_cases_status_check,
  add constraint variance_cases_status_check check (status in ('pending', 'written_off', 'charged_to_agent', 'linked_to_handover')),
  drop constraint variance_cases_shipment_id_sku_id_key,
  add constraint variance_cases_one_per_kind unique (shipment_id, sku_id, kind);

-- Push sale core gains a manager override for the geofence (used only by accept-into-variance).
create or replace function app.apply_push_sale(
  p_shipment_id uuid, p_agent_user_id uuid, p_retailer_org_id uuid, p_lines jsonb,
  p_lat double precision, p_lng double precision, p_accuracy_m double precision, p_idempotency_key text,
  p_skip_geofence boolean default false
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
  if not found or v_s.kind <> 'push' or v_s.status not in ('open', 'returning', 'reconciling')
     or (v_s.status <> 'open' and not p_skip_geofence) then
    raise exception using errcode = 'SOL04', message = 'shipment_closed';
  end if;
  if (select user_id from public.stock_locations where id = v_s.carrier_location_id) <> p_agent_user_id then
    raise exception using errcode = 'SOL03', message = 'not_owner';
  end if;
  if not exists (select 1 from public.customer_relationships
                 where distributor_org_id = v_s.org_id and retailer_org_id = p_retailer_org_id and status = 'active') then
    raise exception using errcode = 'SOL05', message = 'unknown_retailer';
  end if;
  select * into v_geo from app.evaluate_geofence(v_s.org_id, p_retailer_org_id, p_lat, p_lng, p_accuracy_m);
  if not v_geo.ok and not p_skip_geofence then
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
drop function app.apply_push_sale(uuid, uuid, uuid, jsonb, double precision, double precision, double precision, text);

-- Register (or re-confirm) this device for the signed-in agent.
create function app.register_device(p_device_id uuid, p_org_id uuid)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_role(p_org_id, array['agent', 'driver']::public.member_role[]);
  v_dev public.agent_devices;
begin
  insert into public.agent_devices (device_id, user_id, org_id) values (p_device_id, v_uid, p_org_id)
  on conflict (device_id) do nothing;
  select * into strict v_dev from public.agent_devices where device_id = p_device_id;
  if v_dev.user_id <> v_uid then
    raise exception using errcode = 'SOL03', message = 'this device is registered to someone else';
  end if;
  return v_dev.last_seq;
end;
$$;

-- Applies one event (inside the caller's subtransaction). Raises on rejection; returns the result.
create function app.apply_sync_event(p_dev public.agent_devices, p_event jsonb)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_type text := p_event->>'type';
  v_payload jsonb := p_event->'payload';
  v_geo record;
  v_dist uuid;
begin
  if v_type = 'sale.recorded' then
    return app.apply_push_sale((v_payload->>'shipment_id')::uuid, p_dev.user_id, (v_payload->>'retailer_id')::uuid,
                               v_payload->'lines', (p_event->>'lat')::double precision, (p_event->>'lng')::double precision,
                               (p_event->>'accuracy_m')::double precision, 'sync:' || (p_event->>'event_id'));
  elsif v_type = 'visit.checked_in' then
    if not exists (select 1 from public.customer_relationships where distributor_org_id = p_dev.org_id
                   and retailer_org_id = (v_payload->>'retailer_id')::uuid and status = 'active') then
      raise exception using errcode = 'SOL05', message = 'unknown_retailer';
    end if;
    select * into v_geo from app.evaluate_geofence(p_dev.org_id, (v_payload->>'retailer_id')::uuid,
      (p_event->>'lat')::double precision, (p_event->>'lng')::double precision, (p_event->>'accuracy_m')::double precision);
    insert into public.agent_visits (event_id, agent_user_id, org_id, retailer_org_id, geofence_ok, geofence_reason, distance_m, visited_at)
    values ((p_event->>'event_id')::uuid, p_dev.user_id, p_dev.org_id, (v_payload->>'retailer_id')::uuid,
            v_geo.ok, v_geo.reason, v_geo.distance_m, coalesce((p_event->>'client_ts')::timestamptz, now()));
    return jsonb_build_object('geofence_ok', v_geo.ok, 'reason', v_geo.reason, 'distance_m', v_geo.distance_m);
  else
    raise exception using errcode = 'SOL05', message = 'invalid_payload', detail = format('unknown event type %s', v_type);
  end if;
end;
$$;

-- The sync endpoint. Returns one result per event: accepted | duplicate | rejected (reason) | deferred.
create function app.sync_agent_events(p_device_id uuid, p_events jsonb)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid     uuid := app.require_user();
  v_dev     public.agent_devices;
  v_ev      jsonb;
  v_existing public.sync_events;
  v_results jsonb := '[]'::jsonb;
  v_result  jsonb;
  v_reason  text;
  v_gap     boolean := false;
begin
  select * into v_dev from public.agent_devices where device_id = p_device_id for update;
  if not found or v_dev.user_id <> v_uid then
    raise exception using errcode = 'SOL03', message = 'unknown device; register it first';
  end if;
  if not app.has_role(v_dev.org_id, array['agent', 'driver']::public.member_role[]) then
    raise exception using errcode = 'SOL03', message = 'not an active field member of this distributor';
  end if;

  for v_ev in select e from jsonb_array_elements(p_events) e order by (e->>'seq')::bigint loop
    select * into v_existing from public.sync_events where event_id = (v_ev->>'event_id')::uuid;
    if found then
      if v_existing.device_id <> p_device_id then
        v_results := v_results || jsonb_build_object('event_id', v_ev->>'event_id', 'status', 'rejected', 'reason', 'not_owner');
      else
        v_results := v_results || jsonb_build_object('event_id', v_ev->>'event_id', 'status', 'duplicate',
                                                     'original_status', v_existing.status, 'reason', v_existing.reason, 'result', v_existing.result);
      end if;
      continue;
    end if;
    if v_gap or (v_ev->>'seq')::bigint <> v_dev.last_seq + 1 then
      v_gap := true;   -- an earlier event is missing: never validate later events against stale stock
      v_results := v_results || jsonb_build_object('event_id', v_ev->>'event_id', 'status', 'deferred', 'reason', 'seq_gap',
                                                   'expected_seq', v_dev.last_seq + 1);
      continue;
    end if;

    begin
      v_result := app.apply_sync_event(v_dev, v_ev);
      insert into public.sync_events (event_id, device_id, agent_user_id, org_id, seq, type, client_ts, lat, lng, accuracy_m, payload, status, result)
      values ((v_ev->>'event_id')::uuid, p_device_id, v_uid, v_dev.org_id, (v_ev->>'seq')::bigint, v_ev->>'type',
              (v_ev->>'client_ts')::timestamptz, (v_ev->>'lat')::double precision, (v_ev->>'lng')::double precision,
              (v_ev->>'accuracy_m')::double precision, coalesce(v_ev->'payload', '{}'::jsonb), 'accepted', v_result);
      v_results := v_results || jsonb_build_object('event_id', v_ev->>'event_id', 'status', 'accepted', 'result', v_result);
    exception when sqlstate 'SOL01' or sqlstate 'SOL03' or sqlstate 'SOL04' or sqlstate 'SOL05'
                   or sqlstate '22P02' or sqlstate '23514' then
      get stacked diagnostics v_reason = message_text;
      if v_reason not in ('insufficient_carried_stock', 'outside_geofence', 'shipment_closed', 'unknown_retailer',
                          'price_mismatch', 'not_owner', 'invalid_payload') then
        v_reason := 'invalid_payload';
      end if;
      insert into public.sync_events (event_id, device_id, agent_user_id, org_id, seq, type, client_ts, lat, lng, accuracy_m, payload, status, reason)
      values ((v_ev->>'event_id')::uuid, p_device_id, v_uid, v_dev.org_id, (v_ev->>'seq')::bigint, coalesce(v_ev->>'type', 'unknown'),
              (v_ev->>'client_ts')::timestamptz, (v_ev->>'lat')::double precision, (v_ev->>'lng')::double precision,
              (v_ev->>'accuracy_m')::double precision, coalesce(v_ev->'payload', '{}'::jsonb), 'rejected', v_reason);
      insert into public.review_items (event_id, org_id, agent_user_id, reason)
      values ((v_ev->>'event_id')::uuid, v_dev.org_id, v_uid, v_reason);
      v_results := v_results || jsonb_build_object('event_id', v_ev->>'event_id', 'status', 'rejected', 'reason', v_reason);
    end;
    v_dev.last_seq := (v_ev->>'seq')::bigint;
  end loop;

  update public.agent_devices set last_seq = v_dev.last_seq, last_sync_at = now() where device_id = p_device_id;
  return v_results;
end;
$$;

-- Manager: the sale really happened. Missing carried stock is brought in as an 'unrecorded_stock'
-- adjustment (variance case, pending), then the sale is applied (geofence overridden by the manager).
create function app.review_accept_into_variance(p_item_id uuid, p_note text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := app.require_user();
  v_item  public.review_items;
  v_ev    public.sync_events;
  v_s     public.shipments;
  v_line  record;
  v_case  uuid;
  v_short integer;
  v_total integer := 0;
  v_sale  jsonb;
begin
  select * into v_item from public.review_items where id = p_item_id for update;
  if not found or v_item.status <> 'open' then
    raise exception using errcode = 'SOL04', message = 'review item is not open';
  end if;
  select * into strict v_ev from public.sync_events where event_id = v_item.event_id;
  if v_ev.type <> 'sale.recorded' or v_item.reason not in ('insufficient_carried_stock', 'outside_geofence') then
    raise exception using errcode = 'SOL04', message = 'only rejected sales (stock or geofence) can be accepted into variance';
  end if;
  select * into v_s from public.shipments where id = (v_ev.payload->>'shipment_id')::uuid for update;
  if not found or v_s.status not in ('open', 'returning', 'reconciling') then
    raise exception using errcode = 'SOL04', message = 'shipment_closed';
  end if;
  perform app.require_warehouse_operator(v_s.warehouse_id, array['branch_manager']::public.member_role[]);
  if v_uid = v_item.agent_user_id then
    raise exception using errcode = 'SOL03', message = 'you cannot review your own sale';
  end if;
  if nullif(btrim(p_note), '') is null then
    raise exception using errcode = 'SOL05', message = 'a note is required';
  end if;

  for v_line in
    select (x->>'sku_id')::uuid as sku_id, sum((x->>'qty_pieces')::integer)::integer as qty
    from jsonb_array_elements(v_ev.payload->'lines') x group by 1 order by 1
  loop
    select greatest(v_line.qty - coalesce((select on_hand from public.stock_balances
                                           where location_id = v_s.carrier_location_id and sku_id = v_line.sku_id), 0), 0)
      into v_short;
    if v_short > 0 then
      insert into public.variance_cases (shipment_id, org_id, carrier_user_id, sku_id, qty_pieces, value_kobo, kind)
      values (v_s.id, v_s.org_id, v_item.agent_user_id, v_line.sku_id, v_short, 0, 'unrecorded_stock')
      on conflict (shipment_id, sku_id, kind) do update set qty_pieces = public.variance_cases.qty_pieces + excluded.qty_pieces
      returning id into v_case;
      perform app.post_stock_movement(p_item_id, 'adjustment', v_s.carrier_location_id, v_line.sku_id, v_short, 1,
                                      'variance_case', v_case, 'unrecorded_stock: ' || p_note, null);
      v_total := v_total + v_short;
    end if;
  end loop;

  v_sale := app.apply_push_sale(v_s.id, v_item.agent_user_id, (v_ev.payload->>'retailer_id')::uuid, v_ev.payload->'lines',
                                v_ev.lat, v_ev.lng, v_ev.accuracy_m, 'sync:' || v_ev.event_id, true);
  update public.review_items
     set status = case when v_total > 0 then 'accepted_into_variance' else 'accepted' end,
         decided_by = v_uid, decision_note = p_note, decided_at = now()
   where id = p_item_id;
  if v_total > 0 and v_s.status <> 'reconciling' then
    update public.shipments set status_note = format('%s pieces sold beyond recorded stock: variance pending', v_total) where id = v_s.id;
  end if;
  return jsonb_build_object('sale', v_sale, 'unrecorded_pieces', v_total);
end;
$$;

create function app.review_dismiss(p_item_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid  uuid := app.require_user();
  v_item public.review_items;
begin
  select * into v_item from public.review_items where id = p_item_id for update;
  if not found or v_item.status <> 'open' then
    raise exception using errcode = 'SOL04', message = 'review item is not open';
  end if;
  perform app.require_role(v_item.org_id, array['distributor_admin', 'branch_manager']::public.member_role[]);
  if v_uid = v_item.agent_user_id then
    raise exception using errcode = 'SOL03', message = 'you cannot review your own event';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception using errcode = 'SOL05', message = 'a reason is required';
  end if;
  update public.review_items set status = 'dismissed', decided_by = v_uid, decision_note = p_reason, decided_at = now()
   where id = p_item_id;
end;
$$;

-- Shipments never close while ANY variance case is pending (both kinds).
create or replace function app.settle_carrier(p_shipment_id uuid)
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
    v_case := null;
    insert into public.variance_cases (shipment_id, org_id, carrier_user_id, sku_id, qty_pieces, value_kobo, kind)
    values (p_shipment_id, v_s.org_id, v_agent, v_rem.sku_id, v_rem.on_hand, v_value, 'shortfall')
    on conflict (shipment_id, sku_id, kind) do nothing
    returning id into v_case;
    if v_case is not null and v_value > 0 then
      v_jid := app.post_journal('variance_raised', 'variance_raised:' || v_case, jsonb_build_array(
        jsonb_build_object('account_id', app.ensure_account(v_s.org_id, 'variance', p_counterparty_user_id => v_agent), 'amount_kobo', v_value::text),
        jsonb_build_object('account_id', app.ensure_account(v_s.org_id, 'variance_offset'), 'amount_kobo', (-v_value)::text)),
        'variance_case', v_case, 'unreconciled stock after return');
      update public.variance_cases set raised_journal_id = v_jid where id = v_case;
    end if;
  end loop;

  if v_total = 0 and not exists (select 1 from public.variance_cases where shipment_id = p_shipment_id and status = 'pending') then
    update public.shipments set status = 'closed', closed_at = now(), status_note = null where id = p_shipment_id;
    return 'closed';
  end if;
  update public.shipments
     set status = 'reconciling',
         status_note = case when v_total > 0 then format('%s pieces unaccounted for: variance pending approval', v_total)
                            else 'variance pending approval' end
   where id = p_shipment_id;
  return 'reconciling';
end;
$$;

-- Resolution now covers both kinds:
--   shortfall:        write_off | charge_agent (as before)
--   unrecorded_stock: link_handover (the stock really came from the warehouse: post the missing handover and
--                     reverse the placeholder) | write_off (accept the explained adjustment as is)
create or replace function app.resolve_variance(p_case_id uuid, p_decision text, p_note text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
  v_c   public.variance_cases;
  v_s   public.shipments;
  v_entries jsonb;
  v_jid uuid;
  v_wh  uuid;
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
  if nullif(btrim(p_note), '') is null then
    raise exception using errcode = 'SOL05', message = 'a note is required';
  end if;

  if v_c.kind = 'shortfall' then
    if p_decision not in ('write_off', 'charge_agent') then
      raise exception using errcode = 'SOL05', message = 'decision must be write_off or charge_agent';
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
  else
    if p_decision not in ('link_handover', 'write_off') then
      raise exception using errcode = 'SOL05', message = 'decision must be link_handover or write_off for unrecorded stock';
    end if;
    if p_decision = 'link_handover' then
      v_wh := app.warehouse_location(v_s.warehouse_id);
      perform app.post_stock_movement(p_case_id, 'handover', v_wh, v_c.sku_id, v_c.qty_pieces, -1, 'variance_case', p_case_id, 'missed handover: ' || p_note, null);
      perform app.post_stock_movement(p_case_id, 'handover', v_s.carrier_location_id, v_c.sku_id, v_c.qty_pieces, 1, 'variance_case', p_case_id, 'missed handover: ' || p_note, null);
      perform app.post_stock_movement(p_case_id, 'adjustment', v_s.carrier_location_id, v_c.sku_id, v_c.qty_pieces, -1, 'variance_case', p_case_id, 'reverse unrecorded_stock placeholder', null);
    end if;
  end if;

  update public.variance_cases
     set status = case p_decision when 'write_off' then 'written_off' when 'charge_agent' then 'charged_to_agent' else 'linked_to_handover' end,
         resolved_journal_id = v_jid, resolved_by = v_uid, resolution_note = p_note, resolved_at = now()
   where id = p_case_id;

  if v_s.status = 'reconciling'
     and not exists (select 1 from public.variance_cases where shipment_id = v_s.id and status = 'pending')
     and not exists (select 1 from public.stock_balances where location_id = v_s.carrier_location_id and on_hand <> 0) then
    update public.shipments set status = 'closed', closed_at = now(), status_note = null where id = v_s.id;
    return 'closed';
  end if;
  if not exists (select 1 from public.variance_cases where shipment_id = v_s.id and status = 'pending') and v_s.status <> 'reconciling' then
    update public.shipments set status_note = null where id = v_s.id;
  end if;
  return 'pending';
end;
$$;

-- RLS, audit, grants
alter table public.agent_devices enable row level security;
alter table public.sync_events enable row level security;
alter table public.agent_visits enable row level security;
alter table public.review_items enable row level security;

create policy agent_devices_select on public.agent_devices for select to authenticated using (
  (select app.is_platform_admin()) or user_id = (select app.current_user_id())
  or org_id = any((select app.my_org_ids_with_role(array['distributor_admin', 'branch_manager']::public.member_role[]))::uuid[]));
create policy sync_events_select on public.sync_events for select to authenticated using (
  (select app.is_platform_admin()) or agent_user_id = (select app.current_user_id())
  or org_id = any((select app.my_org_ids_with_role(array['distributor_admin', 'branch_manager']::public.member_role[]))::uuid[]));
create policy agent_visits_select on public.agent_visits for select to authenticated using (
  (select app.is_platform_admin()) or agent_user_id = (select app.current_user_id())
  or org_id = any((select app.my_org_ids_with_role(array['distributor_admin', 'branch_manager']::public.member_role[]))::uuid[]));
create policy review_items_select on public.review_items for select to authenticated using (
  (select app.is_platform_admin()) or agent_user_id = (select app.current_user_id())
  or org_id = any((select app.my_org_ids_with_role(array['distributor_admin', 'branch_manager']::public.member_role[]))::uuid[]));

select audit.attach(t::regclass) from unnest(array['public.agent_devices', 'public.sync_events', 'public.agent_visits', 'public.review_items']) t;

revoke all on public.agent_devices, public.sync_events, public.agent_visits, public.review_items from anon, authenticated;
grant select on public.agent_devices, public.sync_events, public.agent_visits, public.review_items to authenticated;

revoke all on function
  app.apply_push_sale(uuid, uuid, uuid, jsonb, double precision, double precision, double precision, text, boolean),
  app.register_device(uuid, uuid), app.apply_sync_event(public.agent_devices, jsonb), app.sync_agent_events(uuid, jsonb),
  app.review_accept_into_variance(uuid, text), app.review_dismiss(uuid, text), app.settle_carrier(uuid), app.resolve_variance(uuid, text, text)
from public, anon, authenticated;
grant execute on function
  app.register_device(uuid, uuid), app.sync_agent_events(uuid, jsonb),
  app.review_accept_into_variance(uuid, text), app.review_dismiss(uuid, text), app.resolve_variance(uuid, text, text)
to authenticated;
