// Shared helpers for Node tests that must run against the REAL local Postgres (never a mock).
import pg from 'pg';

export const DATABASE_URL =
  process.env['DATABASE_URL'] ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';

export async function connect(): Promise<pg.Client> {
  const client = new pg.Client({ connectionString: DATABASE_URL });
  await client.connect();
  return client;
}

export async function one<T extends pg.QueryResultRow>(
  client: pg.Client,
  sql: string,
  params: unknown[] = [],
): Promise<T> {
  const res = await client.query<T>(sql, params);
  const row = res.rows[0];
  if (row === undefined) throw new Error(`expected one row from: ${sql}`);
  return row;
}

/** SQLSTATE of a pg error, or 'non-pg-error'. */
export function sqlstate(err: unknown): string {
  return typeof err === 'object' && err !== null && 'code' in err && typeof err.code === 'string'
    ? err.code
    : 'non-pg-error';
}

export async function waitFor(check: () => Promise<boolean>, timeoutMs: number, what: string): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await check()) return;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error(`timed out after ${timeoutMs}ms waiting for ${what}`);
}

/** Runs the ledger rebuild checks; each must return zero rows. */
export async function assertProjectionsMatchLedgers(client: pg.Client): Promise<void> {
  for (const fn of ['check_stock_projection', 'check_money_projection', 'check_journals_balanced']) {
    const res = await client.query(`select * from app.${fn}()`);
    if (res.rowCount !== 0) {
      throw new Error(`app.${fn}() returned ${res.rowCount} mismatch(es): ${JSON.stringify(res.rows)}`);
    }
  }
}
