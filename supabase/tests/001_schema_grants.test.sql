-- Structural guarantees: RLS everywhere, no client write grants, internal functions not callable
-- by clients, auth.uid() only behind the seam, audit attached to every business table.
begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

select is(
  (select array_agg(tablename::text order by tablename) from pg_tables
   where schemaname = 'public' and not rowsecurity),
  null,
  'RLS is enabled on every table in public'
);

select is(
  (select array_agg(format('%s:%s:%s', grantee, table_name, privilege_type) order by 1)
   from information_schema.role_table_grants
   where table_schema = 'public' and grantee in ('anon', 'authenticated', 'public')
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER')),
  null,
  'anon/authenticated hold no write privilege on any public table'
);

select is(
  (select array_agg(format('%s:%s', grantee, table_name) order by 1)
   from information_schema.role_table_grants
   where table_schema = 'public' and grantee = 'anon'),
  null,
  'anon holds no privilege at all on public tables'
);

select is(
  (select array_agg(format('%s:%s.%s', grantee, table_schema, table_name) order by 1)
   from information_schema.role_table_grants
   where table_schema in ('audit', 'private') and grantee in ('anon', 'authenticated', 'service_role')),
  null,
  'no client or service role privilege on audit/private tables'
);

select is(
  (select array_agg(format('service_role:%s:%s', table_name, privilege_type) order by 1)
   from information_schema.role_table_grants
   where table_schema = 'public' and grantee = 'service_role'
     and table_name in ('stock_movements', 'stock_balances', 'journals', 'ledger_entries', 'account_balances')
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')),
  null,
  'service_role cannot write ledgers or projections directly'
);

-- Explicit allowlist: adding a client-callable function requires adding it here, on purpose.
select is(
  (select array_agg(p.proname::text order by 1)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('app', 'audit', 'private', 'public')
     and has_function_privilege('authenticated', p.oid, 'execute')
     and p.proname not in (
       -- RLS helpers
       'current_user_id', 'is_platform_admin', 'my_org_ids', 'my_org_ids_with_role', 'my_branch_ids',
       'visible_location_ids', 'visible_retailer_ids', 'visible_distributor_ids', 'visible_manufacturer_ids',
       'visible_user_ids', 'visible_account_ids', 'account_normal_side',
       -- Phase 3 commands (each authorises internally)
       'onboard_organisation', 'update_distributor_settings', 'create_branch', 'create_territory',
       'create_warehouse', 'set_warehouse_active', 'upsert_my_profile', 'registration_directory',
       'register_retailer', 'request_distributor', 'decide_customer', 'request_to_join',
       'decide_join_request', 'kyc_level', 'check_geofence',
       -- Phase 4 helpers + commands
       'visible_warehouse_ids', 'my_carrier_location_ids', 'visible_shipment_ids', 'visible_order_ids',
       'create_brand', 'create_sku', 'add_sku_uom', 'set_sku_active', 'publish_price_list',
       'record_receipt', 'request_adjustment', 'decide_adjustment',
       'create_transfer', 'dispatch_transfer', 'receive_transfer', 'resolve_transfer_shortage',
       'place_order', 'decide_split', 'cancel_order', 'create_batch', 'mark_batch_packed', 'dispatch_batch',
       'accept_dispatch', 'decline_dispatch', 'record_delivery', 'confirm_delivery', 'dispute_delivery',
       'start_return', 'confirm_return', 'close_shipment',
       -- Phase 5a commands
       'verify_otp', 'request_stock', 'decide_stock_request', 'start_handover', 'record_push_sale',
       'start_push_return', 'resolve_variance',
       -- Phase 5b-2 commands
       'register_device', 'sync_agent_events', 'review_accept_into_variance', 'review_dismiss',
       -- Phase 5b-1 commands
       'order_amount_due', 'allocate_receipt', 'set_credit_limit', 'start_order_payment', 'record_delivery_cash',
       'repay_credit', 'reconcile_provider',
       -- Phase 6 commands / helpers
       'manufacturer_summary', 'mark_notifications_read', 'open_ticket', 'post_ticket_message', 'resolve_ticket',
       'round_div')),
  null,
  'authenticated can execute only allow-listed functions (no ledger primitives, no adapter-only functions)'
);

select is(
  (select array_agg(p.oid::regprocedure::text order by 1)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('app', 'audit', 'private', 'public')
     and p.prosrc ilike '%auth.uid%'
     and p.oid <> 'app.current_user_id()'::regprocedure),
  null,
  'auth.uid() appears in no function except app.current_user_id() (ADR-0004 seam)'
);

select is(
  (select array_agg(format('%s.%s', tablename, policyname) order by 1)
   from pg_policies
   where coalesce(qual, '') ilike '%auth.uid%' or coalesce(with_check, '') ilike '%auth.uid%'),
  null,
  'no RLS policy references auth.uid() directly'
);

select is(
  (select array_agg(t.tablename::text order by 1)
   from pg_tables t
   where t.schemaname = 'public'
     and t.tablename not in ('stock_balances', 'account_balances', 'notifications')   -- derived from audited rows
     and not exists (
       select 1 from pg_trigger tg
       where tg.tgrelid = format('public.%I', t.tablename)::regclass and tg.tgname = 'audit_log')),
  null,
  'every business table (all but projections and derived notifications) has the audit trigger'
);

select ok(not has_function_privilege('authenticated', 'app.record_provider_event(text,text,text,text,bigint,text,timestamptz)', 'execute')
          and has_function_privilege('service_role', 'app.record_provider_event(text,text,text,text,bigint,text,timestamptz)', 'execute'),
          'only the server webhook adapter can post provider events');
select ok(not has_function_privilege('authenticated', 'app.issue_otp_code(uuid)', 'execute')
          and has_function_privilege('service_role', 'app.issue_otp_code(uuid)', 'execute'),
          'only the server SMS adapter can obtain OTP codes');
select ok(not has_function_privilege('authenticated', 'app.record_kyc_result(uuid,uuid,text,text,text,text,text)', 'execute'),
          'clients cannot record their own KYC result');
select ok(has_function_privilege('service_role', 'app.record_kyc_result(uuid,uuid,text,text,text,text,text)', 'execute'),
          'the server-side KYC adapter (service_role) can record results');

select * from finish();
rollback;
