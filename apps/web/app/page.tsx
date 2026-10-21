import { redirect } from 'next/navigation';
import { homePathFor } from '@solus/core';
import { requireSession } from '@/lib/session';

export default async function Home() {
  const { memberships } = await requireSession();
  redirect(homePathFor(memberships));
}
