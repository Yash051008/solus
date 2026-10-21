-- KYC results (ADR-0005) and the server-side geofence check (Phase 3).

-- Append-only history of verification attempts. Stores outcome + provider reference + HMAC digest of the
-- ID number, never the number itself, and never any data returned by the provider.
create table public.kyc_checks (
  id              uuid primary key default gen_random_uuid(),
  seq             bigint generated always as identity unique,   -- strict order (now() is per-transaction)
  org_id          uuid not null references public.organisations (id),
  subject_user_id uuid not null references public.profiles (user_id),
  id_type         text not null check (id_type in ('BVN', 'NIN')),
  outcome         text not null check (outcome in ('exact_match', 'partial_match', 'no_match', 'not_found')),
  provider        text not null check (provider ~ '^[a-z][a-z0-9_]{1,30}$'),
  provider_ref    text not null check (length(provider_ref) between 1 and 200),
  id_hash         text not null check (id_hash ~ '^[0-9a-f]{64}$'),
  checked_at      timestamptz not null default now(),
  unique (provider, provider_ref)
);
create index kyc_checks_org_idx on public.kyc_checks (org_id, id_type, seq desc);
create index kyc_checks_hash_idx on public.kyc_checks (id_hash);
create trigger kyc_checks_append_only before update or delete on public.kyc_checks
  for each row execute function app.tg_append_only();
create trigger kyc_checks_no_truncate before truncate on public.kyc_checks
  for each statement execute function app.tg_append_only();

-- 0 = none, 1 = one of BVN/NIN exact-matched (latest attempt), 2 = both. Partial matches don't count.
create function app.kyc_level(p_org_id uuid)
returns integer
language sql stable security definer set search_path = ''
as $$
  select count(*)::integer from (
    select distinct on (k.id_type) k.id_type, k.outcome
    from public.kyc_checks k
    where k.org_id = p_org_id
    order by k.id_type, k.seq desc
  ) latest
  where latest.outcome = 'exact_match'
$$;

-- Called ONLY by the server-side KYC adapter (service_role) after it has called the provider.
-- Clients must not be able to record their own verification. Idempotent on (provider, provider_ref).
create function app.record_kyc_result(
  p_org_id uuid, p_subject_user_id uuid, p_id_type text, p_outcome text,
  p_provider text, p_provider_ref text, p_id_hash text
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_dupes integer;
begin
  if not exists (select 1 from public.memberships
                 where org_id = p_org_id and user_id = p_subject_user_id and role = 'retailer') then
    raise exception using errcode = 'SOL05', message = 'subject is not the owner of this retailer organisation';
  end if;

  insert into public.kyc_checks (org_id, subject_user_id, id_type, outcome, provider, provider_ref, id_hash)
  values (p_org_id, p_subject_user_id, p_id_type, p_outcome, p_provider, p_provider_ref, p_id_hash)
  on conflict (provider, provider_ref) do nothing;

  -- Same ID number exact-matched for a different shop: surfaced to approvers, not silently blocked.
  select count(distinct k.org_id) into v_dupes
  from public.kyc_checks k
  where k.id_hash = p_id_hash and k.outcome = 'exact_match' and k.org_id <> p_org_id;

  return jsonb_build_object('kyc_level', app.kyc_level(p_org_id), 'same_identity_other_shops', v_dupes);
end;
$$;

-- Geofence ----------------------------------------------------------------------------------------
-- Defaults when a distributor hasn't configured its own: 150 m radius, GPS fix must be <= 50 m.
-- Fails closed: missing or poor accuracy is a failure, never a pass.
create function app.evaluate_geofence(
  p_distributor_id uuid, p_retailer_org_id uuid,
  p_lat double precision, p_lng double precision, p_accuracy_m double precision
)
returns table (ok boolean, reason text, distance_m integer, radius_m integer, max_accuracy_m integer)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_radius   integer;
  v_max_acc  integer;
  v_shop     extensions.geography;
  v_distance double precision;
begin
  select coalesce(o.geofence_radius_m, 150), coalesce(o.geofence_max_accuracy_m, 50)
    into v_radius, v_max_acc
  from public.organisations o where o.id = p_distributor_id and o.kind = 'distributor';
  if not found then
    raise exception using errcode = 'SOL05', message = 'unknown distributor';
  end if;

  if not exists (select 1 from public.customer_relationships cr
                 where cr.distributor_org_id = p_distributor_id and cr.retailer_org_id = p_retailer_org_id
                   and cr.status = 'active') then
    return query select false, 'not_a_customer', null::integer, v_radius, v_max_acc;
    return;
  end if;

  select location into v_shop from public.organisations where id = p_retailer_org_id;
  if v_shop is null then
    return query select false, 'no_shop_location', null::integer, v_radius, v_max_acc;
    return;
  end if;

  v_distance := extensions.st_distance(v_shop, app.make_point(p_lat, p_lng));   -- metres, spheroid

  if p_accuracy_m is null or p_accuracy_m < 0 or p_accuracy_m > v_max_acc then
    return query select false, 'low_accuracy', round(v_distance)::integer, v_radius, v_max_acc;
  elsif v_distance > v_radius then
    return query select false, 'outside_radius', round(v_distance)::integer, v_radius, v_max_acc;
  else
    return query select true, 'ok', round(v_distance)::integer, v_radius, v_max_acc;
  end if;
end;
$$;

-- Client-callable variant: only for a field user of that distributor who can see the retailer.
create function app.check_geofence(
  p_distributor_id uuid, p_retailer_org_id uuid,
  p_lat double precision, p_lng double precision, p_accuracy_m double precision
)
returns table (ok boolean, reason text, distance_m integer, radius_m integer, max_accuracy_m integer)
language plpgsql stable security definer set search_path = ''
as $$
begin
  perform app.require_role(p_distributor_id,
    array['distributor_admin', 'branch_manager', 'agent', 'driver']::public.member_role[]);
  if not (p_retailer_org_id = any(app.visible_retailer_ids())) then
    raise exception using errcode = 'SOL03', message = 'retailer not visible to you';
  end if;
  return query select * from app.evaluate_geofence(p_distributor_id, p_retailer_org_id, p_lat, p_lng, p_accuracy_m);
end;
$$;
