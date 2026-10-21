-- Row level security on EVERY table in public (hard rule 6). Clients only ever SELECT;
-- all writes go through app.* command functions (security definer), so there are no
-- INSERT/UPDATE/DELETE policies at all.

do $$
declare
  t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
  end loop;
end;
$$;

-- Tenancy -------------------------------------------------------------------------------------

create policy organisations_select on public.organisations for select to authenticated using (
     (select app.is_platform_admin())
  or id = any((select app.my_org_ids())::uuid[])
  or id = any((select app.visible_retailer_ids())::uuid[])
  or id = any((select app.visible_distributor_ids())::uuid[])
  or id = any((select app.visible_manufacturer_ids())::uuid[])
);

create policy branches_select on public.branches for select to authenticated using (
  (select app.is_platform_admin()) or org_id = any((select app.my_org_ids())::uuid[])
);

create policy territories_select on public.territories for select to authenticated using (
  (select app.is_platform_admin()) or org_id = any((select app.my_org_ids())::uuid[])
);

create policy warehouses_select on public.warehouses for select to authenticated using (
  (select app.is_platform_admin()) or org_id = any((select app.my_org_ids())::uuid[])
);

create policy profiles_select on public.profiles for select to authenticated using (
  (select app.is_platform_admin()) or user_id = any((select app.visible_user_ids())::uuid[])
);

create policy memberships_select on public.memberships for select to authenticated using (
     (select app.is_platform_admin())
  or user_id = (select app.current_user_id())
  or org_id = any((select app.my_org_ids_with_role(
       array['distributor_admin', 'branch_manager', 'manufacturer_admin']::public.member_role[]))::uuid[])
  or org_id = any((select app.visible_retailer_ids())::uuid[])
);

create policy customer_relationships_select on public.customer_relationships for select to authenticated using (
     (select app.is_platform_admin())
  or (distributor_org_id = any((select app.my_org_ids())::uuid[])
      and retailer_org_id = any((select app.visible_retailer_ids())::uuid[]))
  or retailer_org_id = any((select app.my_org_ids_with_role(array['retailer']::public.member_role[]))::uuid[])
);

create policy supply_relationships_select on public.supply_relationships for select to authenticated using (
     (select app.is_platform_admin())
  or manufacturer_org_id = any((select app.my_org_ids())::uuid[])
  or distributor_org_id = any((select app.my_org_ids())::uuid[])
);

-- Catalogue -----------------------------------------------------------------------------------

create policy brands_select on public.brands for select to authenticated using (
  (select app.is_platform_admin()) or manufacturer_org_id = any((select app.visible_manufacturer_ids())::uuid[])
);

create policy skus_select on public.skus for select to authenticated using (
  (select app.is_platform_admin()) or manufacturer_org_id = any((select app.visible_manufacturer_ids())::uuid[])
);

create policy sku_uom_select on public.sku_uom for select to authenticated using (
  sku_id in (select s.id from public.skus s)
);

create policy price_lists_select on public.price_lists for select to authenticated using (
     (select app.is_platform_admin())
  or distributor_org_id = any((select app.my_org_ids())::uuid[])
  or distributor_org_id in (select cr.distributor_org_id from public.customer_relationships cr)
);

create policy price_list_items_select on public.price_list_items for select to authenticated using (
  price_list_id in (select pl.id from public.price_lists pl)
);

-- Inventory -----------------------------------------------------------------------------------

create policy stock_locations_select on public.stock_locations for select to authenticated using (
  (select app.is_platform_admin()) or id = any((select app.visible_location_ids())::uuid[])
);

create policy stock_movements_select on public.stock_movements for select to authenticated using (
  (select app.is_platform_admin()) or location_id = any((select app.visible_location_ids())::uuid[])
);

create policy stock_balances_select on public.stock_balances for select to authenticated using (
  (select app.is_platform_admin()) or location_id = any((select app.visible_location_ids())::uuid[])
);

-- Orders --------------------------------------------------------------------------------------

create policy orders_select on public.orders for select to authenticated using (
     (select app.is_platform_admin())
  or distributor_org_id = any((select app.my_org_ids_with_role(
       array['distributor_admin', 'branch_manager', 'warehouse_staff']::public.member_role[]))::uuid[])
  or (retailer_org_id = any((select app.visible_retailer_ids())::uuid[])
      and (distributor_org_id = any((select app.my_org_ids())::uuid[])
           or retailer_org_id = any((select app.my_org_ids())::uuid[])))
);

create policy order_lines_select on public.order_lines for select to authenticated using (
  order_id in (select o.id from public.orders o)
);

-- Money ---------------------------------------------------------------------------------------

create policy accounts_select on public.accounts for select to authenticated using (
  (select app.is_platform_admin()) or id = any((select app.visible_account_ids())::uuid[])
);

create policy account_balances_select on public.account_balances for select to authenticated using (
  (select app.is_platform_admin()) or account_id = any((select app.visible_account_ids())::uuid[])
);

create policy ledger_entries_select on public.ledger_entries for select to authenticated using (
  (select app.is_platform_admin()) or account_id = any((select app.visible_account_ids())::uuid[])
);

create policy journals_select on public.journals for select to authenticated using (
  (select app.is_platform_admin()) or id in (select e.journal_id from public.ledger_entries e)
);
