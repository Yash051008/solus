-- RLS scoping helpers (docs/architecture/roles-permissions.md, ADR-0004).
-- All: security definer, stable, empty search_path, built only on app.current_user_id().
-- They return arrays so policies can use  col = any((select app.fn()))  (evaluated once per statement).

create function app.is_platform_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.memberships m
    where m.user_id = app.current_user_id() and m.role = 'platform_admin' and m.status = 'active'
  )
$$;

create function app.my_org_ids()
returns uuid[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(distinct m.org_id), '{}')
  from public.memberships m
  where m.user_id = app.current_user_id() and m.status = 'active'
$$;

create function app.my_org_ids_with_role(p_roles public.member_role[])
returns uuid[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(distinct m.org_id), '{}')
  from public.memberships m
  where m.user_id = app.current_user_id() and m.status = 'active' and m.role = any(p_roles)
$$;

-- Branches a user manages or works in: their own branch memberships, plus every branch of a
-- distributor where they are distributor_admin.
create function app.my_branch_ids(p_roles public.member_role[])
returns uuid[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(distinct x.branch_id), '{}') from (
    select m.branch_id
    from public.memberships m
    where m.user_id = app.current_user_id() and m.status = 'active'
      and m.role = any(p_roles) and m.branch_id is not null
    union
    select b.id
    from public.branches b
    join public.memberships m on m.org_id = b.org_id
    where m.user_id = app.current_user_id() and m.status = 'active' and m.role = 'distributor_admin'
  ) x
$$;

-- Stock locations visible to the user.
--   distributor_admin: all of the org; branch_manager / warehouse_staff: warehouses in their branch and
--   carriers whose membership is in that branch; agent / driver: their own location.
create function app.visible_location_ids()
returns uuid[]
language sql stable security definer set search_path = ''
as $$
  with my_branches as (
    select unnest(app.my_branch_ids(array['branch_manager', 'warehouse_staff']::public.member_role[])) as branch_id
  )
  select coalesce(array_agg(distinct x.id), '{}') from (
    select sl.id
    from public.stock_locations sl
    join public.warehouses w on w.id = sl.warehouse_id
    where w.branch_id in (select branch_id from my_branches)
    union
    select sl.id
    from public.stock_locations sl
    join public.memberships m
      on m.user_id = sl.user_id and m.org_id = sl.org_id and m.role::text = sl.kind::text
    where sl.kind in ('agent', 'driver') and m.branch_id in (select branch_id from my_branches)
    union
    select sl.id
    from public.stock_locations sl
    where sl.user_id = app.current_user_id()
      and sl.org_id = any(app.my_org_ids_with_role(array['agent', 'driver']::public.member_role[]))
  ) x
$$;

-- Retailer organisations visible to the user.
--   retailer: own org; distributor_admin: all customers; branch_manager: customers in territories of their
--   branches; agent: customers in their territory.
create function app.visible_retailer_ids()
returns uuid[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(distinct x.id), '{}') from (
    select unnest(app.my_org_ids_with_role(array['retailer']::public.member_role[])) as id
    union
    select cr.retailer_org_id
    from public.customer_relationships cr
    where cr.distributor_org_id = any(app.my_org_ids_with_role(array['distributor_admin']::public.member_role[]))
    union
    select cr.retailer_org_id
    from public.customer_relationships cr
    join public.territories t on t.id = cr.territory_id
    where t.branch_id = any(app.my_branch_ids(array['branch_manager']::public.member_role[]))
    union
    select cr.retailer_org_id
    from public.customer_relationships cr
    join public.memberships m on m.territory_id = cr.territory_id and m.org_id = cr.distributor_org_id
    where m.user_id = app.current_user_id() and m.status = 'active' and m.role = 'agent'
  ) x
$$;

-- Distributors visible: own distributor orgs, distributors my retailer org buys from,
-- distributors supplied by my manufacturer org.
create function app.visible_distributor_ids()
returns uuid[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(distinct x.id), '{}') from (
    select o.id from public.organisations o
    where o.kind = 'distributor' and o.id = any(app.my_org_ids())
    union
    select cr.distributor_org_id from public.customer_relationships cr
    where cr.retailer_org_id = any(app.my_org_ids_with_role(array['retailer']::public.member_role[]))
    union
    select s.distributor_org_id from public.supply_relationships s
    where s.manufacturer_org_id = any(app.my_org_ids_with_role(array['manufacturer_admin']::public.member_role[]))
  ) x
$$;

-- Manufacturers whose catalogue the user may read.
create function app.visible_manufacturer_ids()
returns uuid[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(distinct x.id), '{}') from (
    select unnest(app.my_org_ids_with_role(array['manufacturer_admin']::public.member_role[])) as id
    union
    select s.manufacturer_org_id from public.supply_relationships s
    where s.distributor_org_id = any(app.my_org_ids())
    union
    select s.manufacturer_org_id
    from public.supply_relationships s
    join public.customer_relationships cr on cr.distributor_org_id = s.distributor_org_id
    where cr.retailer_org_id = any(app.my_org_ids_with_role(array['retailer']::public.member_role[]))
  ) x
$$;

-- People visible: myself, colleagues in my organisations, and members of retailer orgs I can see.
create function app.visible_user_ids()
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
  ) x
  where x.user_id is not null
$$;

-- Money accounts visible to the user.
--   distributor_admin: their whole book + their platform wallet; branch_manager: their book's accounts
--   with visible retailers; agent/driver: accounts where they are the counterparty;
--   retailer: own wallet + distributor-book accounts where they are the counterparty.
create function app.visible_account_ids()
returns uuid[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(distinct x.id), '{}') from (
    select a.id from public.accounts a
    where a.book_org_id = any(app.my_org_ids_with_role(array['distributor_admin']::public.member_role[]))
       or (a.account_type = 'wallet'
           and a.holder_org_id = any(app.my_org_ids_with_role(array['distributor_admin', 'retailer']::public.member_role[])))
    union
    select a.id from public.accounts a
    where a.book_org_id = any(app.my_org_ids_with_role(array['branch_manager']::public.member_role[]))
      and a.counterparty_org_id = any(app.visible_retailer_ids())
    union
    select a.id from public.accounts a
    where a.counterparty_user_id = app.current_user_id()
      and a.book_org_id = any(app.my_org_ids_with_role(array['agent', 'driver']::public.member_role[]))
    union
    select a.id from public.accounts a
    where a.counterparty_org_id = any(app.my_org_ids_with_role(array['retailer']::public.member_role[]))
  ) x
$$;
