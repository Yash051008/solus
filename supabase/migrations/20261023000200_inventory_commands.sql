-- Receipts and approved adjustments (Phase 4). Every quantity change is a ledger movement.

-- distributor_admin of the warehouse's org, or a member with one of p_roles in the warehouse's branch.
create function app.can_operate_warehouse(p_warehouse_id uuid, p_roles public.member_role[])
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.warehouses w
    join public.memberships m on m.org_id = w.org_id
    where w.id = p_warehouse_id and m.user_id = app.current_user_id() and m.status = 'active'
      and (m.role = 'distributor_admin' or (m.role = any(p_roles) and m.branch_id = w.branch_id))
  )
$$;

create function app.require_warehouse_operator(p_warehouse_id uuid, p_roles public.member_role[])
returns uuid
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
begin
  if not app.can_operate_warehouse(p_warehouse_id, p_roles) then
    raise exception using errcode = 'SOL03',
      message = format('requires distributor_admin or %s of this warehouse''s branch', array_to_string(p_roles, '/'));
  end if;
  return v_uid;
end;
$$;

create function app.warehouse_location(p_warehouse_id uuid)
returns uuid
language sql stable security definer set search_path = ''
as $$
  select id from public.stock_locations where warehouse_id = p_warehouse_id and kind = 'warehouse'
$$;

-- Lines: [{"sku_id", "uom_code", "uom_qty"}] -> pieces via sku_uom. Shared by receipts, transfers, orders.
create function app.lines_to_pieces(p_lines jsonb)
returns table (line_no integer, sku_id uuid, uom_code text, uom_qty integer, qty_pieces integer)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception using errcode = 'SOL05', message = 'at least one line is required';
  end if;
  return query
  select l.ord::integer, (l.v->>'sku_id')::uuid, l.v->>'uom_code', (l.v->>'uom_qty')::integer,
         ((l.v->>'uom_qty')::integer * u.pieces_per_uom)::integer
  from jsonb_array_elements(p_lines) with ordinality as l(v, ord)
  left join public.sku_uom u on u.sku_id = (l.v->>'sku_id')::uuid and u.uom_code = l.v->>'uom_code';

  if exists (
    select 1 from jsonb_array_elements(p_lines) l
    left join public.sku_uom u on u.sku_id = (l->>'sku_id')::uuid and u.uom_code = l->>'uom_code'
    where u.sku_id is null or (l->>'uom_qty')::integer <= 0
  ) then
    raise exception using errcode = 'SOL05', message = 'every line needs a known sku/uom and a positive whole quantity';
  end if;
end;
$$;

create table public.receipts (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references public.organisations (id),
  warehouse_id    uuid not null references public.warehouses (id),
  reference       text not null check (length(btrim(reference)) between 1 and 120),
  idempotency_key text not null unique check (length(idempotency_key) between 8 and 200),
  received_by     uuid not null references public.profiles (user_id),
  created_at      timestamptz not null default now()
);
create index receipts_warehouse_idx on public.receipts (warehouse_id, created_at desc);

-- Inbound stock (until primary orders exist, this is how stock enters a distributor). Idempotent.
create function app.record_receipt(p_warehouse_id uuid, p_reference text, p_lines jsonb, p_idempotency_key text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := app.require_warehouse_operator(p_warehouse_id, array['branch_manager', 'warehouse_staff']::public.member_role[]);
  v_id    uuid;
  v_org   uuid;
  v_loc   uuid := app.warehouse_location(p_warehouse_id);
  v_line  record;
begin
  select org_id into strict v_org from public.warehouses where id = p_warehouse_id;

  insert into public.receipts (org_id, warehouse_id, reference, idempotency_key, received_by)
  values (v_org, p_warehouse_id, p_reference, p_idempotency_key, v_uid)
  on conflict (idempotency_key) do nothing
  returning id into v_id;
  if v_id is null then   -- replay (also under concurrency: the loser waits, then lands here)
    select id into strict v_id from public.receipts where idempotency_key = p_idempotency_key;
    return v_id;
  end if;

  for v_line in select * from app.lines_to_pieces(p_lines) loop
    perform app.post_stock_movement(v_id, 'receipt', v_loc, v_line.sku_id, v_line.qty_pieces,
                                    null, 'receipt', v_id, p_reference, null);
  end loop;
  return v_id;
end;
$$;

create table public.adjustment_requests (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references public.organisations (id),
  location_id     uuid not null references public.stock_locations (id),
  sku_id          uuid not null references public.skus (id),
  qty_delta       integer not null check (qty_delta <> 0),
  reason          text not null check (length(btrim(reason)) between 3 and 500),
  status          public.record_status not null default 'pending' check (status in ('pending', 'active', 'rejected')),
  requested_by    uuid not null references public.profiles (user_id),
  decided_by      uuid references public.profiles (user_id),
  decided_at      timestamptz,
  decision_reason text,
  created_at      timestamptz not null default now()
);
create index adjustment_requests_org_status_idx on public.adjustment_requests (org_id, status);

create function app.request_adjustment(p_warehouse_id uuid, p_sku_id uuid, p_qty_delta integer, p_reason text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_warehouse_operator(p_warehouse_id, array['branch_manager', 'warehouse_staff']::public.member_role[]);
  v_id  uuid;
begin
  insert into public.adjustment_requests (org_id, location_id, sku_id, qty_delta, reason, requested_by)
  select w.org_id, app.warehouse_location(w.id), p_sku_id, p_qty_delta, p_reason, v_uid
  from public.warehouses w where w.id = p_warehouse_id
  returning id into v_id;
  return v_id;
end;
$$;

-- Approver must be BM of the branch or admin, and never the requester (separation of duties).
create function app.decide_adjustment(p_request_id uuid, p_approve boolean, p_reason text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
  v_req public.adjustment_requests;
  v_wh  uuid;
begin
  select * into v_req from public.adjustment_requests where id = p_request_id for update;
  if not found then
    raise exception using errcode = 'SOL05', message = 'adjustment request not found';
  end if;
  if v_req.status <> 'pending' then
    raise exception using errcode = 'SOL04', message = format('request is already %s', v_req.status);
  end if;
  select warehouse_id into v_wh from public.stock_locations where id = v_req.location_id;
  perform app.require_warehouse_operator(v_wh, array['branch_manager']::public.member_role[]);
  if v_req.requested_by = v_uid then
    raise exception using errcode = 'SOL03', message = 'you cannot approve your own adjustment';
  end if;
  if not p_approve and nullif(btrim(p_reason), '') is null then
    raise exception using errcode = 'SOL05', message = 'a reason is required to reject';
  end if;

  if p_approve then
    perform app.post_stock_movement(p_request_id, 'adjustment', v_req.location_id, v_req.sku_id,
                                    abs(v_req.qty_delta), sign(v_req.qty_delta)::integer,
                                    'adjustment_request', p_request_id, v_req.reason, null);
  end if;
  update public.adjustment_requests
     set status = case when p_approve then 'active' else 'rejected' end::public.record_status,
         decided_by = v_uid, decided_at = now(), decision_reason = p_reason
   where id = p_request_id;
end;
$$;
