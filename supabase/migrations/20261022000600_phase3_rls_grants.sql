-- RLS, audit and grants for Phase 3 tables and commands.

alter table public.join_requests enable row level security;
alter table public.kyc_checks enable row level security;

create policy join_requests_select on public.join_requests for select to authenticated using (
     (select app.is_platform_admin())
  or user_id = (select app.current_user_id())
  or org_id = any((select app.my_org_ids_with_role(
       array['distributor_admin', 'branch_manager']::public.member_role[]))::uuid[])
);

create policy kyc_checks_select on public.kyc_checks for select to authenticated using (
     (select app.is_platform_admin())
  or org_id = any((select app.visible_retailer_ids())::uuid[])
);

select audit.attach('public.join_requests'::regclass);
select audit.attach('public.kyc_checks'::regclass);

revoke all on public.join_requests, public.kyc_checks from anon, authenticated;
grant select on public.join_requests to authenticated;
-- Column-level: clients never read the identity digest or the provider reference.
grant select (id, org_id, subject_user_id, id_type, outcome, provider, checked_at) on public.kyc_checks to authenticated;
revoke insert, update, delete, truncate on public.kyc_checks from service_role;

revoke all on all functions in schema app from public, anon, authenticated;

-- Re-grant the Phase 2 RLS helpers (the blanket revoke above covers them too).
grant execute on function
  app.current_user_id(), app.is_platform_admin(), app.my_org_ids(),
  app.my_org_ids_with_role(public.member_role[]), app.my_branch_ids(public.member_role[]),
  app.visible_location_ids(), app.visible_retailer_ids(), app.visible_distributor_ids(),
  app.visible_manufacturer_ids(), app.visible_user_ids(), app.visible_account_ids(),
  app.account_normal_side(public.account_type)
to authenticated;

-- Phase 3 client commands (each performs its own authorisation).
grant execute on function
  app.onboard_organisation(public.org_kind, text, text, uuid),
  app.update_distributor_settings(uuid, integer, integer, integer),
  app.create_branch(uuid, text),
  app.create_territory(uuid, text, jsonb),
  app.create_warehouse(uuid, text, double precision, double precision),
  app.set_warehouse_active(uuid, boolean),
  app.upsert_my_profile(text, text),
  app.registration_directory(),
  app.register_retailer(text, text, text, double precision, double precision, integer, uuid),
  app.request_distributor(uuid, uuid),
  app.decide_customer(uuid, boolean, uuid, text),
  app.request_to_join(uuid, public.member_role, text, text, text),
  app.decide_join_request(uuid, boolean, uuid, uuid, text),
  app.kyc_level(uuid),
  app.check_geofence(uuid, uuid, double precision, double precision, double precision)
to authenticated;

-- Server-side adapters only.
grant execute on function
  app.record_kyc_result(uuid, uuid, text, text, text, text, text)
to service_role;
