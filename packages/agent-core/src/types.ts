// Offline agent model (hard rule 4). The device records EVENTS; the server decides. Platform-neutral:
// storage (SQLite on the phone, memory in tests) and transport (Supabase) are interfaces.

export type EventType = 'sale.recorded' | 'visit.checked_in';

export type SaleLine = { skuId: string; qtyPieces: number };

export type OutboxEvent = {
  eventId: string;          // client-generated UUID
  seq: number;              // per-device monotonic
  type: EventType;
  clientTs: string;         // ISO-8601 UTC (informational only)
  lat: number | null;
  lng: number | null;
  accuracyM: number | null;
  payload: Record<string, unknown>;
  status: 'pending' | 'accepted' | 'rejected';
  reason: string | null;    // rejection reason code from the server
  result: unknown;
};

export type ServerResult = {
  event_id: string;
  status: 'accepted' | 'duplicate' | 'rejected' | 'deferred';
  reason?: string;
  original_status?: 'accepted' | 'rejected';
  result?: unknown;
};

export type CarriedLine = { skuId: string; onHand: number };

export type FieldState = {
  orgId: string;
  shipment: { id: string; status: string; note: string | null } | null;
  carried: CarriedLine[];
  shops: { id: string; name: string; lat: number | null; lng: number | null }[];
  geofence: { radiusM: number; maxAccuracyM: number };
  fetchedAt: string;
};

export interface AgentStore {
  getMeta(key: string): Promise<string | null>;
  setMeta(key: string, value: string): Promise<void>;
  append(event: OutboxEvent): Promise<void>;
  pending(limit: number): Promise<OutboxEvent[]>;
  all(): Promise<OutboxEvent[]>;
  markResult(eventId: string, status: OutboxEvent['status'], reason: string | null, result: unknown): Promise<void>;
}

export interface AgentTransport {
  registerDevice(deviceId: string, orgId: string): Promise<number>;
  sync(deviceId: string, events: OutboxEvent[]): Promise<ServerResult[]>;
  fetchState(): Promise<FieldState>;
}

export class OfflineError extends Error {
  constructor(message = 'offline') {
    super(message);
    this.name = 'OfflineError';
  }
}

/** Human text for server rejection codes (shown on the device and in the manager's review queue). */
export const REJECTION_TEXT: Record<string, string> = {
  insufficient_carried_stock: 'More than the stock you were recorded as carrying. Your manager will review it.',
  outside_geofence: 'Recorded away from the shop (or GPS too weak). Your manager will review it.',
  shipment_closed: 'Your stock run was already closed.',
  unknown_retailer: 'Shop not recognised for your distributor.',
  price_mismatch: 'No price for that product.',
  not_owner: 'This event belongs to another device or agent.',
  invalid_payload: 'The event was malformed.',
};
