import { Flash, Shell, Status, type FlashParams } from '@/components/shell';
import { requireOrgRole } from '@/lib/session';
import { requestDistributor, submitKyc } from './actions';

export default async function RetailerPage({ params, searchParams }: {
  params: Promise<{ orgId: string }>;
  searchParams: FlashParams;
}) {
  const { orgId } = await params;
  const { ok, error } = await searchParams;
  const { repo, membership } = await requireOrgRole(orgId, ['retailer']);
  const [[shop], relationships, checks, level, directory] = await Promise.all([
    repo.organisations.byIds([orgId]),
    repo.retailer.relationships(orgId),
    repo.retailer.kycChecks(orgId),
    repo.retailer.kycLevel(orgId),
    repo.registration.directory(),
  ]);
  const linked = new Set(relationships.map((r) => r.distributor_org_id));
  const available = directory.filter((d) => !linked.has(d.id));

  return (
    <Shell nav={[{ href: `/retailer/${orgId}`, label: membership.orgName }]}>
      <h1>{shop?.name}</h1>
      <p>Shop status: <Status value={shop?.status ?? 'pending'} /> · KYC level <strong>{level}</strong> of 2</p>
      <Flash ok={ok} error={error} />

      <h2>Distributors</h2>
      <div className="panel table-wrap">
        <table>
          <thead><tr><th>Distributor</th><th>Status</th><th>Note</th></tr></thead>
          <tbody>
            {relationships.map((r) => (
              <tr key={r.id}><td>{r.organisations?.name}</td><td><Status value={r.status} /></td><td className="muted">{r.decision_reason ?? ''}</td></tr>
            ))}
          </tbody>
        </table>
        {available.length > 0 ? (
          <form action={requestDistributor} className="inline" style={{ marginTop: 12 }}>
            <input type="hidden" name="orgId" value={orgId} />
            <label>Also buy from
              <select name="distributorId">{available.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}</select>
            </label>
            <button type="submit">Send request</button>
          </form>
        ) : null}
      </div>

      <h2>Identity verification (BVN / NIN)</h2>
      <div className="grid">
        <form action={submitKyc} className="panel stack">
          <input type="hidden" name="orgId" value={orgId} />
          <label>ID type
            <select name="idType"><option value="BVN">BVN</option><option value="NIN">NIN</option></select>
          </label>
          <label>ID number (11 digits)<input name="idNumber" inputMode="numeric" pattern="\d{11}" autoComplete="off" required /></label>
          <label>First name (as on the ID)<input name="firstName" required /></label>
          <label>Last name (as on the ID)<input name="lastName" required /></label>
          <label>Date of birth (optional)<input name="dateOfBirth" type="date" /></label>
          <p className="muted">We check that your details match the ID. We never store the number itself, and we never receive or keep a photo.</p>
          <button type="submit">Verify</button>
        </form>
        <div className="panel">
          <h2 style={{ marginTop: 0 }}>History</h2>
          {checks.length === 0 ? <p className="muted">No checks yet.</p> : (
            <ul>{checks.map((c) => (
              <li key={c.id}>{c.id_type}: <Status value={c.outcome} /> <span className="muted">{new Date(c.checked_at).toLocaleString('en-NG')}</span></li>
            ))}</ul>
          )}
        </div>
      </div>
    </Shell>
  );
}
