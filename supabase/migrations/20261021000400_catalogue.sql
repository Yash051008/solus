-- Master catalogue (manufacturer-owned), units of measure, distributor price lists.
-- Stock is always pieces; sku_uom is applied only at input/display edges.

create table public.brands (
  id                  uuid primary key default gen_random_uuid(),
  manufacturer_org_id uuid not null,
  manufacturer_kind   public.org_kind not null default 'manufacturer' check (manufacturer_kind = 'manufacturer'),
  name                text not null check (length(btrim(name)) > 0),
  created_at          timestamptz not null default now(),
  foreign key (manufacturer_org_id, manufacturer_kind) references public.organisations (id, kind),
  unique (id, manufacturer_org_id),
  unique (manufacturer_org_id, name)
);

create table public.skus (
  id                  uuid primary key default gen_random_uuid(),
  manufacturer_org_id uuid not null,
  brand_id            uuid not null,
  code                text not null check (code ~ '^[A-Z0-9][A-Z0-9-]{1,31}$'),
  name                text not null check (length(btrim(name)) > 0),
  -- 'returnable_container' reserved for empties tracking (deferred); same ledger, no migration needed.
  item_class          text not null default 'sellable' check (item_class in ('sellable', 'returnable_container')),
  active              boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  foreign key (brand_id, manufacturer_org_id) references public.brands (id, manufacturer_org_id),
  unique (manufacturer_org_id, code)
);
create index skus_brand_idx on public.skus (brand_id);

create table public.sku_uom (
  sku_id         uuid not null references public.skus (id),
  uom_code       text not null check (uom_code ~ '^[a-z][a-z_]{1,15}$'),
  pieces_per_uom integer not null check (pieces_per_uom > 0),
  primary key (sku_id, uom_code),
  constraint sku_uom_piece_is_one check (uom_code <> 'piece' or pieces_per_uom = 1)
);

-- Every SKU always has the base unit.
create function app.tg_sku_add_piece_uom()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.sku_uom (sku_id, uom_code, pieces_per_uom) values (new.id, 'piece', 1);
  return null;
end;
$$;
create trigger skus_add_piece_uom after insert on public.skus
  for each row execute function app.tg_sku_add_piece_uom();
create trigger skus_updated_at before update on public.skus
  for each row execute function app.tg_set_updated_at();

-- Conversion factors are history: changing one would silently re-interpret past orders.
create function app.tg_sku_uom_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = 'SOL04',
    message = 'sku_uom rows are immutable; add a new uom_code instead of changing a conversion factor';
end;
$$;
create trigger sku_uom_immutable before update or delete on public.sku_uom
  for each row execute function app.tg_sku_uom_immutable();

create table public.price_lists (
  id                 uuid primary key default gen_random_uuid(),
  distributor_org_id uuid not null,
  distributor_kind   public.org_kind not null default 'distributor' check (distributor_kind = 'distributor'),
  name               text not null check (length(btrim(name)) > 0),
  effective_from     timestamptz not null,
  created_at         timestamptz not null default now(),
  foreign key (distributor_org_id, distributor_kind) references public.organisations (id, kind),
  unique (distributor_org_id, name, effective_from)
);
create index price_lists_distributor_idx on public.price_lists (distributor_org_id, effective_from desc);

-- Price per (sku, uom) so a carton can be priced exactly (no fractional per-piece kobo).
create table public.price_list_items (
  price_list_id uuid not null references public.price_lists (id),
  sku_id        uuid not null,
  uom_code      text not null,
  price_kobo    bigint not null check (price_kobo > 0),
  primary key (price_list_id, sku_id, uom_code),
  foreign key (sku_id, uom_code) references public.sku_uom (sku_id, uom_code)
);

-- Prices that are already in effect are history: publish a new price list instead.
create function app.tg_price_list_items_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_effective timestamptz;
begin
  select effective_from into v_effective
  from public.price_lists
  where id = coalesce(old.price_list_id, new.price_list_id);
  if v_effective <= now() then
    raise exception using errcode = 'SOL04',
      message = 'price list is already in effect; publish a new price list instead of editing it';
  end if;
  return coalesce(new, old);
end;
$$;
create trigger price_list_items_guard before update or delete on public.price_list_items
  for each row execute function app.tg_price_list_items_guard();
