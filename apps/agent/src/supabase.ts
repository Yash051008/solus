import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';

const url = process.env.EXPO_PUBLIC_SUPABASE_URL ?? '';
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? '';

export const configured = url !== '' && anonKey !== '';

/** Weak signal often means requests that hang rather than fail; give up after this so the outbox keeps the events. */
const REQUEST_TIMEOUT_MS = 15_000;

const fetchWithTimeout: typeof fetch = (input, init) => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  init?.signal?.addEventListener('abort', () => controller.abort());
  return fetch(input, { ...init, signal: controller.signal }).finally(() => clearTimeout(timer));
};

/** Session persists on the device so the agent stays signed in while offline. */
export const supabase = createClient(url || 'http://localhost:54321', anonKey || 'missing', {
  auth: { storage: AsyncStorage, persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
  global: { fetch: fetchWithTimeout },
});
