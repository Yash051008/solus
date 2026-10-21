// In-memory AgentStore for tests (the phone uses the SQLite store in apps/agent).
import type { AgentStore, OutboxEvent } from './types.ts';

export class MemoryStore implements AgentStore {
  private readonly meta = new Map<string, string>();
  private readonly events: OutboxEvent[] = [];

  async getMeta(key: string) { return this.meta.get(key) ?? null; }
  async setMeta(key: string, value: string) { this.meta.set(key, value); }
  async append(event: OutboxEvent) { this.events.push({ ...event }); }
  async pending(limit: number) {
    return this.events.filter((e) => e.status === 'pending').sort((a, b) => a.seq - b.seq).slice(0, limit).map((e) => ({ ...e }));
  }
  async all() { return this.events.map((e) => ({ ...e })).sort((a, b) => a.seq - b.seq); }
  async markResult(eventId: string, status: OutboxEvent['status'], reason: string | null, result: unknown) {
    const e = this.events.find((x) => x.eventId === eventId);
    if (e) Object.assign(e, { status, reason, result });
  }
}
