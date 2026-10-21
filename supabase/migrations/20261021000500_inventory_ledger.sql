-- Inventory: polymorphic stock locations, the append-only stock_movements ledger and the
-- stock_balances projection (hard rule 1, ADR-0003, docs/architecture/domain-model.md).

create table public.stock_locations (
  id           uuid primary key default gen_random_uuid(),
  kind         public.location_kind not null,
  org_id       uuid not null,
  org_kind     public.org_kind not null default 'distributor' check (org_kind = 'distributor'),
  warehouse_id uuid unique,
  user_id      uuid references public.profiles (user_id),
  created_at   timestamptz not null default now(),
  foreign key (org_id, org_kind) references public.organisations (id, kind),
  foreign key (warehouse_id, org_id) references public.warehouses (id, org_id),
  unique (id, org_id),
  unique (org_id, kind, user_id),
  constraint stock_locations_shape check (
       (kind = 'warehouse' and warehouse_id is not null and user_id is null)
    or (kind in ('agent', 'driver') and user_id is not null and warehouse_id is null)
  )
);
create index stock_locations_user_idx on public.stock_locations (user_id);

-- A carrier location must belong to a person holding the matching role in the same distributor.
create function app.tg_stock_location_carrier_check()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.kind in ('agent', 'driver') and not exists (
    select 1 from public.memberships m
    where m.user_id = new.user_id
      and m.org_id = new.org_id
      and m.role::text = new.kind::text
      and m.status <> 'suspended'
  ) then
    raise exception using errcode = 'SOL05',
      message = format('user %s holds no %s membership in organisation %s', new.user_id, new.kind, new.org_id);
  end if;
  return new;
end;
$$;
create trigger stock_locations_carrier_check before insert or update on public.stock_locations
  for each row execute function app.tg_stock_location_carrier_check();

create table public.stock_movements (
  id                uuid primary key default gen_random_uuid(),
  movement_group_id uuid not null,
  movement_type     public.movement_type not null,
  location_id       uuid not null,
  org_id            uuid not null,
  sku_id            uuid not null references public.skus (id),
  qty               integer not null check (qty > 0),
  on_hand_delta     integer not null,
  reserved_delta    integer not null,
  ref_kind          text check (ref_kind ~ '^[a-z][a-z_]{1,40}$'),
  ref_id            uuid,
  reason            text,
  batch_id          uuid,            -- FEFO/lot tracking extension point (unused in MVP)
  expiry_date       date,            -- FEFO/lot tracking extension point (unused in MVP)
  actor_user_id     uuid,
  occurred_at       timestamptz not null default now(),
  recorded_at       timestamptz not null default now(),
  idempotency_key   text unique,
  foreign key (location_id, org_id) references public.stock_locations (id, org_id),
  constraint stock_movements_ref_pair check ((ref_kind is null) = (ref_id is null)),
  -- Deltas are fully determined by type (and sign, for two-legged / adjustment rows).
  constraint stock_movements_delta_matches_type check (
       (movement_type = 'receipt'      and on_hand_delta =  qty and reserved_delta = 0)
    or (movement_type = 'reserve'      and on_hand_delta =  0   and reserved_delta = qty)
    or (movement_type = 'release'      and on_hand_delta =  0   and reserved_delta = -qty)
    or (movement_type = 'transfer_out' and on_hand_delta = -qty and reserved_delta = 0)
    or (movement_type = 'transfer_in'  and on_hand_delta =  qty and reserved_delta = 0)
    or (movement_type in ('sale', 'damage') and on_hand_delta = -qty and reserved_delta = 0)
    or (movement_type in ('handover', 'return', 'adjustment')
        and on_hand_delta in (qty, -qty) and reserved_delta = 0)
  )
);
create index stock_movements_location_sku_idx on public.stock_movements (location_id, sku_id);
create index stock_movements_group_idx on public.stock_movements (movement_group_id);
create index stock_movements_ref_idx on public.stock_movements (ref_kind, ref_id);
create index stock_movements_org_idx on public.stock_movements (org_id);

