import 'server-only';
import { cookies } from 'next/headers';
import { createServerClient } from '@supabase/ssr';
import { createRepository, type Database, type DbClient } from '@solus/db';
import { publicEnv } from '../env';

/** Supabase client acting AS the signed-in user (cookie session). RLS applies to everything it does. */
export async function createUserClient(): Promise<DbClient> {
  const cookieStore = await cookies();
  return createServerClient<Database>(publicEnv.supabaseUrl(), publicEnv.supabaseAnonKey(), {
    cookies: {
      getAll: () => cookieStore.getAll(),
      setAll: (toSet) => {
        try {
          for (const { name, value, options } of toSet) cookieStore.set(name, value, options);
        } catch {
          // Called from a Server Component: cookies are read-only there; middleware refreshes the session.
        }
      },
    },
  }) as unknown as DbClient;
}

export async function getRepo() {
  return createRepository(await createUserClient());
}
