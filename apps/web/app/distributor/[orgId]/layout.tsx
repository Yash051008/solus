import { Shell } from '@/components/shell';
import { requireOrgRole } from '@/lib/session';

export default async function DistributorLayout({ children, params }: {
  children: React.ReactNode;
  params: Promise<{ orgId: string }>;
}) {
  const { orgId } = await params;
  const { membership } = await requireOrgRole(orgId, ['distributor_admin', 'branch_manager', 'warehouse_staff']);
  const base = `/distributor/${orgId}`;
  const nav = [
    { href: base, label: membership.orgName },
    ...(membership.role === 'warehouse_staff' ? [] : [{ href: `${base}/approvals`, label: 'Approvals' }]),
    { href: `${base}/stock`, label: 'Stock' },
    { href: `${base}/fulfilment`, label: 'Fulfilment' },
    { href: `${base}/push`, label: 'Agent stock' },
    { href: `${base}/structure`, label: 'Branches & warehouses' },
    ...(membership.role === 'distributor_admin' ? [{ href: `${base}/settings`, label: 'Settings' }] : []),
  ];
  return <Shell nav={nav}>{children}</Shell>;
}
