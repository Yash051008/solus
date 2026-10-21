import 'server-only';
import { notFound, redirect } from 'next/navigation';
import type { MemberRole } from '@solus/core';
import type { Membership } from '@solus/db';
import { getRepo } from './supabase/server';

/** Loads the signed-in user's memberships; redirects to /login when there is no session. */
export async function requireSession() {
  const repo = await getRepo();
  const userId = await repo.me.userId();
  if (userId === null) redirect('/login');
  const memberships = await repo.me.memberships();
  return { repo, userId, memberships };
}

/** Page guard (UX): 404 unless the user holds one of the roles in this org. Data access is RLS-enforced regardless. */
export async function requireOrgRole(orgId: string, roles: readonly MemberRole[]) {
  const session = await requireSession();
  const membership = session.memberships.find(
    (m: Membership) => m.orgId === orgId && m.status === 'active' && roles.includes(m.role),
  );
  if (!membership) notFound();
  return { ...session, membership };
}