create table public.stock_balances (
  location_id   uuid not null,
  sku_id        uuid not null references public.skus (id),
  org_id        uuid not null,
  location_kind public.location_kind not null,
  on_hand       integer not null default 0,
  reserved      integer not null default 0,
  available     integer generated always as (on_hand - reserved) stored,
  updated_at    timestamptz not null default now(),
  primary key (location_id, sku_id),
  foreign key (location_id, org_id) references public.stock_locations (id, org_id),
  constraint stock_balances_on_hand_nonnegative check (on_hand >= 0),
  constraint stock_balances_reserved_nonnegative check (reserved >= 0),
  constraint stock_balances_reserved_within_on_hand check (reserved <= on_hand),
  constraint stock_balances_carriers_never_reserve check (location_kind = 'warehouse' or reserved = 0)
);
create index stock_balances_org_idx on public.stock_balances (org_id);
create index stock_balances_sku_idx on public.stock_balances (sku_id);

-- Validates a movement against its location kind and applies it to the projection,
-- in the same transaction. CHECKs on stock_balances make negative stock / oversell impossible.
create function app.tg_stock_movement_apply()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind public.location_kind;
begin
  select kind into strict v_kind from public.stock_locations where id = new.location_id;

  if new.movement_type in ('receipt', 'reserve', 'release', 'transfer_out', 'transfer_in')
     and v_kind <> 'warehouse' then
    raise exception using errcode = 'SOL05',
      message = format('%s is only valid at a warehouse location (got %s)', new.movement_type, v_kind);
  end if;

  if new.movement_type = 'sale' and v_kind = 'warehouse' then
    raise exception using errcode = 'SOL05',
      message = 'sale is only valid at an agent or driver location';
  end if;

  -- handover: warehouse gives (-), carrier receives (+). return: carrier gives (-), warehouse receives (+).
  if new.movement_type = 'handover'
     and not ((v_kind = 'warehouse' and new.on_hand_delta < 0) or (v_kind <> 'warehouse' and new.on_hand_delta > 0)) then
    raise exception using errcode = 'SOL05',
      message = 'handover legs must be warehouse (-) and carrier (+)';
  end if;
  if new.movement_type = 'return'
     and not ((v_kind <> 'warehouse' and new.on_hand_delta < 0) or (v_kind = 'warehouse' and new.on_hand_delta > 0)) then
    raise exception using errcode = 'SOL05',
      message = 'return legs must be carrier (-) and warehouse (+)';
  end if;

  -- Update first, insert only if the row does not exist yet. (INSERT ... ON CONFLICT would evaluate
  -- the CHECKs against the delta itself before resolving the conflict, rejecting valid decrements.)
  update public.stock_balances
     set on_hand = on_hand + new.on_hand_delta, reserved = reserved + new.reserved_delta, updated_at = now()
   where location_id = new.location_id and sku_id = new.sku_id;
  if not found then
    begin
      insert into public.stock_balances (location_id, sku_id, org_id, location_kind, on_hand, reserved)
      values (new.location_id, new.sku_id, new.org_id, v_kind, new.on_hand_delta, new.reserved_delta);
    exception when unique_violation then   -- a concurrent transaction created the row first
      update public.stock_balances
         set on_hand = on_hand + new.on_hand_delta, reserved = reserved + new.reserved_delta, updated_at = now()
       where location_id = new.location_id and sku_id = new.sku_id;
    end;
  end if;

  return null;
end;
$$;
create trigger stock_movements_apply after insert on public.stock_movements
  for each row execute function app.tg_stock_movement_apply();

-- Two-legged custody changes (handover, return) must net to zero per SKU within their group.
-- Deferred to commit so both legs can be inserted in either order.
create function app.tg_stock_group_balanced()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_net bigint;
begin
  select coalesce(sum(on_hand_delta), 0) into v_net
  from public.stock_movements
  where movement_group_id = new.movement_group_id
    and sku_id = new.sku_id
    and movement_type = new.movement_type;
  if v_net <> 0 then
    raise exception using errcode = 'SOL06',
      message = format('%s group %s is unbalanced for sku %s (net %s)',
                       new.movement_type, new.movement_group_id, new.sku_id, v_net);
  end if;
  return null;
end;
$$;
create constraint trigger stock_movements_group_balanced
  after insert on public.stock_movements
  deferrable initially deferred
  for each row
  when (new.movement_type in ('handover', 'return'))
  execute function app.tg_stock_group_balanced();

create trigger stock_movements_append_only before update or delete on public.stock_movements
  for each row execute function app.tg_append_only();
create trigger stock_movements_no_truncate before truncate on public.stock_movements
  for each statement execute function app.tg_append_only();

create trigger stock_balances_guard before insert or update or delete on public.stock_balances
  for each row execute function app.tg_projection_guard();
create trigger stock_balances_no_truncate before truncate on public.stock_balances
  for each statement execute function app.tg_projection_guard();
