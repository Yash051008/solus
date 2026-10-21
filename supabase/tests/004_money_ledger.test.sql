-- Money ledger invariants (hard rule 2): zero-sum per book, idempotency, append-only,
-- impossible balances rejected, projection equals ledger.
begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

create temp table fx as
select
  p.id as platform, d.id as dist, r.id as retailer,
  app.ensure_account(p.id, 'provider_clearing', p_provider => 'mockpay') as clearing,
  app.ensure_account(p.id, 'wallet', p_holder_org_id => r.id) as r_wallet,
  app.ensure_account(p.id, 'wallet', p_holder_org_id => d.id) as d_wallet,
  app.ensure_account(d.id, 'partner_funds') as d_funds,
  app.ensure_account(d.id, 'sales_revenue') as d_revenue,
  app.ensure_account(d.id, 'receivables', p_counterparty_org_id => r.id) as d_recv,
  app.ensure_account(d.id, 'trade_credit', p_counterparty_org_id => r.id) as d_credit
from public.organisations p, public.organisations d, public.organisations r
where p.slug = 'solus-platform' and d.slug = 'lagos-prime' and r.slug = 'retailer-03';

create function pg_temp.entries(variadic p_pairs text[]) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('account_id', p_pairs[i], 'amount_kobo', p_pairs[i + 1]))
  from generate_series(1, array_length(p_pairs, 1), 2) i
$$;

-- seed: retailer-03 wallet = N100,000 + 3 x N5,000 = N115,000 (credit-normal => -11,500,000 signed)
select is((select balance_kobo from public.v_account_balances, fx where account_id = fx.r_wallet),
          11500000::bigint, 'seeded wallet shows N115,000.00 in natural sign');

select is(app.ensure_account(fx.platform, 'wallet', p_holder_org_id => fx.retailer), fx.r_wallet,
          'ensure_account is idempotent') from fx;

-- Posting + idempotency ----------------------------------------------------------------------
create temp table posted as
select app.post_journal('va_inflow', 'test:inflow:0001',
         pg_temp.entries(fx.clearing::text, '250000', fx.r_wallet::text, '-250000')) as id
from fx;

select is((select balance_kobo from public.v_account_balances, fx where account_id = fx.r_wallet),
          11750000::bigint, 'a balanced inflow of N2,500 credits the wallet');
select is(app.post_journal('va_inflow', 'test:inflow:0001',
            pg_temp.entries(fx.clearing::text, '250000', fx.r_wallet::text, '-250000')),
          (select id from posted), 'replaying the same idempotency key returns the original journal')
from fx;
select is((select count(*)::int from public.ledger_entries where journal_id = (select id from posted)),
          2, 'the replay posted no new entries');
select is((select balance_kobo from public.v_account_balances, fx where account_id = fx.r_wallet),
          11750000::bigint, 'the replay did not credit the wallet twice');
select throws_ok($$ select app.post_journal('va_inflow', 'test:inflow:0001',
                      pg_temp.entries(fx.clearing::text, '999', fx.r_wallet::text, '-999')) from fx $$,
                 'SOL02', null, 'reusing a key with a different payload is rejected');

-- Zero-sum, per book -------------------------------------------------------------------------
select throws_ok($$ select app.post_journal('va_inflow', 'test:unbalanced:01',
                      pg_temp.entries(fx.clearing::text, '100', fx.r_wallet::text, '-99')) from fx $$,
                 'SOL06', null, 'an unbalanced journal is rejected');
select throws_ok($$ select app.post_journal('bogus_transfer', 'test:crossbook:01',
                      pg_temp.entries(fx.clearing::text, '100', fx.d_revenue::text, '-100')) from fx $$,
                 'SOL06', null, 'a journal balanced overall but not per book is rejected');
select throws_ok($$ select app.post_journal('va_inflow', 'test:single:0001',
                      pg_temp.entries(fx.clearing::text, '100')) from fx $$,
                 'SOL05', null, 'a single-entry journal is rejected');
select throws_ok($$ select app.post_journal('va_inflow', 'test:zero:00001',
                      pg_temp.entries(fx.clearing::text, '0', fx.r_wallet::text, '0')) from fx $$,
                 'SOL05', null, 'zero-amount entries are rejected');
