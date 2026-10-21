'use server';
import { redirect } from 'next/navigation';
import { getRepo } from '@/lib/supabase/server';

export async function markAllRead() {
  await (await getRepo()).notifications.markRead();
  redirect('/inbox');
}
