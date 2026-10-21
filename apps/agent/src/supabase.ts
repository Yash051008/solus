import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';

const url = process.env.EXPO_PUBLIC_SUPABASE_URL ?? '';
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? '';

export const configured = url !== '' && anonKey !== '';

/** Session persists on the device so the agent stays signed in while offline. */
export const supabase = createClient(url || 'http://localhost:54321', anonKey || 'missing', {
  auth: { storage: AsyncStorage, persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
});
