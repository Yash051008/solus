// Final end-to-end test: the pull flow and the push flow drawing on the same SKU in the same warehouse, on
// the real stack, through the same repository/engine code the apps use. At the end the stock moved out
// of the warehouse equals what was delivered plus what the agent sold, and every projection and journal
// still matches its ledger.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createRepository, createAdapterRepository } from '@solus/db';
import { AgentEngine, MemoryStore, OfflineError, createSupabaseTransport, minimalFromSupabase, type AgentTransport } from '@solus/agent-core';
import { MockSmsProvider, MockVirtualAccountProvider, handlePaymentWebhook, sendOtp } from '@solus/integrations';
import { signIn, signUpFresh, serviceClient } from '../support/supabase.ts';
import { connect, one, assertProjectionsMatchLedgers } from '../support/db.ts';

type Fixture = {
  lp: string; ikeja_branch: string; ikeja_south: string; ikeja_wh: string; sku: string;
  shop: string; shop_lat: number; shop_lng: number; shop_va: string; shop_phone: string; rel: string;
};

async function fixture(): Promise<Fixture> {
  const c = await connect();
  try {
    return await one<Fixture>(c, `
      select (select id from public.organisations where slug = 'lagos-prime') as lp,
             (select id from public.branches where name = 'Ikeja') as ikeja_branch,
             (select id from public.territories where name = 'Ikeja South') as ikeja_south,
             (select id from public.warehouses where name = 'Ikeja Main') as ikeja_wh,
             (select id from public.skus where code = 'HOM-SOP-150G') as sku,
             o.id as shop, o.lat as shop_lat, o.lng as shop_lng,
             (select account_number from public.virtual_accounts where org_id = o.id) as shop_va,
             (select p.phone_e164 from public.profiles p join auth.users u on u.id = p.user_id where u.email = 'retailer07@solus.test') as shop_phone,
             (select id from public.customer_relationships where retailer_org_id = o.id
                and distributor_org_id = (select id from public.organisations where slug = 'lagos-prime')) as rel
      from public.v_organisations o where o.slug = 'retailer-07'`);
  } finally { await c.end(); }
}

async function warehouseOnHand(warehouseId: string, skuId: string): Promise<number> {
  const c = await connect();
  try {
    const r = await one<{ n: number }>(c, `select coalesce(sum(b.on_hand), 0)::int as n from public.stock_balances b
      join public.stock_locations l on l.id = b.location_id where l.warehouse_id = $1 and l.kind = 'warehouse' and b.sku_id = $2`, [warehouseId, skuId]);
    return r.n;
  } finally { await c.end(); }
}

function switchable(inner: AgentTransport) {
  const t = { online: true } as { online: boolean } & AgentTransport;
  t.registerDevice = (d, o) => (t.online ? inner.registerDevice(d, o) : Promise.reject(new OfflineError()));
  t.sync = (d, e) => (t.online ? inner.sync(d, e) : Promise.reject(new OfflineError()));
  t.fetchState = () => (t.online ? inner.fetchState() : Promise.reject(new OfflineError()));
  return t;
}