select throws_ok($$ select app.post_journal('va_inflow', 'test:decimal:001',
                      pg_temp.entries(fx.clearing::text, '10.5', fx.r_wallet::text, '-10.5')) from fx $$,
                 '22P02', null, 'fractional kobo cannot be posted');

-- The deferred constraint trigger catches raw inserts that bypass post_journal
select throws_ok($$
  do $d$
  declare j uuid; f record;
  begin
    select * into f from pg_temp.fx;
    insert into public.journals (journal_type, idempotency_key, request_hash)
    values ('raw_test', 'test:raw:unbalanced', 'x') returning id into j;
    insert into public.ledger_entries (journal_id, account_id, book_org_id, amount_kobo)
    values (j, f.clearing, f.platform, 500), (j, f.r_wallet, f.platform, -400);
    set constraints all immediate;
  end $d$ $$, 'SOL06', null, 'raw unbalanced entries fail the zero-sum constraint at commit');
select throws_ok($$
  do $d$
  begin
    insert into public.journals (journal_type, idempotency_key, request_hash)
    values ('raw_test', 'test:raw:empty001', 'x');
    set constraints all immediate;
  end $d$ $$, 'SOL06', null, 'a journal with no entries fails at commit');

-- Impossible balances ------------------------------------------------------------------------
select throws_ok($$ select app.post_journal('settle_wallet', 'test:overdraft:1',
                      pg_temp.entries(fx.r_wallet::text, '20000000', fx.d_wallet::text, '-20000000',
                                      fx.d_funds::text, '20000000', fx.d_recv::text, '-20000000')) from fx $$,
                 '23514', null, 'spending more than the wallet holds violates account_balances_sign_rules');

-- Split payment: N30,000 invoice, N20,000 from wallet + N10,000 on trade credit, one journal, two books
select lives_ok($$ select app.post_journal('delivery_invoiced', 'test:invoice:0001',
                     pg_temp.entries(fx.d_recv::text, '3000000', fx.d_revenue::text, '-3000000')) from fx $$,
                'invoice posted: receivable N30,000');
select lives_ok($$ select app.post_journal('split_payment', 'test:split:00001',
                     pg_temp.entries(fx.r_wallet::text, '2000000', fx.d_wallet::text, '-2000000',
                                     fx.d_funds::text, '2000000', fx.d_recv::text, '-2000000',
                                     fx.d_credit::text, '1000000', fx.d_recv::text, '-1000000')) from fx $$,
                'split payment posts as one journal balanced in both books');
select results_eq(
  $$ select b.account_id, b.balance_kobo from public.v_account_balances b, fx
     where b.account_id in (fx.r_wallet, fx.d_recv, fx.d_credit, fx.d_funds) order by b.account_id $$,
  $$ select x.id, x.bal from fx, lateral (values (fx.r_wallet, 9750000::bigint), (fx.d_recv, 0::bigint),
                                                 (fx.d_credit, 1000000::bigint), (fx.d_funds, 2000000::bigint)) x(id, bal)
     order by x.id $$,
  'after split: wallet N97,500, receivable 0, credit drawn N10,000, partner funds N20,000');

-- Append-only + projection guard ---------------------------------------------------------------
select throws_ok($$ update public.ledger_entries set amount_kobo = amount_kobo * 2 $$, 'SOL06', null,
                 'ledger_entries: UPDATE rejected');
select throws_ok($$ delete from public.journals $$, 'SOL06', null, 'journals: DELETE rejected');
select throws_ok($$ update public.account_balances set balance_kobo = 0 $$, 'SOL06', null,
                 'account_balances: direct UPDATE rejected even for the table owner');

-- Account shape ------------------------------------------------------------------------------
select throws_ok($$ insert into public.accounts (book_org_id, book_kind, account_type, holder_org_id)
                    select fx.dist, 'distributor', 'wallet', fx.retailer from fx $$,
                 '23514', null, 'a wallet cannot live in a distributor book');

-- Rebuild from ledger -------------------------------------------------------------------------
select is_empty($$ select * from app.check_money_projection() $$,
                'account_balances rebuilt from ledger_entries matches the projection exactly');
select is_empty($$ select * from app.check_journals_balanced() $$,
                'every journal balances per book');

select * from finish();
rollback;
