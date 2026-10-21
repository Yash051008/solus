// The repository layer is the ONLY TypeScript that talks to the database (ADR-0004). It hides
// supabase-js behind small typed functions so the transport can change (e.g. plain PostgREST or pg).
import type { SupabaseClient } from '@supabase/supabase-js';
import { DomainError, domainCodeFor } from '@solus/core';
import type { Database } from './database.types.ts';

export type DbClient = SupabaseClient<Database>;
export type AppFunctions = Database['app']['Functions'];
export type Tables = Database['public']['Tables'];
export type Views = Database['public']['Views'];
export type Enums = Database['public']['Enums'];

type PgError = { code?: string; message: string; details?: string | null; hint?: string | null };

export function toDomainError(error: PgError): DomainError {
  return new DomainError(domainCodeFor(error.code), error.message, error.code);
}

/** Calls an app.* command. Errors surface as DomainError with the SOL code mapped. */
export async function command<F extends keyof AppFunctions & string>(
  client: DbClient,
  fn: F,
  args: AppFunctions[F]['Args'],
): Promise<AppFunctions[F]['Returns']> {
  // supabase-js typing for schema-qualified rpc is loose; the generic signature above is the contract.
  const { data, error } = await (client.schema('app') as unknown as {
    rpc: (f: string, a: unknown) => Promise<{ data: unknown; error: PgError | null }>;
  }).rpc(fn, args);
  if (error) throw toDomainError(error);
  return data as AppFunctions[F]['Returns'];
}

/** Unwraps a PostgREST select result. */
export function rows<T>(result: { data: T[] | null; error: PgError | null }): T[] {
  if (result.error) throw toDomainError(result.error);
  return result.data ?? [];
}
