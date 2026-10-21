-- Explicit privileges. Clients (authenticated) may SELECT business tables (filtered by RLS) and
-- EXECUTE only the RLS helper functions. No client role can write any table directly.
-- Command functions are granted individually in the phase that introduces them.

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all tables in schema audit from anon, authenticated, service_role;
revoke all on all tables in schema private from anon, authenticated, service_role;
revoke all on all functions in schema public from public, anon, authenticated;
revoke all on all functions in schema app from public, anon, authenticated;
revoke all on all functions in schema audit from public, anon, authenticated;

grant select on
  public.organisations, public.branches, public.territories, public.warehouses, public.profiles,
  public.memberships, public.customer_relationships, public.supply_relationships,
  public.brands, public.skus, public.sku_uom, public.price_lists, public.price_list_items,
  public.stock_locations, public.stock_movements, public.stock_balances,
  public.orders, public.order_lines,
  public.accounts, public.journals, public.ledger_entries, public.account_balances,
  public.v_account_balances
to authenticated;

-- Policy helpers run as the querying user, so authenticated needs EXECUTE on them (and only them).
grant execute on function
  app.current_user_id(),
  app.is_platform_admin(),
  app.my_org_ids(),
  app.my_org_ids_with_role(public.member_role[]),
  app.my_branch_ids(public.member_role[]),
  app.visible_location_ids(),
  app.visible_retailer_ids(),
  app.visible_distributor_ids(),
  app.visible_manufacturer_ids(),
  app.visible_user_ids(),
  app.visible_account_ids(),
  app.account_normal_side(public.account_type)
to authenticated;

-- service_role (server-side adapters) bypasses RLS, so take away direct writes to ledgers,
-- projections and audit: adapters must call app.* functions like everyone else.
revoke insert, update, delete, truncate on
  public.stock_movements, public.stock_balances, public.journals, public.ledger_entries,
  public.account_balances
from service_role;
