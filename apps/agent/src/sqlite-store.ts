// AgentStore on the phone's SQLite (expo-sqlite). The outbox is append-only from the app's point of view:
// rows are only ever marked with the server's result, never edited or deleted.
import * as SQLite from 'expo-sqlite';
import type { AgentStore, OutboxEvent } from '@solus/agent-core';

type Row = {
  event_id: string; seq: number; type: OutboxEvent['type']; client_ts: string; lat: number | null; lng: number | null;
  accuracy_m: number | null; payload: string; status: OutboxEvent['status']; reason: string | null; result: string | null;
};

const toEvent = (r: Row): OutboxEvent => ({
  eventId: r.event_id, seq: r.seq, type: r.type, clientTs: r.client_ts, lat: r.lat, lng: r.lng, accuracyM: r.accuracy_m,
  payload: JSON.parse(r.payload) as Record<string, unknown>, status: r.status, reason: r.reason,
  result: r.result ? (JSON.parse(r.result) as unknown) : null,
});

export function openStore(name = 'solus-field.db'): AgentStore {
  const db = SQLite.openDatabaseSync(name);
  db.execSync(`
    pragma journal_mode = wal;
    create table if not exists meta (key text primary key not null, value text not null);
    create table if not exists outbox (
      event_id text primary key not null, seq integer not null unique, type text not null, client_ts text not null,
      lat real, lng real, accuracy_m real, payload text not null,
      status text not null default 'pending', reason text, result text
    );
  `);
  return {
    async getMeta(key) {
      return db.getFirstSync<{ value: string }>('select value from meta where key = ?', [key])?.value ?? null;
    },
    async setMeta(key, value) {
      db.runSync('insert into meta (key, value) values (?, ?) on conflict(key) do update set value = excluded.value', [key, value]);
    },
    async append(e) {
      db.runSync(
        'insert into outbox (event_id, seq, type, client_ts, lat, lng, accuracy_m, payload, status) values (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [e.eventId, e.seq, e.type, e.clientTs, e.lat, e.lng, e.accuracyM, JSON.stringify(e.payload), e.status],
      );
    },
    async pending(limit) {
      return db.getAllSync<Row>("select * from outbox where status = 'pending' order by seq limit ?", [limit]).map(toEvent);
    },
    async all() {
      return db.getAllSync<Row>('select * from outbox order by seq').map(toEvent);
    },
    async markResult(eventId, status, reason, result) {
      db.runSync('update outbox set status = ?, reason = ?, result = ? where event_id = ?',
        [status, reason, result === null || result === undefined ? null : JSON.stringify(result), eventId]);
    },
  };
}
