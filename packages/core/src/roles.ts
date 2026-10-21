// Per-role landing routes. UX only: every permission is enforced in Postgres (RLS + app.* functions).

export const MEMBER_ROLES = [
  'platform_admin', 'manufacturer_admin', 'distributor_admin', 'branch_manager',
  'warehouse_staff', 'driver', 'agent', 'retailer',
] as const;
export type MemberRole = (typeof MEMBER_ROLES)[number];

export type ActiveMembership = { role: MemberRole; orgId: string; status: 'pending' | 'active' | 'suspended' | 'rejected' };

/** Precedence when a user holds several memberships: the broadest console wins. */
const PRECEDENCE: readonly MemberRole[] = [
  'platform_admin', 'manufacturer_admin', 'distributor_admin', 'branch_manager',
  'warehouse_staff', 'retailer', 'agent', 'driver',
];

export function homePathFor(memberships: readonly ActiveMembership[]): string {
  const active = memberships.filter((m) => m.status === 'active');
  for (const role of PRECEDENCE) {
    const m = active.find((x) => x.role === role);
    if (!m) continue;
    switch (role) {
      case 'platform_admin':
        return '/platform';
      case 'manufacturer_admin':
        return `/manufacturer/${m.orgId}`;
      case 'distributor_admin':
      case 'branch_manager':
      case 'warehouse_staff':
        return `/distributor/${m.orgId}`;
      case 'retailer':
        return `/retailer/${m.orgId}`;
      case 'agent':
      case 'driver':
        return '/field';
    }
  }
  return '/onboarding';
}
