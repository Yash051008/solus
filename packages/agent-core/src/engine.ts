// The agent engine: append-only outbox with per-device seq, idempotent sync, cached server state.
// Local checks are ADVISORY (instant feedback); the server validates every event authoritatively.
import { advisoryGeofence } from '@solus/core';
import type { AgentStore, AgentTransport, FieldState, OutboxEvent, SaleLine, ServerResult } from './types.ts';
import { OfflineError } from './types.ts';

export type Fix = { lat: number; lng: number; accuracyM: number | null };

export type EngineDeps = {
  store: AgentStore;
  transport: AgentTransport;
  uuid: () => string;
  now?: () => Date;
};

const BATCH = 50;

export class AgentEngine {
  private readonly store: AgentStore;
  private readonly transport: AgentTransport;
  private readonly uuid: () => string;
  private readonly now: () => Date;

  constructor(deps: EngineDeps) {
    this.store = deps.store;
    this.transport = deps.transport;
    this.uuid = deps.uuid;
    this.now = deps.now ?? (() => new Date());
  }

  async deviceId(): Promise<string> {
    let id = await this.store.getMeta('device_id');
    if (!id) {
      id = this.uuid();
      await this.store.setMeta('device_id', id);
    }
    return id;
  }

  async state(): Promise<FieldState | null> {
    const raw = await this.store.getMeta('state');
    return raw ? (JSON.parse(raw) as FieldState) : null;
  }

  /** Server-carried stock minus local sales not yet accepted: what the agent should still physically hold. */
  async estimatedCarried(): Promise<Map<string, number>> {
    const state = await this.state();
    const est = new Map((state?.carried ?? []).map((c) => [c.skuId, c.onHand]));
    for (const e of await this.store.all()) {
      if (e.status !== 'pending' || e.type !== 'sale.recorded') continue;
      for (const l of (e.payload['lines'] as { sku_id: string; qty_pieces: number }[])) {
        est.set(l.sku_id, (est.get(l.sku_id) ?? 0) - l.qty_pieces);
      }
    }
    return est;
  }

  private async nextSeq(): Promise<number> {
    const seq = Number((await this.store.getMeta('last_seq')) ?? '0') + 1;
    await this.store.setMeta('last_seq', String(seq));
    return seq;
  }

  private async append(type: OutboxEvent['type'], fix: Fix | null, payload: Record<string, unknown>): Promise<OutboxEvent> {
    const event: OutboxEvent = {
      eventId: this.uuid(), seq: await this.nextSeq(), type, clientTs: this.now().toISOString(),
      lat: fix?.lat ?? null, lng: fix?.lng ?? null, accuracyM: fix?.accuracyM ?? null,
      payload, status: 'pending', reason: null, result: null,
    };
    await this.store.append(event);
    return event;
  }

  /** Advisory geofence for the UI (the server repeats the check). */
  async geofenceHint(shopId: string, fix: Fix) {
    const state = await this.state();
    const shop = state?.shops.find((s) => s.id === shopId);
    if (!shop || shop.lat === null || shop.lng === null || !state) return null;
    return advisoryGeofence({ shop: { lat: shop.lat, lng: shop.lng }, fix, accuracyM: fix.accuracyM,
                              radiusM: state.geofence.radiusM, maxAccuracyM: state.geofence.maxAccuracyM });
  }

  /** Records a cash sale offline. Never refuses a real sale: an excess over estimated stock is flagged, and the
   *  server routes it to the manager (accept into variance) instead of the device dropping it. */
  async recordSale(shopId: string, lines: SaleLine[], fix: Fix | null): Promise<{ event: OutboxEvent; exceedsEstimate: boolean }> {
    const state = await this.state();
    if (!state?.shipment) throw new Error('No open stock run. Sync first.');
    const clean = lines.filter((l) => Number.isSafeInteger(l.qtyPieces) && l.qtyPieces > 0);
    if (clean.length === 0) throw new RangeError('Enter at least one quantity.');
    const est = await this.estimatedCarried();
    const exceedsEstimate = clean.some((l) => l.qtyPieces > (est.get(l.skuId) ?? 0));
    const event = await this.append('sale.recorded', fix, {
      shipment_id: state.shipment.id, retailer_id: shopId,
      lines: clean.map((l) => ({ sku_id: l.skuId, qty_pieces: l.qtyPieces })),
    });
    return { event, exceedsEstimate };
  }

  async checkIn(shopId: string, fix: Fix | null): Promise<OutboxEvent> {
    return this.append('visit.checked_in', fix, { retailer_id: shopId });
  }

  /** Push the outbox (in seq order, batched), apply results, then refresh state. Safe to call repeatedly:
   *  a lost response just means the next sync gets 'duplicate' results for the same events. */
  async sync(): Promise<{ sent: number; accepted: number; rejected: number; deferred: number; online: boolean }> {
    const counts = { sent: 0, accepted: 0, rejected: 0, deferred: 0, online: true };
    try {
      const deviceId = await this.deviceId();
      const state = await this.state();
      const orgId = state?.orgId ?? (await this.store.getMeta('org_id'));
      if (!orgId) throw new Error('not signed in to a distributor');
      if ((await this.store.getMeta('registered')) !== 'yes') {
        await this.transport.registerDevice(deviceId, orgId);
        await this.store.setMeta('registered', 'yes');
      }
      for (;;) {
        const batch = await this.store.pending(BATCH);
        if (batch.length === 0) break;
        const results = await this.transport.sync(deviceId, batch);
        counts.sent += batch.length;
        const progressed = await this.apply(results, counts);
        if (!progressed) break;   // everything deferred: wait for the missing event
      }
      const fresh = await this.transport.fetchState();
      await this.store.setMeta('state', JSON.stringify(fresh));
      await this.store.setMeta('last_sync', this.now().toISOString());
    } catch (err) {
      if (err instanceof OfflineError) {
        counts.online = false;
        return counts;
      }
      throw err;
    }
    return counts;
  }

  private async apply(results: ServerResult[], counts: { accepted: number; rejected: number; deferred: number }): Promise<boolean> {
    let progressed = false;
    for (const r of results) {
      const status = r.status === 'duplicate' ? r.original_status : r.status;
      if (status === 'accepted') {
        await this.store.markResult(r.event_id, 'accepted', null, r.result ?? null);
        counts.accepted += 1;
        progressed = true;
      } else if (status === 'rejected') {
        await this.store.markResult(r.event_id, 'rejected', r.reason ?? 'rejected', null);
        counts.rejected += 1;
        progressed = true;
      } else {
        counts.deferred += 1;
      }
    }
    return progressed;
  }

  async signIn(orgId: string): Promise<void> {
    await this.store.setMeta('org_id', orgId);
  }
}
