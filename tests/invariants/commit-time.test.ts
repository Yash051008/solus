// Invariants that only fire at COMMIT (deferred constraint triggers), proven with real commits,
// plus idempotent journal posting under concurrent duplicates (the DB half of "duplicate webhook").
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { connect, one, sqlstate, assertProjectionsMatchLedgers } from '../support/db.ts';

test('an unbalanced journal is rejected at COMMIT and leaves no trace', async () => {
  const c = await connect();
  try {
    const key = `test:commit:unbalanced:${randomUUID()}`;
    const fx = await one<{ clearing: string; wallet: string }>(
      c,
      `select (select id from public.accounts where account_type = 'provider_clearing') as clearing,
              (select a.id from public.accounts a join public.organisations o on o.id = a.holder_org_id
                where a.account_type = 'wallet' and o.slug = 'retailer-02') as wallet`,
    );
    await c.query('begin');
    const j = await one<{ id: string }>(
      c,
      `insert into public.journals (journal_type, idempotency_key, request_hash) values ('raw_test', $1, 'x') returning id`,
      [key],
    );
    await c.query(
      `insert into public.ledger_entries (journal_id, account_id, book_org_id, amount_kobo)
       select $1, a.id, a.book_org_id, v.amt from (values ($2::uuid, 700::bigint), ($3::uuid, -600::bigint)) v(acc, amt)
       join public.accounts a on a.id = v.acc`,
      [j.id, fx.clearing, fx.wallet],
    );
    await assert.rejects(c.query('commit'), (err) => sqlstate(err) === 'SOL06', 'COMMIT fails with SOL06');
    const left = await one<{ n: number }>(c, 'select count(*)::int as n from public.journals where idempotency_key = $1', [key]);
    assert.equal(left.n, 0, 'nothing from the failed journal persisted');
  } finally {
    await c.end();
  }
});

test('a one-legged handover is rejected at COMMIT', async () => {
  const c = await connect();
  try {
    const fx = await one<{ wh: string; sku: string }>(
      c,
      `select (select sl.id from public.stock_locations sl join public.warehouses w on w.id = sl.warehouse_id
                where w.name = 'Lekki Depot') as wh,
              (select id from public.skus where code = 'HOM-SOP-150G') as sku`,
    );
    const before = await one<{ on_hand: number }>(
      c, 'select on_hand from public.stock_balances where location_id = $1 and sku_id = $2', [fx.wh, fx.sku]);
    await c.query('begin');
    await c.query(`select app.post_stock_movement(gen_random_uuid(), 'handover', $1, $2, 5, -1)`, [fx.wh, fx.sku]);
    await assert.rejects(c.query('commit'), (err) => sqlstate(err) === 'SOL06', 'COMMIT fails with SOL06');
    const after = await one<{ on_hand: number }>(
      c, 'select on_hand from public.stock_balances where location_id = $1 and sku_id = $2', [fx.wh, fx.sku]);
    assert.equal(after.on_hand, before.on_hand, 'warehouse balance unchanged');
  } finally {
    await c.end();
  }
});

test('20 concurrent duplicates of one journal post exactly once', async () => {
  const key = `test:dup:${randomUUID()}`;
  const admin = await connect();
  const clients = await Promise.all(Array.from({ length: 20 }, () => connect()));
  try {
    const fx = await one<{ clearing: string; wallet: string; before: string }>(
      admin,
      `select (select id from public.accounts where account_type = 'provider_clearing') as clearing,
              a.id as wallet, b.balance_kobo::text as before
       from public.accounts a join public.organisations o on o.id = a.holder_org_id
       join public.account_balances b on b.account_id = a.id
       where a.account_type = 'wallet' and o.slug = 'retailer-04'`,
    );
    const entries = JSON.stringify([
      { account_id: fx.clearing, amount_kobo: '123456' },
      { account_id: fx.wallet, amount_kobo: '-123456' },
    ]);
    const ids = await Promise.all(
      clients.map(async (c) => {
        const r = await one<{ id: string }>(c, `select app.post_journal('va_inflow', $1, $2::jsonb) as id`, [key, entries]);
        return r.id;
      }),
    );
    assert.equal(new Set(ids).size, 1, 'every caller got the same journal id');

    const after = await one<{ journals: number; entries: number; balance: string }>(
      admin,
      `select (select count(*)::int from public.journals where idempotency_key = $1) as journals,
              (select count(*)::int from public.ledger_entries e join public.journals j on j.id = e.journal_id
                where j.idempotency_key = $1) as entries,
              (select balance_kobo::text from public.account_balances where account_id = $2) as balance`,
      [key, fx.wallet],
    );
    assert.equal(after.journals, 1, 'one journal');
    assert.equal(after.entries, 2, 'two entries');
    assert.equal(BigInt(after.balance), BigInt(fx.before) - 123456n, 'wallet credited exactly once');
  } finally {
    await Promise.all(clients.map((c) => c.end()));
    await admin.end();
  }
});

test('projections equal a rebuild from the ledgers after all tests', async () => {
  const c = await connect();
  try {
    await assertProjectionsMatchLedgers(c);
  } finally {
    await c.end();
  }
});
