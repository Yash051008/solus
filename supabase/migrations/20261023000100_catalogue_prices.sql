-- Catalogue management (manufacturer) and price publication (distributor). Phase 4.

create function app.create_brand(p_manufacturer_id uuid, p_name text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform app.require_role(p_manufacturer_id, array['manufacturer_admin']::public.member_role[]);
  insert into public.brands (manufacturer_org_id, name) values (p_manufacturer_id, btrim(p_name)) returning id into v_id;
  return v_id;
end;
$$;

-- Creates a SKU (the 'piece' UoM is added automatically) and, optionally, its carton factor.
create function app.create_sku(
  p_manufacturer_id uuid, p_brand_id uuid, p_code text, p_name text, p_carton_pieces integer default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform app.require_role(p_manufacturer_id, array['manufacturer_admin']::public.member_role[]);
  insert into public.skus (manufacturer_org_id, brand_id, code, name)
  values (p_manufacturer_id, p_brand_id, upper(btrim(p_code)), btrim(p_name))
  returning id into v_id;
  if p_carton_pieces is not null then
    insert into public.sku_uom (sku_id, uom_code, pieces_per_uom) values (v_id, 'carton', p_carton_pieces);
  end if;
  return v_id;
end;
$$;

create function app.add_sku_uom(p_sku_id uuid, p_uom_code text, p_pieces_per_uom integer)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform app.require_role((select manufacturer_org_id from public.skus where id = p_sku_id),
                           array['manufacturer_admin']::public.member_role[]);
  insert into public.sku_uom (sku_id, uom_code, pieces_per_uom) values (p_sku_id, lower(btrim(p_uom_code)), p_pieces_per_uom);
end;
$$;

create function app.set_sku_active(p_sku_id uuid, p_active boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform app.require_role((select manufacturer_org_id from public.skus where id = p_sku_id),
                           array['manufacturer_admin']::public.member_role[]);
  update public.skus set active = p_active where id = p_sku_id;
end;
$$;

-- Publishes a whole price list atomically. Items: [{"sku_id","uom_code","price_kobo":"<integer>"}].
-- effective_from may not be in the past (history is immutable; see price_list_items guard).
create function app.publish_price_list(p_distributor_id uuid, p_name text, p_effective_from timestamptz, p_items jsonb)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform app.require_role(p_distributor_id, array['distributor_admin']::public.member_role[]);
  if p_effective_from < now() - interval '1 minute' then
    raise exception using errcode = 'SOL05', message = 'a price list cannot take effect in the past';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception using errcode = 'SOL05', message = 'a price list needs at least one item';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) i
    join public.skus s on s.id = (i->>'sku_id')::uuid
    where s.manufacturer_org_id not in (
      select manufacturer_org_id from public.supply_relationships where distributor_org_id = p_distributor_id)
  ) then
    raise exception using errcode = 'SOL05', message = 'price list contains SKUs from a manufacturer that does not supply you';
  end if;

  insert into public.price_lists (distributor_org_id, name, effective_from)
  values (p_distributor_id, btrim(p_name), greatest(p_effective_from, now()))
  returning id into v_id;

  insert into public.price_list_items (price_list_id, sku_id, uom_code, price_kobo)
  select v_id, (i->>'sku_id')::uuid, i->>'uom_code', (i->>'price_kobo')::bigint
  from jsonb_array_elements(p_items) i;
  return v_id;
end;
$$;

-- Current price per (distributor, sku, uom): the most recent list already in effect that prices it.
create view public.v_current_prices with (security_invoker = true) as
select distinct on (pl.distributor_org_id, i.sku_id, i.uom_code)
       pl.distributor_org_id, i.sku_id, i.uom_code, i.price_kobo, pl.id as price_list_id, pl.effective_from
from public.price_list_items i
join public.price_lists pl on pl.id = i.price_list_id
where pl.effective_from <= now()
order by pl.distributor_org_id, i.sku_id, i.uom_code, pl.effective_from desc, pl.created_at desc;

create function app.current_price_kobo(p_distributor_id uuid, p_sku_id uuid, p_uom_code text)
returns bigint
language sql stable security definer set search_path = ''
as $$
  select i.price_kobo
  from public.price_list_items i
  join public.price_lists pl on pl.id = i.price_list_id
  where pl.distributor_org_id = p_distributor_id and i.sku_id = p_sku_id and i.uom_code = p_uom_code
    and pl.effective_from <= now()
  order by pl.effective_from desc, pl.created_at desc
  limit 1
$$;
