import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { AgentEngine, MemoryStore, OfflineError, type AgentTransport, type FieldState, type OutboxEvent, type ServerResult } from '../src/index.ts';

/** A tiny stand-in for the server's sync rules: dedupe by event_id, strict seq, carried-stock check. */
class FakeServer implements AgentTransport {
  online = true;
  dropNextResponse = false;
  carried = new Map([['sku-a', 50]]);
  lastSeq = 0;
  seen = new Map<string, ServerResult>();
  applied = 0;

  async registerDevice() { if (!this.online) throw new OfflineError(); return this.lastSeq; }
  async sync(_device: string, events: OutboxEvent[]): Promise<ServerResult[]> {
    if (!this.online) throw new OfflineError();
    const out: ServerResult[] = [];
    for (const e of [...events].sort((a, b) => a.seq - b.seq)) {
      const prior = this.seen.get(e.eventId);
      if (prior) { out.push({ event_id: e.eventId, status: 'duplicate', original_status: prior.status as 'accepted' | 'rejected', ...(prior.reason ? { reason: prior.reason } : {}) }); continue; }
      if (e.seq !== this.lastSeq + 1) { out.push({ event_id: e.eventId, status: 'deferred', reason: 'seq_gap' }); continue; }
      let r: ServerResult = { event_id: e.eventId, status: 'accepted' };
      if (e.type === 'sale.recorded') {
        const lines = e.payload['lines'] as { sku_id: string; qty_pieces: number }[];
        if (lines.some((l) => l.qty_pieces > (this.carried.get(l.sku_id) ?? 0))) r = { event_id: e.eventId, status: 'rejected', reason: 'insufficient_carried_stock' };
        else { for (const l of lines) this.carried.set(l.sku_id, (this.carried.get(l.sku_id) ?? 0) - l.qty_pieces); this.applied += 1; }
      }
      this.seen.set(e.eventId, r);
      this.lastSeq = e.seq;
      out.push(r);
    }
    if (this.dropNextResponse) { this.dropNextResponse = false; throw new OfflineError('response lost'); }
    return out;
  }
  async fetchState(): Promise<FieldState> {
    if (!this.online) throw new OfflineError();
    return { orgId: 'org-1', shipment: { id: 'ship-1', status: 'open', note: null },
             carried: [...this.carried].map(([skuId, onHand]) => ({ skuId, onHand })),
             shops: [{ id: 'shop-1', name: 'Shop', lat: 6.62, lng: 3.345 }], geofence: { radiusM: 150, maxAccuracyM: 50 },
             fetchedAt: new Date().toISOString() };
  }
}

async function setup() {
  const server = new FakeServer();
  const store = new MemoryStore();
  const engine = new AgentEngine({ store, transport: server, uuid: randomUUID });
  await engine.signIn('org-1');
  await engine.sync();
  return { server, store, engine };
}

test('airplane mode: sales queue locally with rising seq; estimated stock drops; nothing is lost', async () => {
  const { server, store, engine } = await setup();
  server.online = false;
  await engine.recordSale('shop-1', [{ skuId: 'sku-a', qtyPieces: 20 }], { lat: 6.62, lng: 3.345, accuracyM: 5 });
  await engine.recordSale('shop-1', [{ skuId: 'sku-a', qtyPieces: 5 }], null);
  const r = await engine.sync();
  assert.equal(r.online, false);
  assert.deepEqual((await store.all()).map((e) => [e.seq, e.status]), [[1, 'pending'], [2, 'pending']]);
  assert.equal((await engine.estimatedCarried()).get('sku-a'), 25);

  server.online = true;
  const back = await engine.sync();
  assert.deepEqual([back.accepted, back.rejected], [2, 0]);
  assert.equal((await engine.state())?.carried[0]?.onHand, 25, 'state refreshed from the server');
});

test('a lost response is harmless: the resend comes back as duplicates and nothing applies twice', async () => {
  const { server, store, engine } = await setup();
  await engine.recordSale('shop-1', [{ skuId: 'sku-a', qtyPieces: 10 }], null);
  server.dropNextResponse = true;
  assert.equal((await engine.sync()).online, false);
  assert.equal((await store.all())[0]?.status, 'pending', 'the device does not know it was applied');
  await engine.sync();
  assert.equal((await store.all())[0]?.status, 'accepted');
  assert.equal(server.applied, 1, 'applied exactly once');
});

test('a real sale beyond carried stock is recorded, flagged, then rejected into review (never dropped)', async () => {
  const { store, engine } = await setup();
  const { exceedsEstimate } = await engine.recordSale('shop-1', [{ skuId: 'sku-a', qtyPieces: 60 }], null);
  assert.equal(exceedsEstimate, true);
  const r = await engine.sync();
  assert.equal(r.rejected, 1);
  const [e] = await store.all();
  assert.deepEqual([e?.status, e?.reason], ['rejected', 'insufficient_carried_stock']);
});

test('if the server defers everything, sync stops instead of looping', async () => {
  const { server, engine } = await setup();
  await engine.recordSale('shop-1', [{ skuId: 'sku-a', qtyPieces: 1 }], null);
  server.lastSeq = 5;   // pretend the server expects a later seq (e.g. reinstall); events stay pending
  const r = await engine.sync();
  assert.deepEqual([r.accepted, r.deferred], [0, 1]);
});

test('advisory geofence uses the cached shop location', async () => {
  const { engine } = await setup();
  assert.equal((await engine.geofenceHint('shop-1', { lat: 6.62, lng: 3.345, accuracyM: 8 }))?.ok, true);
  assert.equal((await engine.geofenceHint('shop-1', { lat: 6.63, lng: 3.345, accuracyM: 8 }))?.reason, 'outside_radius');
});
