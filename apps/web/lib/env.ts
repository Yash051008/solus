function required(name: string, value: string | undefined): string {
  if (value === undefined || value === '') throw new Error(`missing environment variable ${name} (see apps/web/.env.example)`);
  return value;
}

// NEXT_PUBLIC_* must be referenced literally so Next can inline them.
export const publicEnv = {
  supabaseUrl: () => required('NEXT_PUBLIC_SUPABASE_URL', process.env.NEXT_PUBLIC_SUPABASE_URL),
  supabaseAnonKey: () => required('NEXT_PUBLIC_SUPABASE_ANON_KEY', process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY),
};
