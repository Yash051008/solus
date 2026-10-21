// Hard rule 3: 50 truly parallel transactions each reserve 1 piece of a SKU with only 10 in stock.
// Expected: exactly 10 succeed, 40 fail cleanly with insufficient_stock (SOL01), zero oversell.
//
// "Truly parallel" is proven, not assumed: every worker opens its transaction and blocks on a shared
// advisory lock held by the coordinator. The test asserts all 50 are waiting simultaneously
// (pg_locks), then releases them at once.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import type pg from 'pg';
import { connect, one, sqlstate, waitFor, assertProjectionsMatchLedgers } from '../support/db.ts';

const WORKERS = 50;
const STOCK = 10;
const GATE_KEY = 424242;

type Outcome = { ok: true } | { ok: false; code: string };

test(`${WORKERS} concurrent orders vs ${STOCK} units: exactly ${STOCK} reserved, zero oversell`, async () => {
  const admin = await connect();
  const workers: pg.Client[] = [];
  try {
    // Fixture: a brand-new SKU with exactly 10 pieces at Ikeja Main, and 50 one-piece orders.
    const code = `CONC-${randomUUID().slice(0, 8).toUpperCase()}`;
    const fx = await one<{ sku_id: string; location_id: string; warehouse_id: string }>(
      admin,
      `with sku as (
         insert into public.skus (manufacturer_org_id, brand_id, code, name)
         select b.manufacturer_org_id, b.id, $1, 'Concurrency test SKU'
         from public.brands b join public.organisations m on m.id = b.manufacturer_org_id
         where m.slug = 'sunrise' and b.name = 'Sunrise Noodles'
         returning id
       )
       select sku.id as sku_id, sl.id as location_id, w.id as warehouse_id
       from sku, public.stock_locations sl join public.warehouses w on w.id = sl.warehouse_id
       where w.name = 'Ikeja Main'`,
      [code],
    );
    await admin.query(
      `select app.post_stock_movement(gen_random_uuid(), 'receipt', $1, $2, $3, null, null, null, 'concurrency fixture')`,
      [fx.location_id, fx.sku_id, STOCK],
    );
    const orders = await admin.query<{ id: string }>(
      `with o as (
         insert into public.orders (distributor_org_id, retailer_org_id)
         select cr.distributor_org_id, cr.retailer_org_id
         from public.customer_relationships cr
         join public.organisations r on r.id = cr.retailer_org_id,
         generate_series(1, $1)
         where r.slug = 'retailer-01'
         returning id
       ), l as (
         insert into public.order_lines (order_id, sku_id, uom_code, uom_qty, uom_price_kobo)
         select o.id, $2, 'piece', 1, 25000 from o
         returning order_id
       )
       select order_id as id from l`,
      [WORKERS, fx.sku_id],
    );
    assert.equal(orders.rowCount, WORKERS);

    // Gate: the coordinator holds the exclusive lock; workers queue behind it inside open transactions.
    await admin.query('select pg_advisory_lock($1)', [GATE_KEY]);
    for (let i = 0; i < WORKERS; i++) workers.push(await connect());

    const runs = workers.map(async (client, i): Promise<Outcome> => {
      const orderId = orders.rows[i]?.id;
      try {
        await client.query('begin');
        await client.query('select pg_advisory_xact_lock_shared($1)', [GATE_KEY]);
        await client.query('select app.reserve_order($1, $2)', [orderId, fx.warehouse_id]);
        await client.query('commit');
        return { ok: true };
      } catch (err) {
        await client.query('rollback');
        return { ok: false, code: sqlstate(err) };
      }
    });

    await waitFor(
      async () => {
        const r = await one<{ n: number }>(
          admin,
          `select count(*)::int as n from pg_locks
           where locktype = 'advisory' and objid = $1 and not granted`,
          [GATE_KEY],
        );
        return r.n === WORKERS;
      },
      15_000,
      `${WORKERS} transactions blocked on the gate`,
    );
    await admin.query('select pg_advisory_unlock($1)', [GATE_KEY]);

    const outcomes = await Promise.all(runs);
    const succeeded = outcomes.filter((o) => o.ok).length;
    const failureCodes = outcomes.flatMap((o) => (o.ok ? [] : [o.code]));

    assert.equal(succeeded, STOCK, 'exactly 10 reservations succeed');
    assert.equal(failureCodes.length, WORKERS - STOCK, 'exactly 40 reservations fail');
    assert.deepEqual([...new Set(failureCodes)], ['SOL01'], 'every failure is a clean insufficient_stock');

    const bal = await one<{ on_hand: number; reserved: number; available: number }>(
      admin,
      'select on_hand, reserved, available from public.stock_balances where location_id = $1 and sku_id = $2',
      [fx.location_id, fx.sku_id],
    );
    assert.deepEqual(bal, { on_hand: STOCK, reserved: STOCK, available: 0 }, 'zero oversell in the projection');

    const ledger = await one<{ reserved: number; movements: number; orders: number }>(
      admin,
      `select (select coalesce(sum(reserved_delta), 0)::int from public.stock_movements where sku_id = $1) as reserved,
              (select count(*)::int from public.stock_movements where sku_id = $1 and movement_type = 'reserve') as movements,
              (select count(*)::int from public.orders o join public.order_lines l on l.order_id = o.id
                where l.sku_id = $1 and o.status = 'reserved') as orders`,
      [fx.sku_id],
    );
    assert.deepEqual(ledger, { reserved: STOCK, movements: STOCK, orders: STOCK }, 'ledger agrees: 10 reserve rows');

    await assertProjectionsMatchLedgers(admin);
  } finally {
    await Promise.all(workers.map((c) => c.end()));
    await admin.end();
  }
});
