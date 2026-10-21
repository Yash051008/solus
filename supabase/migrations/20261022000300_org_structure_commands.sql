-- Branch / territory / warehouse management and distributor settings (Phase 3).

alter table public.organisations
  add column geofence_radius_m       integer check (geofence_radius_m is null or geofence_radius_m between 10 and 5000),
  add column geofence_max_accuracy_m integer check (geofence_max_accuracy_m is null or geofence_max_accuracy_m between 5 and 500),
  add column location_accuracy_m     integer check (location_accuracy_m is null or location_accuracy_m >= 0),
  add constraint organisations_geofence_distributor_only
    check (kind = 'distributor' or (geofence_radius_m is null and geofence_max_accuracy_m is null));

-- Platform onboarding of a manufacturer or distributor, with its first admin (an existing user).
create function app.onboard_organisation(
  p_kind public.org_kind, p_name text, p_slug text, p_admin_user_id uuid
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_org uuid;
begin
  perform app.require_role((select id from public.organisations where kind = 'platform'),
                           array['platform_admin']::public.member_role[]);
  if p_kind not in ('manufacturer', 'distributor') then
    raise exception using errcode = 'SOL05', message = 'only manufacturers and distributors are onboarded by the platform';
  end if;
  if not exists (select 1 from public.profiles where user_id = p_admin_user_id) then
    raise exception using errcode = 'SOL05', message = 'the admin user has no profile yet';
  end if;

  insert into public.organisations (kind, name, slug, status)
  values (p_kind, p_name, p_slug, 'active')
  returning id into v_org;

  insert into public.memberships (user_id, org_id, org_kind, role, status)
  values (p_admin_user_id, v_org, p_kind,
          case p_kind when 'manufacturer' then 'manufacturer_admin' else 'distributor_admin' end::public.member_role,
          'active');

  if p_kind = 'distributor' then
    perform app.ensure_account((select id from public.organisations where kind = 'platform'), 'wallet',
                               p_holder_org_id => v_org);
    perform app.ensure_account(v_org, 'partner_funds');
    perform app.ensure_account(v_org, 'sales_revenue');
    perform app.ensure_account(v_org, 'variance_offset');
  end if;
  return v_org;
end;
$$;

create function app.update_distributor_settings(
  p_org_id uuid, p_split_threshold_m integer, p_geofence_radius_m integer, p_geofence_max_accuracy_m integer
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform app.require_role(p_org_id, array['distributor_admin']::public.member_role[]);
  update public.organisations
     set split_threshold_m = p_split_threshold_m,
         geofence_radius_m = p_geofence_radius_m,
         geofence_max_accuracy_m = p_geofence_max_accuracy_m
   where id = p_org_id and kind = 'distributor';
end;
$$;

create function app.create_branch(p_org_id uuid, p_name text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform app.require_role(p_org_id, array['distributor_admin']::public.member_role[]);
  insert into public.branches (org_id, name) values (p_org_id, btrim(p_name)) returning id into v_id;
  return v_id;
end;
$$;

-- p_boundary: optional GeoJSON Polygon or MultiPolygon (WGS84). Stored as MultiPolygon; must be valid.
create function app.create_territory(p_branch_id uuid, p_name text, p_boundary jsonb default null)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id   uuid;
  v_org  uuid;
  v_geom extensions.geometry;
begin
  perform app.require_branch_manager(p_branch_id);
  select org_id into strict v_org from public.branches where id = p_branch_id;

  if p_boundary is not null then
    v_geom := extensions.st_multi(extensions.st_setsrid(extensions.st_geomfromgeojson(p_boundary::text), 4326));
    if extensions.geometrytype(v_geom) <> 'MULTIPOLYGON' or not extensions.st_isvalid(v_geom) then
      raise exception using errcode = 'SOL05', message = 'territory boundary must be a valid Polygon or MultiPolygon';
    end if;
  end if;

  insert into public.territories (org_id, branch_id, name, boundary)
  values (v_org, p_branch_id, btrim(p_name), v_geom::extensions.geography)
  returning id into v_id;
  return v_id;
end;
$$;

create function app.create_warehouse(p_branch_id uuid, p_name text, p_lat double precision, p_lng double precision)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id  uuid;
  v_org uuid;
begin
  select org_id into strict v_org from public.branches where id = p_branch_id;
  perform app.require_role(v_org, array['distributor_admin']::public.member_role[]);

  insert into public.warehouses (org_id, branch_id, name, location)
  values (v_org, p_branch_id, btrim(p_name), app.make_point(p_lat, p_lng))
  returning id into v_id;

  insert into public.stock_locations (kind, org_id, warehouse_id) values ('warehouse', v_org, v_id);
  return v_id;
end;
$$;

-- A warehouse holding stock cannot be deactivated: the stock would become unroutable but still owned.
create function app.set_warehouse_active(p_warehouse_id uuid, p_active boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_org uuid;
begin
  select org_id into strict v_org from public.warehouses where id = p_warehouse_id;
  perform app.require_role(v_org, array['distributor_admin']::public.member_role[]);

  if not p_active and exists (
    select 1 from public.stock_balances b
    join public.stock_locations sl on sl.id = b.location_id
    where sl.warehouse_id = p_warehouse_id and (b.on_hand > 0 or b.reserved > 0)
  ) then
    raise exception using errcode = 'SOL04',
      message = 'warehouse still holds stock; transfer it out before deactivating';
  end if;

  update public.warehouses set active = p_active where id = p_warehouse_id;
end;
$$;
