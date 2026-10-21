import Link from 'next/link';
import { requireOrgRole } from '@/lib/session';

export default async function DistributorHome({ params }: { params: Promise<{ orgId: string }> }) {
  const { orgId } = await params;
  const { repo, membership } = await requireOrgRole(orgId, ['distributor_admin', 'branch_manager', 'warehouse_staff']);
  const canApprove = membership.role !== 'warehouse_staff';
  const [customers, joins, branches, warehouses] = await Promise.all([
    canApprove ? repo.approvals.pendingCustomers(orgId) : Promise.resolve([]),
    canApprove ? repo.approvals.pendingJoinRequests(orgId) : Promise.resolve([]),
    repo.structure.branches(orgId),
    repo.structure.warehouses(orgId),
  ]);
  const base = `/distributor/${orgId}`;
  return (
    <>
      <h1>{membership.orgName}</h1>
      <p className="muted">Signed in as {membership.role.replace('_', ' ')}</p>
      <div className="grid">
        {canApprove ? (
          <Link href={`${base}/approvals`} className="panel">
            <strong>{customers.length + joins.length}</strong> pending approvals
            <div className="muted">{customers.length} shops · {joins.length} staff/agents</div>
          </Link>
        ) : null}
        <Link href={`${base}/structure`} className="panel">
          <strong>{branches.length}</strong> branches · <strong>{warehouses.filter((w) => w.active).length}</strong> active warehouses
        </Link>
      </div>
      <p className="muted">Inventory, orders and fulfilment arrive in Phase 4.</p>
    </>
  );
}
