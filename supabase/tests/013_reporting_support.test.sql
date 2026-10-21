-- Phase 6a: reporting views stay tenant-scoped, the manufacturer sees aggregates only, notifications are
-- private to their user, support tickets and dispute resolution respect roles.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

create temp table ids as select split_part(email, '@', 1) as handle, id from auth.users;
create temp table f as select
  (select id from public.organisations where slug = 'lagos-prime') as lp,
  (select id from public.organisations where slug = 'abuja-central') as ac,
  (select id from public.organisations where slug = 'sunrise') as mfr,
  (select id from public.organisations where slug = 'retailer-05') as shop5,
  (select id from public.tickets where category = 'delivery' and distributor_org_id = (select id from public.organisations where slug = 'lagos-prime')) as lp_dispute_ticket;
create temp table t (name text primary key, id uuid);
create function pg_temp.uid(h text) returns uuid language sql as $$ select id from pg_temp.ids where handle = h $$;
create function pg_temp.as_user(h text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(h), 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
grant select, insert on ids, f, t to authenticated;
grant execute on function pg_temp.uid(text), pg_temp.as_user(text) to authenticated;

-- Reporting -------------------------------------------------------------------------------------------
select pg_temp.as_user('lp.admin');
select is((select count(*)::int from public.v_sales_daily where org_id <> (select lp from f)), 0, 'a distributor admin sees only their own sales');
select ok((select sum(revenue_kobo) from public.v_sales_daily) > 0, 'and their sales are there');
select is((select count(*)::int from public.v_agent_leaderboard where org_id <> (select lp from f)), 0, 'leaderboard is tenant-scoped');
select ok((select sum(value_kobo) from public.v_inventory_value) > 0, 'inventory is valued at current prices');
select pg_temp.as_user('retailer05');
select is((select count(*)::int from public.v_inventory_value), 0, 'shops see no inventory');
select pg_temp.as_user('sunrise.admin');
select results_eq($$ select count(distinct distributor_org_id)::int, (sum(qty_pieces) > 0) from app.manufacturer_summary((select mfr from f)) $$,
                  $$ values (2, true) $$, 'manufacturer gets totals per supplied distributor');
select is((select count(*)::int from public.v_sales_daily), 0, 'but cannot read the distributors'' detailed sales');
select pg_temp.as_user('lp.admin');
select throws_ok($$ select * from app.manufacturer_summary((select mfr from f)) $$, 'SOL03', null, 'only the manufacturer reads its summary');

-- Notifications ---------------------------------------------------------------------------------------
select pg_temp.as_user('retailer05');
select ok((select count(*) from public.notifications where kind = 'order') > 0, 'the shop was notified of its order progress');
select is((select count(*)::int from public.notifications where user_id <> pg_temp.uid('retailer05')), 0, 'notifications are private');
select ok(app.mark_notifications_read() > 0, 'mark all read');
select is((select count(*)::int from public.notifications where read_at is null), 0, 'nothing unread');

-- Support -----------------------------------------------------------------------------------------------
select pg_temp.as_user('retailer05');
insert into t select 'tk', app.open_ticket((select shop5 from f), (select lp from f), 'Wallet top-up missing', 'payment', 'I sent N5,000 yesterday');
select pg_temp.as_user('ac.admin');
select is((select count(*)::int from public.tickets where id = (select id from t where name = 'tk')), 0, 'another distributor cannot see the ticket');
select pg_temp.as_user('lp.bm.ikeja');
select lives_ok($$ select app.post_ticket_message((select id from t where name = 'tk'), 'Checking with the bank now') $$, 'the distributor replies');
select pg_temp.as_user('retailer05');
select throws_ok($$ select app.resolve_ticket((select id from t where name = 'tk'), 'done') $$, 'SOL03', null, 'only the distributor resolves');
select pg_temp.as_user('lp.bm.ikeja');
select app.resolve_ticket((select lp_dispute_ticket from f), 'Replacement carton sent on next run');
reset role;
select is((select status from public.order_disputes where id = (select dispute_id from public.tickets where id = (select lp_dispute_ticket from f))),
          'resolved', 'resolving the dispute ticket resolves the delivery dispute');

select * from finish();
rollback;
