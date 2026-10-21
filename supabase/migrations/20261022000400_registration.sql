-- Registration and distributor approval (Phase 3).
--   Retailers self-register a shop and request a distributor; the distributor approves (assigning the
--   territory) or rejects. Staff/agents/drivers request to join a distributor; an admin (or the branch
--   manager, for roles below branch manager in their own branch) approves with branch/territory.

alter table public.customer_relationships
  add column decided_by      uuid references public.profiles (user_id),
  add column decided_at      timestamptz,
  add column decision_reason text;

create table public.join_requests (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles (user_id),
  org_id          uuid not null,
  org_kind        public.org_kind not null default 'distributor' check (org_kind = 'distributor'),
  requested_role  public.member_role not null
                  check (requested_role in ('branch_manager', 'warehouse_staff', 'driver', 'agent')),
  note            text check (length(note) <= 500),
  status          public.record_status not null default 'pending'
                  check (status in ('pending', 'active', 'rejected')),
  decided_by      uuid references public.profiles (user_id),
  decided_at      timestamptz,
  decision_reason text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  foreign key (org_id, org_kind) references public.organisations (id, kind)
);
create unique index join_requests_one_pending on public.join_requests (user_id, org_id, requested_role)
  where status = 'pending';
create index join_requests_org_status_idx on public.join_requests (org_id, status);
create index join_requests_user_idx on public.join_requests (user_id);
create trigger join_requests_updated_at before update on public.join_requests
  for each row execute function app.tg_set_updated_at();

