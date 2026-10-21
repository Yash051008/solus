'use server';
import { redirect } from 'next/navigation';
import { requireSession } from '@/lib/session';
import { adapterRepository } from '@/lib/supabase/admin';
import { paymentProvider } from '@/lib/payments';

export async function reconcile() {
  const { memberships } = await requireSession();
  if (!memberships.some((m) => m.role === 'platform_admin' && m.status === 'active')) redirect('/platform/payments?error=forbidden');
  const provider = paymentProvider();
  const result = await adapterRepository().reconcile(provider.name, await provider.statement());
  redirect(`/platform/payments?r=${encodeURIComponent(JSON.stringify(result))}`);
}
