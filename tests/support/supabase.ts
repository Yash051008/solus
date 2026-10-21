// Real Supabase clients against the local stack (Auth + PostgREST), for end-to-end tests as genuine users.
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import type { Database, DbClient } from '@solus/db';

type StackEnv = { apiUrl: string; anonKey: string; serviceRoleKey: string };

let cached: StackEnv | undefined;

export function stackEnv(): StackEnv {
  if (cached) return cached;
  const out = execFileSync('supabase', ['status', '-o', 'env'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  const get = (k: string) => {
    const m = new RegExp(`^${k}="?([^"\\n]+)"?$`, 'm').exec(out);
    if (!m?.[1]) throw new Error(`supabase status did not report ${k}; is the local stack running?`);
    return m[1];
  };
  cached = { apiUrl: get('API_URL'), anonKey: get('ANON_KEY'), serviceRoleKey: get('SERVICE_ROLE_KEY') };
  return cached;
}

function client(key: string): DbClient {
  return createClient<Database>(stackEnv().apiUrl, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  }) as unknown as DbClient;
}

export const SEED_PASSWORD = 'SolusDev-2026!';

/** Signs in a seeded user (`<handle>@solus.test`). */
export async function signIn(handle: string): Promise<DbClient> {
  const c = client(stackEnv().anonKey);
  const { error } = await c.auth.signInWithPassword({ email: `${handle}@solus.test`, password: SEED_PASSWORD });
  if (error) throw new Error(`sign-in failed for ${handle}: ${error.message}`);
  return c;
}

/** Signs up a brand-new user through Supabase Auth (email confirmation is off locally). */
export async function signUpFresh(prefix: string): Promise<{ db: DbClient; email: string }> {
  const c = client(stackEnv().anonKey);
  const email = `${prefix}-${randomUUID().slice(0, 8)}@solus.test`;
  const { data, error } = await c.auth.signUp({ email, password: 'Integration-Test-Pass-1' });
  if (error || !data.session) throw new Error(`sign-up failed: ${error?.message ?? 'no session returned'}`);
  return { db: c, email };
}

export function serviceClient(): DbClient {
  return client(stackEnv().serviceRoleKey);
}