-- Create or update the caller's own profile (minimal personal data).
create function app.upsert_my_profile(p_full_name text, p_phone_e164 text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
begin
  insert into public.profiles (user_id, full_name, phone_e164)
  values (v_uid, btrim(p_full_name), p_phone_e164)
  on conflict (user_id) do update
    set full_name = excluded.full_name, phone_e164 = excluded.phone_e164;
end;
$$;

-- Active distributors a newcomer can choose from (they can't read organisations via RLS yet).
create function app.registration_directory()
returns table (id uuid, name text)
language sql stable security definer set search_path = ''
as $$
  select o.id, o.name from public.organisations o
  where o.kind = 'distributor' and o.status = 'active' and app.current_user_id() is not null
  order by o.name
$$;

-- Territory suggestion for a point: a territory whose boundary contains it, else a territory of the
-- branch whose nearest warehouse is closest. The approver confirms or changes it.
create function app.suggest_territory(p_distributor_id uuid, p_point extensions.geography)
returns uuid
language sql stable security definer set search_path = ''
as $$
  select coalesce(
    (select t.id from public.territories t
     where t.org_id = p_distributor_id and t.boundary is not null
       and extensions.st_covers(t.boundary, p_point)
     order by t.name limit 1),
    (select t.id from public.warehouses w
     join public.territories t on t.branch_id = w.branch_id
     where w.org_id = p_distributor_id and w.active
     order by extensions.st_distance(w.location, p_point), t.name limit 1)
  )
$$;

create function app.register_retailer(
  p_business_name  text,
  p_full_name      text,
  p_phone_e164     text,
  p_lat            double precision,
  p_lng            double precision,
  p_accuracy_m     integer,
  p_distributor_id uuid
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid       uuid := app.require_user();
  v_org       uuid;
  v_point     extensions.geography := app.make_point(p_lat, p_lng);
  v_territory uuid;
begin
  if exists (select 1 from public.memberships where user_id = v_uid and role = 'retailer') then
    raise exception using errcode = 'SOL04', message = 'this account already has a registered shop';
  end if;
  if not exists (select 1 from public.organisations
                 where id = p_distributor_id and kind = 'distributor' and status = 'active') then
    raise exception using errcode = 'SOL05', message = 'unknown or inactive distributor';
  end if;
  if p_accuracy_m is null or p_accuracy_m < 0 then
    raise exception using errcode = 'SOL05', message = 'GPS accuracy (metres) is required for the shop location';
  end if;

  v_territory := app.suggest_territory(p_distributor_id, v_point);
  if v_territory is null then
    raise exception using errcode = 'SOL04', message = 'this distributor has no territories yet';
  end if;

  perform app.upsert_my_profile(p_full_name, p_phone_e164);

  insert into public.organisations (kind, name, slug, status, location, location_accuracy_m)
  values ('retailer', btrim(p_business_name), 'retailer-' || replace(gen_random_uuid()::text, '-', ''),
          'pending', v_point, p_accuracy_m)
  returning id into v_org;

  insert into public.memberships (user_id, org_id, org_kind, role, status)
  values (v_uid, v_org, 'retailer', 'retailer', 'active');   -- owner of their own shop

  insert into public.customer_relationships (distributor_org_id, retailer_org_id, territory_id, status)
  values (p_distributor_id, v_org, v_territory, 'pending');

  perform app.ensure_account((select id from public.organisations where kind = 'platform'), 'wallet',
                             p_holder_org_id => v_org);
  return v_org;
end;
$$;

-- An existing retailer asks an additional distributor to serve them.
create function app.request_distributor(p_retailer_org_id uuid, p_distributor_id uuid)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id        uuid;
  v_territory uuid;
begin
  perform app.require_role(p_retailer_org_id, array['retailer']::public.member_role[]);
  v_territory := app.suggest_territory(p_distributor_id,
                   (select location from public.organisations where id = p_retailer_org_id));
  if v_territory is null then
    raise exception using errcode = 'SOL04', message = 'this distributor has no territories yet';
  end if;
  insert into public.customer_relationships (distributor_org_id, retailer_org_id, territory_id, status)
  values (p_distributor_id, p_retailer_org_id, v_territory, 'pending')
  returning id into v_id;
  return v_id;
end;
$$;

create function app.decide_customer(
  p_relationship_id uuid, p_approve boolean, p_territory_id uuid default null, p_reason text default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid       uuid := app.require_user();
  v_cr        public.customer_relationships;
  v_territory uuid;
  v_branch    uuid;
begin
  select * into v_cr from public.customer_relationships where id = p_relationship_id for update;
  if not found then
    raise exception using errcode = 'SOL05', message = 'customer relationship not found';
  end if;
  if v_cr.status <> 'pending' then
    raise exception using errcode = 'SOL04', message = format('relationship is already %s', v_cr.status);
  end if;

  v_territory := coalesce(p_territory_id, v_cr.territory_id);
  select branch_id into v_branch from public.territories
   where id = v_territory and org_id = v_cr.distributor_org_id;
  if v_branch is null then
    raise exception using errcode = 'SOL05', message = 'territory does not belong to this distributor';
  end if;
  perform app.require_branch_manager(v_branch);

  if exists (select 1 from public.memberships where user_id = v_uid and org_id = v_cr.retailer_org_id) then
    raise exception using errcode = 'SOL03', message = 'you cannot approve your own shop';
  end if;
  if not p_approve and nullif(btrim(p_reason), '') is null then
    raise exception using errcode = 'SOL05', message = 'a reason is required to reject';
  end if;

  update public.customer_relationships
     set status = case when p_approve then 'active' else 'rejected' end::public.record_status,
         territory_id = v_territory, decided_by = v_uid, decided_at = now(), decision_reason = p_reason
   where id = p_relationship_id;

  if p_approve then
    update public.organisations set status = 'active' where id = v_cr.retailer_org_id and status = 'pending';
    perform app.ensure_account(v_cr.distributor_org_id, 'receivables', p_counterparty_org_id => v_cr.retailer_org_id);
    perform app.ensure_account(v_cr.distributor_org_id, 'trade_credit', p_counterparty_org_id => v_cr.retailer_org_id);
  end if;
end;
$$;

create function app.request_to_join(
  p_distributor_id uuid, p_role public.member_role, p_full_name text, p_phone_e164 text, p_note text default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
  v_id  uuid;
begin
  if not exists (select 1 from public.organisations
                 where id = p_distributor_id and kind = 'distributor' and status = 'active') then
    raise exception using errcode = 'SOL05', message = 'unknown or inactive distributor';
  end if;
  if exists (select 1 from public.memberships
             where user_id = v_uid and org_id = p_distributor_id and role = p_role) then
    raise exception using errcode = 'SOL04', message = 'you already hold this role';
  end if;
  perform app.upsert_my_profile(p_full_name, p_phone_e164);
  insert into public.join_requests (user_id, org_id, requested_role, note)
  values (v_uid, p_distributor_id, p_role, p_note)
  returning id into v_id;
  return v_id;
end;
$$;

create function app.decide_join_request(
  p_request_id uuid, p_approve boolean, p_branch_id uuid default null,
  p_territory_id uuid default null, p_reason text default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
  v_req public.join_requests;
begin
  select * into v_req from public.join_requests where id = p_request_id for update;
  if not found then
    raise exception using errcode = 'SOL05', message = 'join request not found';
  end if;
  if v_req.status <> 'pending' then
    raise exception using errcode = 'SOL04', message = format('request is already %s', v_req.status);
  end if;
  if v_req.user_id = v_uid then
    raise exception using errcode = 'SOL03', message = 'you cannot decide your own request';
  end if;

  -- Admins decide anything; branch managers decide roles below them, in their own branch only.
  if not app.has_role(v_req.org_id, array['distributor_admin']::public.member_role[]) then
    if v_req.requested_role = 'branch_manager' or p_branch_id is null or not app.can_manage_branch(p_branch_id) then
      raise exception using errcode = 'SOL03',
        message = 'requires distributor_admin (or branch_manager of the target branch for staff/agent/driver)';
    end if;
  end if;

  if not p_approve then
    if nullif(btrim(p_reason), '') is null then
      raise exception using errcode = 'SOL05', message = 'a reason is required to reject';
    end if;
    update public.join_requests
       set status = 'rejected', decided_by = v_uid, decided_at = now(), decision_reason = p_reason
     where id = p_request_id;
    return;
  end if;

  if p_branch_id is null or not exists (select 1 from public.branches where id = p_branch_id and org_id = v_req.org_id) then
    raise exception using errcode = 'SOL05', message = 'a branch of this distributor is required';
  end if;

  insert into public.memberships (user_id, org_id, org_kind, role, branch_id, territory_id, status)
  values (v_req.user_id, v_req.org_id, 'distributor', v_req.requested_role, p_branch_id,
          case when v_req.requested_role = 'agent' then p_territory_id end, 'active');

  if v_req.requested_role in ('agent', 'driver') then
    insert into public.stock_locations (kind, org_id, user_id)
    values (v_req.requested_role::text::public.location_kind, v_req.org_id, v_req.user_id)
    on conflict (org_id, kind, user_id) do nothing;
    perform app.ensure_account(v_req.org_id, 'cash_in_transit', p_counterparty_user_id => v_req.user_id);
    perform app.ensure_account(v_req.org_id, 'variance', p_counterparty_user_id => v_req.user_id);
    perform app.ensure_account(v_req.org_id, 'receivables', p_counterparty_user_id => v_req.user_id);
  end if;

  update public.join_requests
     set status = 'active', decided_by = v_uid, decided_at = now(), decision_reason = p_reason
   where id = p_request_id;
end;
$$;
