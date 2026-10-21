-- Read views exposing coordinates as plain lat/lng (geography columns serialise as hex EWKB).
-- security_invoker: the caller's RLS on the underlying tables applies unchanged.

create view public.v_warehouses with (security_invoker = true) as
select w.id, w.org_id, w.branch_id, w.name, w.active,
       extensions.st_y(w.location::extensions.geometry) as lat,
       extensions.st_x(w.location::extensions.geometry) as lng
from public.warehouses w;

create view public.v_organisations with (security_invoker = true) as
select o.id, o.kind, o.name, o.slug, o.status,
       extensions.st_y(o.location::extensions.geometry) as lat,
       extensions.st_x(o.location::extensions.geometry) as lng,
       o.location_accuracy_m, o.split_threshold_m, o.geofence_radius_m, o.geofence_max_accuracy_m
from public.organisations o;

create view public.v_territories with (security_invoker = true) as
select t.id, t.org_id, t.branch_id, t.name, (t.boundary is not null) as has_boundary
from public.territories t;

grant select on public.v_warehouses, public.v_organisations, public.v_territories to authenticated;
