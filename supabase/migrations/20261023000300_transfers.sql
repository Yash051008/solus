-- Warehouse-to-warehouse transfers (Phase 4). transfer_out at dispatch and transfer_in at receipt are
-- separate transactions linked by transfer_id. In transit = out - in. A transfer closes only at zero.

create table public.transfers (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid not null references public.organisations (id),
  from_warehouse_id uuid not null references public.warehouses (id),
  to_warehouse_id   uuid not null references public.warehouses (id),
  status            text not null default 'created'
                    check (status in ('created', 'dispatched', 'short', 'received', 'cancelled')),
  created_by        uuid not null references public.profiles (user_id),
  dispatched_by     uuid references public.profiles (user_id),
  received_by       uuid references public.profiles (user_id),
  resolved_by       uuid references public.profiles (user_id),
  shortage_reason   text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint transfers_distinct_warehouses check (from_warehouse_id <> to_warehouse_id)
);
create index transfers_org_status_idx on public.transfers (org_id, status);
create trigger transfers_updated_at before update on public.transfers
  for each row execute function app.tg_set_updated_at();

create table public.transfer_lines (
  id          uuid primary key default gen_random_uuid(),
  transfer_id uuid not null references public.transfers (id),
  sku_id      uuid not null references public.skus (id),
  qty_pieces  integer not null check (qty_pieces > 0),
  received    integer check (received >= 0),
  damaged     integer check (damaged >= 0),
  constraint transfer_lines_counts_within_qty check (coalesce(received, 0) + coalesce(damaged, 0) <= qty_pieces),
  unique (transfer_id, sku_id)
);

create function app.create_transfer(p_from_warehouse_id uuid, p_to_warehouse_id uuid, p_lines jsonb)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_warehouse_operator(p_from_warehouse_id, array['branch_manager']::public.member_role[]);
  v_id  uuid;
  v_org uuid;
begin
  select org_id into strict v_org from public.warehouses where id = p_from_warehouse_id;
  if not exists (select 1 from public.warehouses where id = p_to_warehouse_id and org_id = v_org and active) then
    raise exception using errcode = 'SOL05', message = 'destination must be an active warehouse of the same distributor';
  end if;
  insert into public.transfers (org_id, from_warehouse_id, to_warehouse_id, created_by)
  values (v_org, p_from_warehouse_id, p_to_warehouse_id, v_uid)
  returning id into v_id;
  insert into public.transfer_lines (transfer_id, sku_id, qty_pieces)
  select v_id, p.sku_id, sum(p.qty_pieces)::integer from app.lines_to_pieces(p_lines) p group by p.sku_id;
  return v_id;
end;
$$;

