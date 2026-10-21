-- Authorisation helpers used INSIDE command functions (RLS helpers only filter reads).
-- Every command calls one of these first; failures raise SOL03 (forbidden).

create function app.require_user()
returns uuid
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := app.current_user_id();
begin
  if v_uid is null then
    raise exception using errcode = 'SOL03', message = 'authentication required';
  end if;
  return v_uid;
end;
$$;

create function app.has_role(p_org_id uuid, p_roles public.member_role[])
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.memberships m
    where m.user_id = app.current_user_id() and m.org_id = p_org_id
      and m.status = 'active' and m.role = any(p_roles)
  )
$$;

create function app.require_role(p_org_id uuid, p_roles public.member_role[])
returns uuid
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
begin
  if not app.has_role(p_org_id, p_roles) then
    raise exception using errcode = 'SOL03',
      message = format('requires role %s in organisation %s', array_to_string(p_roles, '|'), p_org_id);
  end if;
  return v_uid;
end;
$$;

-- distributor_admin of the branch's org, or branch_manager of that exact branch.
create function app.can_manage_branch(p_branch_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.branches b
    join public.memberships m on m.org_id = b.org_id
    where b.id = p_branch_id and m.user_id = app.current_user_id() and m.status = 'active'
      and (m.role = 'distributor_admin' or (m.role = 'branch_manager' and m.branch_id = b.id))
  )
$$;

create function app.require_branch_manager(p_branch_id uuid)
returns uuid
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
begin
  if not app.can_manage_branch(p_branch_id) then
    raise exception using errcode = 'SOL03',
      message = format('requires distributor_admin, or branch_manager of branch %s', p_branch_id);
  end if;
  return v_uid;
end;
$$;

-- Lat/lng validation + point construction (WGS84). Raises SOL05 on nonsense coordinates.
create function app.make_point(p_lat double precision, p_lng double precision)
returns extensions.geography
language plpgsql immutable set search_path = ''
as $$
begin
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception using errcode = 'SOL05', message = format('invalid coordinates (%s, %s)', p_lat, p_lng);
  end if;
  return extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography;
end;
$$;
