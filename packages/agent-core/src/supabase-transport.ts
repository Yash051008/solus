// Transport over the repository's DbClient (supabase-js). Network failures become OfflineError so the
// engine keeps events queued; server rejections are per-event results, never thrown.
import type { AgentTransport, FieldState, OutboxEvent, ServerResult } from './types.ts';
import { OfflineError } from './types.ts';

type Rpc = (fn: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string; code?: string } | null }>;
type Select = (table: string, columns: string, filters: Record<string, string | string[]>) => Promise<{ data: unknown[] | null; error: { message: string } | null }>;

export type MinimalClient = { rpc: Rpc; select: Select; userId: () => Promise<string | null> };

function isNetwork(message: string): boolean {
  return /fetch|network|timed? ?out|abort|ECONNREFUSED|Failed to fetch|Network request failed/i.test(message);
}

async function call<T>(p: Promise<{ data: unknown; error: { message: string; code?: string } | null }>): Promise<T> {
  let res;
  try {
    res = await p;
  } catch (err) {
    throw new OfflineError(err instanceof Error ? err.message : 'offline');
  }
  if (res.error) {
    if (isNetwork(res.error.message)) throw new OfflineError(res.error.message);
    throw new Error(res.error.message);
  }
  return res.data as T;
}

export function toWire(e: OutboxEvent) {
  return { event_id: e.eventId, seq: e.seq, type: e.type, client_ts: e.clientTs, lat: e.lat, lng: e.lng, accuracy_m: e.accuracyM, payload: e.payload };
}

export function createSupabaseTransport(client: MinimalClient, orgId: string): AgentTransport {
  return {
    registerDevice: (deviceId, org) => call<number>(client.rpc('register_device', { p_device_id: deviceId, p_org_id: org })),
    sync: (deviceId, events) => call<ServerResult[]>(client.rpc('sync_agent_events', { p_device_id: deviceId, p_events: events.map(toWire) })),
    async fetchState(): Promise<FieldState> {
      const userId = await client.userId();
      if (!userId) throw new Error('not signed in');
      const locs = await call<{ id: string }[]>(client.select('stock_locations', 'id', { user_id: userId, kind: 'agent', org_id: orgId }));
      const loc = locs[0]?.id;
      const ships = loc ? await call<{ id: string; status: string; status_note: string | null; kind: string }[]>(
        client.select('shipments', 'id, status, status_note, kind', { carrier_location_id: loc, kind: 'push', status: ['awaiting_acceptance', 'open', 'returning', 'reconciling'] })) : [];
      const balances = loc ? await call<{ sku_id: string; on_hand: number }[]>(client.select('stock_balances', 'sku_id, on_hand', { location_id: loc })) : [];
      const shops = await call<{ id: string; name: string; lat: number | null; lng: number | null; status: string }[]>(
        client.select('v_organisations', 'id, name, lat, lng, status', { kind: 'retailer', status: 'active' }));
      const org = await call<{ geofence_radius_m: number | null; geofence_max_accuracy_m: number | null }[]>(
        client.select('v_organisations', 'geofence_radius_m, geofence_max_accuracy_m', { id: orgId }));
      const ship = ships[0];
      return {
        orgId,
        shipment: ship ? { id: ship.id, status: ship.status, note: ship.status_note } : null,
        carried: balances.filter((b) => b.on_hand > 0).map((b) => ({ skuId: b.sku_id, onHand: b.on_hand })),
        shops: shops.map((s) => ({ id: s.id, name: s.name, lat: s.lat, lng: s.lng })),
        geofence: { radiusM: org[0]?.geofence_radius_m ?? 150, maxAccuracyM: org[0]?.geofence_max_accuracy_m ?? 50 },
        fetchedAt: new Date().toISOString(),
      };
    },
  };
}

type Builder = PromiseLike<{ data: unknown[] | null; error: { message: string } | null }> & {
  eq(column: string, value: string): Builder;
  in(column: string, values: string[]): Builder;
};
type SupabaseLike = {
  schema(name: 'app'): { rpc(fn: string, args: Record<string, unknown>): PromiseLike<{ data: unknown; error: { message: string; code?: string } | null }> };
  from(table: string): { select(columns: string): Builder };
  auth: { getUser(): Promise<{ data: { user: { id: string } | null } }> };
};

/** Adapts a supabase-js client (web, Node or React Native) to the transport's minimal surface. */
export function minimalFromSupabase(client: unknown): MinimalClient {
  const sb = client as SupabaseLike;
  return {
    rpc: async (fn, args) => sb.schema('app').rpc(fn, args),
    select: async (table, columns, filters) => {
      let q = sb.from(table).select(columns);
      for (const [k, v] of Object.entries(filters)) q = Array.isArray(v) ? q.in(k, v) : q.eq(k, v);
      return q;
    },
    userId: async () => (await sb.auth.getUser()).data.user?.id ?? null,
  };
}
