import { Shell, Status } from '@/components/shell';
import { requireOrgRole } from '@/lib/session';

export default async function ManufacturerPage({ params }: { params: Promise<{ orgId: string }> }) {
  const { orgId } = await params;
  const { repo, membership } = await requireOrgRole(orgId, ['manufacturer_admin']);
  const distributors = await repo.organisations.byKind('distributor');
  return (
    <Shell nav={[{ href: `/manufacturer/${orgId}`, label: membership.orgName }]}>
      <h1>{membership.orgName}</h1>
      <h2>Supplied distributors</h2>
      <div className="panel"><ul>{distributors.map((d) => <li key={d.id}>{d.name} <Status value={d.status ?? 'pending'} /></li>)}</ul></div>
      <p className="muted">Catalogue management arrives in Phase 4. Aggregate sales views arrive in Phase 6 (no retailer-level data is visible to manufacturers).</p>
    </Shell>
  );
}
