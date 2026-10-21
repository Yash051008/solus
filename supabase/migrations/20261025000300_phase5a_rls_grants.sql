-- RLS, audit, grants for Phase 5a.

alter table public.stock_requests enable row level security;
alter table public.stock_request_lines enable row level security;
alter table public.shipment_lines enable row level security;
alter table public.push_sales enable row level security;
alter table public.push_sale_lines enable row level security;
alter table public.variance_cases enable row level security;

create policy stock_requests_select on public.stock_requests for select to authenticated using (
  (select app.is_platform_admin())
  or warehouse_id = any((select app.visible_warehouse_ids())::uuid[])
  or agent_user_id = (select app.current_user_id()));
create policy stock_request_lines_select on public.stock_request_lines for select to authenticated using (
  request_id in (select r.id from public.stock_requests r));
create policy shipment_lines_select on public.shipment_lines for select to authenticated using (
  (select app.is_platform_admin()) or shipment_id = any((select app.visible_shipment_ids())::uuid[]));
create policy push_sales_select on public.push_sales for select to authenticated using (
  (select app.is_platform_admin())
  or shipment_id = any((select app.visible_shipment_ids())::uuid[])
  or retailer_org_id = any((select app.my_org_ids_with_role(array['retailer']::public.member_role[]))::uuid[]));
create policy push_sale_lines_select on public.push_sale_lines for select to authenticated using (
  sale_id in (select s.id from public.push_sales s));
create policy variance_cases_select on public.variance_cases for select to authenticated using (
  (select app.is_platform_admin()) or shipment_id = any((select app.visible_shipment_ids())::uuid[]));

select audit.attach(t::regclass) from unnest(array[
  'public.stock_requests', 'public.stock_request_lines', 'public.shipment_lines',
  'public.push_sales', 'public.push_sale_lines', 'public.variance_cases', 'private.otp_challenges']) t;

revoke all on public.stock_requests, public.stock_request_lines, public.shipment_lines, public.push_sales,
  public.push_sale_lines, public.variance_cases from anon, authenticated;
grant select on public.stock_requests, public.stock_request_lines, public.shipment_lines, public.push_sales,
  public.push_sale_lines, public.variance_cases to authenticated;

revoke all on function
  app.open_otp_challenge(text, text, uuid, uuid, uuid, text), app.issue_otp_code(uuid),
  app.verify_otp(uuid, text), app.piece_price_kobo(uuid, uuid), app.request_stock(uuid, jsonb, text),
  app.decide_stock_request(uuid, boolean, jsonb, text), app.start_handover(uuid), app.complete_push_handover(uuid),
  app.apply_push_sale(uuid, uuid, uuid, jsonb, double precision, double precision, double precision, text),
  app.record_push_sale(uuid, uuid, jsonb, double precision, double precision, double precision, text),
  app.start_push_return(uuid, jsonb), app.settle_carrier(uuid), app.complete_push_return(uuid, text),
  app.confirm_return(uuid), app.resolve_variance(uuid, text, text), app.close_shipment(uuid)
from public, anon, authenticated;

grant execute on function
  app.verify_otp(uuid, text), app.request_stock(uuid, jsonb, text),
  app.decide_stock_request(uuid, boolean, jsonb, text), app.start_handover(uuid),
  app.record_push_sale(uuid, uuid, jsonb, double precision, double precision, double precision, text),
  app.start_push_return(uuid, jsonb), app.confirm_return(uuid), app.resolve_variance(uuid, text, text),
  app.close_shipment(uuid)
to authenticated;

-- The SMS adapter alone receives plaintext codes.
grant execute on function app.issue_otp_code(uuid) to service_role;
