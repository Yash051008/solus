-- Approvers must see who is applying: people with a join request to an org where the caller is
-- distributor_admin or branch_manager become visible (profile name + phone only, via profiles RLS).
create or replace function app.visible_user_ids()
returns uuid[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(distinct x.user_id), '{}') from (
    select app.current_user_id() as user_id
    union
    select m.user_id from public.memberships m
    where m.org_id = any(app.my_org_ids()) and m.org_id not in (
      select o.id from public.organisations o where o.kind = 'platform'
    )
    union
    select m.user_id from public.memberships m
    where m.org_id = any(app.visible_retailer_ids())
    union
    select jr.user_id from public.join_requests jr
    where jr.org_id = any(app.my_org_ids_with_role(array['distributor_admin', 'branch_manager']::public.member_role[]))
  ) x
  where x.user_id is not null
$$;
