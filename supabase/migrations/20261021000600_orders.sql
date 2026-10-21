-- Pull orders (primary orders are a deferred order_kind). Lines carry both the authoritative
-- piece quantity and the pricing UoM, so carton prices stay exact (ADR-0003 D10).

create table public.orders (
  id                 uuid primary key default gen_random_uuid(),
  order_kind         public.order_kind not null default 'pull',
  distributor_org_id uuid not null,
  retailer_org_id    uuid not null,
  placed_by_user_id  uuid references public.profiles (user_id),
  status             public.order_status not null default 'placed',
  routing_decision   jsonb,
  routing_reason     text,
  idempotency_key    text unique,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  foreign key (distributor_org_id, retailer_org_id)
    references public.customer_relationships (distributor_org_id, retailer_org_id),
  unique (id, distributor_org_id),
  constraint orders_pull_only_in_mvp check (order_kind = 'pull')
);
create index orders_distributor_status_idx on public.orders (distributor_org_id, status);
create index orders_retailer_idx on public.orders (retailer_org_id);

create table public.order_lines (
  id               uuid primary key default gen_random_uuid(),
  order_id         uuid not null references public.orders (id),
  sku_id           uuid not null,
  uom_code         text not null,
  uom_qty          integer not null check (uom_qty > 0),
  qty_pieces       integer not null check (qty_pieces > 0),
  uom_price_kobo   bigint not null check (uom_price_kobo > 0),
  line_amount_kobo bigint generated always as (uom_qty::bigint * uom_price_kobo) stored,
  warehouse_id     uuid references public.warehouses (id),
  created_at       timestamptz not null default now(),
  foreign key (sku_id, uom_code) references public.sku_uom (sku_id, uom_code)
);
create index order_lines_order_idx on public.order_lines (order_id);
create index order_lines_sku_idx on public.order_lines (sku_id);

-- The database performs the carton -> piece conversion; a caller-supplied qty_pieces must agree.
create function app.tg_order_line_pieces()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_factor integer;
  v_pieces integer;
begin
  select pieces_per_uom into strict v_factor
  from public.sku_uom where sku_id = new.sku_id and uom_code = new.uom_code;
  v_pieces := new.uom_qty * v_factor;   -- integer overflow raises
  if new.qty_pieces is not null and new.qty_pieces <> v_pieces then
    raise exception using errcode = 'SOL05',
      message = format('qty_pieces %s does not match %s x %s (%s pieces)',
                       new.qty_pieces, new.uom_qty, new.uom_code, v_pieces);
  end if;
  new.qty_pieces := v_pieces;
  return new;
end;
$$;
create trigger order_lines_pieces before insert on public.order_lines
  for each row execute function app.tg_order_line_pieces();

-- Only the fulfilment warehouse may change after insert; quantities and prices are history.
create function app.tg_order_line_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE'
     or (new.order_id, new.sku_id, new.uom_code, new.uom_qty, new.qty_pieces, new.uom_price_kobo)
        is distinct from
        (old.order_id, old.sku_id, old.uom_code, old.uom_qty, old.qty_pieces, old.uom_price_kobo) then
    raise exception using errcode = 'SOL04',
      message = 'order line quantities and prices are immutable';
  end if;
  return new;
end;
$$;
create trigger order_lines_immutable before update or delete on public.order_lines
  for each row execute function app.tg_order_line_immutable();

create trigger orders_updated_at before update on public.orders
  for each row execute function app.tg_set_updated_at();