test('pull and push on the same stock: order → e-POD → wallet + credit OTP; request → OTP handover → offline sync → variance → return', async () => {
  const f = await fixture();
  const adapter = createAdapterRepository(serviceClient());
  const wh = createRepository(await signIn('lp.wh.ikeja'));
  const bm = createRepository(await signIn('lp.bm.ikeja'));
  const admin = createRepository(await signIn('lp.admin'));
  const shop = createRepository(await signIn('retailer07'));

  // Fresh stock so the test never depends on earlier runs: 300 pcs received through the ledger.
  await wh.stock.recordReceipt(f.ikeja_wh, `E2E-${randomUUID().slice(0, 8)}`, [{ skuId: f.sku, uomCode: 'piece', uomQty: 300 }], `e2e:receipt:${randomUUID()}`);
  const start = await warehouseOnHand(f.ikeja_wh, f.sku);

  // A fresh driver (one open run per carrier, so the test can be re-run against the same database).
  const { db: driverDb } = await signUpFresh('e2e-driver');
  const driver = createRepository(driverDb);
  await driver.registration.requestToJoin({ distributorId: f.lp, role: 'driver', fullName: `E2E Driver ${randomUUID().slice(0, 4)}`, phoneE164: '+2348099994321' });
  const driverJoin = (await bm.approvals.pendingJoinRequests(f.lp)).find((r) => r.profiles?.full_name?.startsWith('E2E Driver'));
  assert.ok(driverJoin);
  await bm.approvals.decideJoinRequest({ requestId: driverJoin.id, approve: true, branchId: f.ikeja_branch });
  const driverId = (await driverDb.auth.getUser()).data.user!.id;

  // ---------------------------------------------------------------- pull: order → batch → driver → e-POD
  const placed = await shop.orders.place({ distributorId: f.lp, retailerOrgId: f.shop, lines: [{ skuId: f.sku, uomCode: 'piece', uomQty: 30 }], idempotencyKey: `e2e:order:${randomUUID()}` });
  assert.equal(placed.status, 'reserved', `order reserved (routing: ${placed.routing_reason})`);
  const allocs = await wh.orders.allocations({ orderIds: [placed.order_id] });
  assert.deepEqual(allocs.map((a) => a.warehouse_id), [f.ikeja_wh], 'routed to the nearest stocked warehouse');

  const batchId = await wh.fulfilment.createBatch(f.ikeja_wh, [placed.order_id]) as string;
  await wh.fulfilment.markPacked(batchId);
  const shipmentId = await wh.fulfilment.dispatch(batchId, driverId) as string;
  await driver.fulfilment.accept(shipmentId);

  const photoPath = `${shipmentId}/${placed.order_id}/${randomUUID()}.png`;
  const png = Uint8Array.from(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==', 'base64'));
  await driver.fulfilment.uploadEpod(photoPath, new Blob([png], { type: 'image/png' }), 'image/png');
  const pod = await driver.fulfilment.recordDelivery({
    shipmentId, orderId: placed.order_id,
    lines: allocs.map((a) => ({ allocationId: a.id, delivered: a.qty_pieces, refused: 0, damaged: 0, missing: 0 })),
    lat: f.shop_lat, lng: f.shop_lng, accuracyM: 8, photoPath, recipientName: 'Shop Owner 07', idempotencyKey: `e2e:pod:${randomUUID()}`,
  });
  assert.equal(pod.geofence_ok, true);
  await wh.fulfilment.startReturn(shipmentId, []);
  assert.equal(await driver.fulfilment.confirmReturn(shipmentId), 'closed', 'nothing left on the van: the run closes');

  // ---------------------------------------------------------------- pay: half from wallet (topped up by webhook), half on credit with SMS OTP
  const due = BigInt(await shop.finance.amountDue(placed.order_id));
  assert.ok(due > 0n);
  const walletPart = due / 2n;
  const creditPart = due - walletPart;
  const provider = new MockVirtualAccountProvider('e2e-webhook-secret-0001');
  const topup = provider.simulateTransfer({ accountNumber: f.shop_va, amountKobo: walletPart, reference: `E2E TOPUP ${randomUUID()}` });
  assert.equal((await handlePaymentWebhook({ provider, record: adapter.recordProviderEvent }, topup.rawBody, topup.headers)).result, 'posted');
  assert.equal((await handlePaymentWebhook({ provider, record: adapter.recordProviderEvent }, topup.rawBody, topup.headers)).result, 'duplicate');

  await admin.finance.setCreditLimit(f.rel, 100_000_000n);
  const pay = await shop.finance.startPayment(placed.order_id, walletPart, creditPart, `e2e:pay:${randomUUID()}`);
  assert.equal(pay.status, 'pending_otp');
  await sendOtp({ issue: adapter.issueOtpCode, sms: new MockSmsProvider() }, pay.challenge_id!);
  const code = /\b(\d{6})\b/.exec(MockSmsProvider.inboxFor(f.shop_phone, 1)[0]?.body ?? '')?.[1];
  assert.ok(code);
  const wrong = await shop.push.verifyOtp(pay.challenge_id!, code === '000000' ? '111111' : '000000');
  assert.equal(wrong.ok, false, 'a wrong code is refused and nothing is charged');
  assert.equal((await shop.push.verifyOtp(pay.challenge_id!, code)).result, 'settled');
  assert.equal(Number(await shop.finance.amountDue(placed.order_id)), 0, 'order fully paid');

  // ---------------------------------------------------------------- push: fresh agent → request → approve → OTP handover
  const { db: agentDb } = await signUpFresh('e2e-agent');
  const agent = createRepository(agentDb);
  await agent.registration.requestToJoin({ distributorId: f.lp, role: 'agent', fullName: `E2E Agent ${randomUUID().slice(0, 4)}`, phoneE164: '+2348099995678' });
  const join = (await bm.approvals.pendingJoinRequests(f.lp)).find((r) => r.profiles?.full_name?.startsWith('E2E Agent'));
  assert.ok(join);
  await bm.approvals.decideJoinRequest({ requestId: join.id, approve: true, branchId: f.ikeja_branch, territoryId: f.ikeja_south });

  const reqId = await agent.push.requestStock(f.ikeja_wh, [{ skuId: f.sku, uomCode: 'piece', uomQty: 40 }]);
  const run = await bm.push.decideStockRequest(reqId, true) as string;
  const handover = await wh.push.startHandover(run);
  const { code: hcode } = await adapter.issueOtpCode(handover);
  assert.equal((await wh.push.verifyOtp(handover, hcode)).ok, true);

  // ---------------------------------------------------------------- offline: sell 10 (fits) and 45 (does not); sync; replay
  const inner = createSupabaseTransport(minimalFromSupabase(agentDb), f.lp);
  const transport = switchable(inner);
  const store = new MemoryStore();
  const engine = new AgentEngine({ store, transport, uuid: randomUUID });
  await engine.signIn(f.lp);
  await engine.sync();
  transport.online = false;
  const fix = { lat: f.shop_lat, lng: f.shop_lng, accuracyM: 6 };
  await engine.recordSale(f.shop, [{ skuId: f.sku, qtyPieces: 10 }], fix);
  await engine.recordSale(f.shop, [{ skuId: f.sku, qtyPieces: 45 }], fix);
  transport.online = true;
  const synced = await engine.sync();
  assert.deepEqual([synced.accepted, synced.rejected], [1, 1]);

  const events = await store.all();
  const replay = await inner.sync(await engine.deviceId(), events);
  assert.deepEqual(replay.map((r) => r.status), ['duplicate', 'duplicate'], 'a resent batch changes nothing');

  // ---------------------------------------------------------------- manager: accept into variance; return; resolve
  const rejected = events.find((e) => e.reason === 'insufficient_carried_stock');
  const item = (await bm.push.reviewItems(f.lp)).find((i) => i.event_id === rejected?.eventId);
  assert.ok(item, 'the rejected sale waits in review, never dropped');
  assert.equal((await bm.push.acceptIntoVariance(item.id, 'e2e: agent had 15 from an unrecorded top-up')).unrecorded_pieces, 15);

  const ret = await wh.push.startReturn(run, []);
  const { code: rcode } = await adapter.issueOtpCode(ret);
  assert.equal((await wh.push.verifyOtp(ret, rcode)).result, 'reconciling', 'a pending variance blocks the close');
  const [vc] = await bm.push.varianceCases({ shipmentIds: [run], status: 'pending' });
  assert.ok(vc);
  assert.equal(await bm.push.resolveVariance(vc.id, 'link_handover', 'e2e: handover slip found'), 'closed');

  // ---------------------------------------------------------------- invariants
  // Out of the warehouse: 30 delivered + 40 handed over + 15 from linking the missed handover.
  assert.equal(await warehouseOnHand(f.ikeja_wh, f.sku), start - 30 - 40 - 15);
  const c = await connect();
  try {
    await assertProjectionsMatchLedgers(c);
    const neg = await one<{ n: number }>(c, `select count(*)::int as n from public.stock_balances where on_hand < 0 or reserved < 0 or reserved > on_hand`);
    assert.equal(neg.n, 0);
    const carried = await one<{ n: number }>(c, `select coalesce(sum(b.on_hand), 0)::int as n from public.stock_balances b
      join public.shipments s on s.carrier_location_id = b.location_id where s.id = any($1::uuid[]) and b.sku_id = $2`, [[shipmentId, run], f.sku]);
    assert.equal(carried.n, 0, 'nothing left with the driver or the agent');
  } finally { await c.end(); }
});
