// Spec scenario, end to end on the real stack: an agent carries 50 pcs on the ledger, sells 60 in airplane
// mode (a handover of 10 was never recorded), syncs; the sale is rejected into review; the manager accepts it
// into variance; the shipment cannot close until the variance is resolved.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createRepository, createAdapterRepository } from '@solus/db';
import { AgentEngine, MemoryStore, OfflineError, createSupabaseTransport, minimalFromSupabase, type AgentTransport } from '@solus/agent-core';
import { signIn, signUpFresh, serviceClient } from '../support/supabase.ts';
import { connect, one, assertProjectionsMatchLedgers } from '../support/db.ts';

async function ids() {
  const c = await connect();
  try {
    return await one<{ lp: string; ikeja_branch: string; ikeja_south: string; ikeja_wh: string; sku: string; shop: string }>(c, `
      select (select id from public.organisations where slug = 'lagos-prime') as lp,
             (select id from public.branches where name = 'Ikeja') as ikeja_branch,
             (select id from public.territories where name = 'Ikeja South') as ikeja_south,
             (select id from public.warehouses where name = 'Ikeja Main') as ikeja_wh,
             (select id from public.skus where code = 'HOM-BLC-1L') as sku,
             (select id from public.organisations where slug = 'retailer-07') as shop`);
  } finally { await c.end(); }
}

/** Wraps the real transport with an airplane-mode switch. */
function switchable(inner: AgentTransport) {
  const t = { online: true } as { online: boolean } & AgentTransport;
  t.registerDevice = (d, o) => (t.online ? inner.registerDevice(d, o) : Promise.reject(new OfflineError()));
  t.sync = (d, e) => (t.online ? inner.sync(d, e) : Promise.reject(new OfflineError()));
  t.fetchState = () => (t.online ? inner.fetchState() : Promise.reject(new OfflineError()));
  return t;
}

test('offline sale beyond carried stock -> review -> accept into variance -> close blocked -> resolved', async () => {
  const f = await ids();
  // A fresh agent, approved into Ikeja South.
  const { db: agentDb } = await signUpFresh('offline-agent');
  const agent = createRepository(agentDb);
  await agent.registration.requestToJoin({ distributorId: f.lp, role: 'agent', fullName: `Offline Agent ${randomUUID().slice(0, 4)}`, phoneE164: '+2348099991234' });
  const bm = createRepository(await signIn('lp.bm.ikeja'));
  const wh = createRepository(await signIn('lp.wh.ikeja'));
  const reqs = await bm.approvals.pendingJoinRequests(f.lp);
  const mine = reqs.find((r) => r.profiles?.full_name?.startsWith('Offline Agent'));
  assert.ok(mine);
  await bm.approvals.decideJoinRequest({ requestId: mine.id, approve: true, branchId: f.ikeja_branch, territoryId: f.ikeja_south });

  // Ledger: 50 pcs handed over with OTP.
  const reqId = await agent.push.requestStock(f.ikeja_wh, [{ skuId: f.sku, uomCode: 'piece', uomQty: 50 }]);
  const shipmentId = await bm.push.decideStockRequest(reqId, true) as string;
  const challenge = await wh.push.startHandover(shipmentId);
  const { code } = await createAdapterRepository(serviceClient()).issueOtpCode(challenge);
  assert.equal((await wh.push.verifyOtp(challenge, code)).ok, true);

  // The phone: engine + switchable transport.
  const transport = switchable(createSupabaseTransport(minimalFromSupabase(agentDb), f.lp));
  const store = new MemoryStore();
  const engine = new AgentEngine({ store, transport, uuid: randomUUID });
  await engine.signIn(f.lp);
  await engine.sync();
  assert.equal((await engine.state())?.carried.find((c) => c.skuId === f.sku)?.onHand, 50);

  // Airplane mode: check in and sell 60 at the shop.
  transport.online = false;
  const fix = { lat: 6.5800, lng: 3.3480, accuracyM: 6 };
  await engine.checkIn(f.shop, fix);
  const { exceedsEstimate } = await engine.recordSale(f.shop, [{ skuId: f.sku, qtyPieces: 60 }], fix);
  assert.equal(exceedsEstimate, true);
  assert.equal((await engine.sync()).online, false);
  assert.equal((await store.pending(10)).length, 2, 'both events wait in the outbox');

  // Back online.
  transport.online = true;
  const r = await engine.sync();
  assert.deepEqual([r.accepted, r.rejected], [1, 1]);
  const sale = (await store.all()).find((e) => e.type === 'sale.recorded');
  assert.equal(sale?.reason, 'insufficient_carried_stock');
  assert.equal((await engine.sync()).sent, 0, 'nothing left to send; a rejected event is not resent');

  // Manager: accept into variance.
  const items = await bm.push.reviewItems(f.lp);
  const item = items.find((i) => i.event_id === sale?.eventId);
  assert.ok(item, 'the rejected sale is in the manager\'s review queue');
  assert.equal((await bm.push.acceptIntoVariance(item.id, 'agent carried 10 extra from a missed handover')).unrecorded_pieces, 10);

  await engine.sync();
  assert.equal((await engine.state())?.carried.find((c) => c.skuId === f.sku)?.onHand ?? 0, 0, 'all 60 sold; carried stock never went negative');

  // Return (nothing left) -> reconciling; close blocked; resolve -> closed.
  const ret = await wh.push.startReturn(shipmentId, []);
  const { code: code2 } = await createAdapterRepository(serviceClient()).issueOtpCode(ret);
  assert.equal((await wh.push.verifyOtp(ret, code2)).result, 'reconciling');
  await assert.rejects(bm.fulfilment.startReturn(shipmentId, []));   // wrong kind of return for a push run
  const [vc] = await bm.push.varianceCases({ shipmentIds: [shipmentId], status: 'pending' });
  assert.deepEqual([vc?.kind, vc?.qty_pieces], ['unrecorded_stock', 10]);
  assert.equal(await bm.push.resolveVariance(vc!.id, 'link_handover', 'found the missed handover slip'), 'closed');

  const c = await connect();
  try { await assertProjectionsMatchLedgers(c); } finally { await c.end(); }
});