-- Source staff dispatch: transfer_out per line. Reserved stock can't leave (reserved <= on_hand CHECK).
create function app.dispatch_transfer(p_transfer_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid  uuid := app.require_user();
  v_t    public.transfers;
  v_line record;
begin
  select * into v_t from public.transfers where id = p_transfer_id for update;
  if not found or v_t.status <> 'created' then
    raise exception using errcode = 'SOL04', message = 'only a created transfer can be dispatched';
  end if;
  perform app.require_warehouse_operator(v_t.from_warehouse_id, array['branch_manager', 'warehouse_staff']::public.member_role[]);
  for v_line in select sku_id, qty_pieces from public.transfer_lines where transfer_id = p_transfer_id order by sku_id loop
    perform app.post_stock_movement(p_transfer_id, 'transfer_out', app.warehouse_location(v_t.from_warehouse_id),
                                    v_line.sku_id, v_line.qty_pieces, null, 'transfer', p_transfer_id, null, null);
  end loop;
  update public.transfers set status = 'dispatched', dispatched_by = v_uid where id = p_transfer_id;
end;
$$;

-- Destination staff count: lines [{"sku_id","received","damaged"}]. Received + damaged enter the
-- destination (transfer_in), damaged are then written off (damage). Any shortfall leaves the transfer
-- 'short' until a manager resolves it.
create function app.receive_transfer(p_transfer_id uuid, p_lines jsonb)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := app.require_user();
  v_t     public.transfers;
  v_line  record;
  v_dest  uuid;
  v_group uuid := gen_random_uuid();
  v_short integer;
begin
  select * into v_t from public.transfers where id = p_transfer_id for update;
  if not found or v_t.status <> 'dispatched' then
    raise exception using errcode = 'SOL04', message = 'only a dispatched transfer can be received';
  end if;
  perform app.require_warehouse_operator(v_t.to_warehouse_id, array['branch_manager', 'warehouse_staff']::public.member_role[]);
  if v_uid = v_t.dispatched_by then
    raise exception using errcode = 'SOL03', message = 'the dispatcher cannot also receive the transfer';
  end if;
  v_dest := app.warehouse_location(v_t.to_warehouse_id);

  update public.transfer_lines tl
     set received = coalesce((x->>'received')::integer, 0), damaged = coalesce((x->>'damaged')::integer, 0)
    from jsonb_array_elements(p_lines) x
   where tl.transfer_id = p_transfer_id and tl.sku_id = (x->>'sku_id')::uuid;
  if exists (select 1 from public.transfer_lines where transfer_id = p_transfer_id and received is null) then
    raise exception using errcode = 'SOL05', message = 'every transfer line must be counted';
  end if;

  for v_line in select * from public.transfer_lines where transfer_id = p_transfer_id order by sku_id loop
    if v_line.received + v_line.damaged > 0 then
      perform app.post_stock_movement(v_group, 'transfer_in', v_dest, v_line.sku_id, v_line.received + v_line.damaged,
                                      null, 'transfer', p_transfer_id, null, null);
    end if;
    if v_line.damaged > 0 then
      perform app.post_stock_movement(v_group, 'damage', v_dest, v_line.sku_id, v_line.damaged,
                                      null, 'transfer', p_transfer_id, 'damaged in transit', null);
    end if;
  end loop;

  select coalesce(sum(qty_pieces - received - damaged), 0) into v_short
  from public.transfer_lines where transfer_id = p_transfer_id;
  update public.transfers set status = case when v_short = 0 then 'received' else 'short' end, received_by = v_uid
   where id = p_transfer_id;
  return case when v_short = 0 then 'received' else 'short' end;
end;
$$;

-- Manager accepts a transit loss: the missing pieces are brought in and immediately adjusted out at the
-- destination with the reason, so in-transit returns to zero and the loss is explicit in the ledger.
create function app.resolve_transfer_shortage(p_transfer_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := app.require_user();
  v_t     public.transfers;
  v_line  record;
  v_dest  uuid;
  v_group uuid := gen_random_uuid();
begin
  select * into v_t from public.transfers where id = p_transfer_id for update;
  if not found or v_t.status <> 'short' then
    raise exception using errcode = 'SOL04', message = 'only a short transfer can be resolved';
  end if;
  perform app.require_warehouse_operator(v_t.to_warehouse_id, array['branch_manager']::public.member_role[]);
  if v_uid in (v_t.received_by, v_t.dispatched_by) then
    raise exception using errcode = 'SOL03', message = 'the dispatcher or receiver cannot approve the shortage';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception using errcode = 'SOL05', message = 'a reason is required';
  end if;
  v_dest := app.warehouse_location(v_t.to_warehouse_id);
  for v_line in
    select sku_id, qty_pieces - received - damaged as missing
    from public.transfer_lines where transfer_id = p_transfer_id and qty_pieces - received - damaged > 0
    order by sku_id
  loop
    perform app.post_stock_movement(v_group, 'transfer_in', v_dest, v_line.sku_id, v_line.missing,
                                    null, 'transfer', p_transfer_id, null, null);
    perform app.post_stock_movement(v_group, 'adjustment', v_dest, v_line.sku_id, v_line.missing, -1,
                                    'transfer', p_transfer_id, 'transit loss: ' || p_reason, null);
  end loop;
  update public.transfers set status = 'received', resolved_by = v_uid, shortage_reason = p_reason where id = p_transfer_id;
end;
$$;

create view public.v_transfer_in_transit with (security_invoker = true) as
select t.id as transfer_id, t.org_id, m.sku_id,
       sum(case when m.movement_type = 'transfer_out' then m.qty else 0 end)
     - sum(case when m.movement_type = 'transfer_in' then m.qty else 0 end) as in_transit
from public.transfers t
join public.stock_movements m on m.ref_kind = 'transfer' and m.ref_id = t.id
where m.movement_type in ('transfer_out', 'transfer_in')
group by t.id, t.org_id, m.sku_id;
