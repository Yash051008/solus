import { Flash, Shell, Status, type FlashParams } from '@/components/shell';
import { requireSession } from '@/lib/session';
import { notFound } from 'next/navigation';
import { onboardOrganisation } from './actions';

export default async function PlatformPage({ searchParams }: { searchParams: FlashParams }) {
  const { ok, error } = await searchParams;
  const { repo, memberships } = await requireSession();
  if (!memberships.some((m) => m.role === 'platform_admin' && m.status === 'active')) notFound();
  const [manufacturers, distributors, retailers] = await Promise.all([
    repo.organisations.byKind('manufacturer'), repo.organisations.byKind('distributor'), repo.organisations.byKind('retailer'),
  ]);

  return (
    <Shell nav={[{ href: '/platform', label: 'Platform' }]}>
      <h1>Platform administration</h1>
      <Flash ok={ok} error={error} />
      <div className="grid">
        <div className="panel"><strong>{manufacturers.length}</strong> manufacturers</div>
        <div className="panel"><strong>{distributors.length}</strong> distributors</div>
        <div className="panel"><strong>{retailers.length}</strong> retailers ({retailers.filter((r) => r.status === 'pending').length} pending)</div>
      </div>

      <h2>Organisations</h2>
      <div className="panel table-wrap"><table>
        <thead><tr><th>Name</th><th>Kind</th><th>Status</th></tr></thead>
        <tbody>
          {[...manufacturers, ...distributors].map((o) => (
            <tr key={o.id}><td>{o.name}</td><td>{o.kind}</td><td><Status value={o.status ?? 'pending'} /></td></tr>
          ))}
        </tbody>
      </table></div>

      <h2>Onboard a manufacturer or distributor</h2>
      <form action={onboardOrganisation} className="panel stack">
        <label>Kind
          <select name="kind"><option value="distributor">Distributor</option><option value="manufacturer">Manufacturer</option></select>
        </label>
        <label>Legal name<input name="name" required /></label>
        <label>Slug (lowercase, dashes)<input name="slug" pattern="[a-z0-9][a-z0-9\-]{1,62}" required /></label>
        <label>First admin's user ID (they find it on their Get started page)<input name="adminUserId" required /></label>
        <button type="submit">Onboard</button>
      </form>
    </Shell>
  );
}
