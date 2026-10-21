import 'server-only';
import { createClient } from '@supabase/supabase-js';
import { createAdapterRepository, type Database, type DbClient } from '@solus/db';
import { publicEnv } from '../env';

/**
 * service_role client for SERVER-SIDE ADAPTERS ONLY. The role can execute just the adapter functions
 * granted to it (e.g. app.record_kyc_result) and cannot write ledgers directly (migration *_grants.sql).
 */
export function adapterRepository() {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) throw new Error('missing SUPABASE_SERVICE_ROLE_KEY');
  const client = createClient<Database>(publicEnv.supabaseUrl(), key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return createAdapterRepository(client as unknown as DbClient);
}
