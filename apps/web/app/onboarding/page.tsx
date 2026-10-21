import Link from 'next/link';
import { homePathFor } from '@solus/core';
import { Flash, Shell, Status, type FlashParams } from '@/components/shell';
import { LocationFields } from '@/components/location-fields';
import { requireSession } from '@/lib/session';
import { registerShop, requestToJoin } from './actions';

export default async function OnboardingPage({ searchParams }: { searchParams: FlashParams }) {
  const { ok, error } = await searchParams;
  const { repo, userId, memberships } = await requireSession();
  const [directory, requests] = await Promise.all([repo.registration.directory(), repo.me.joinRequests()]);
  const home = homePathFor(memberships);
  const hasShop = memberships.some((m) => m.role === 'retailer');

  return (
    <Shell>
      <h1>Get started</h1>
      <p className="muted">Your user ID (share it with a platform admin if you are onboarding a company): <code>{userId}</code></p>
      <Flash ok={ok} error={error} />
      {home !== '/onboarding' ? <p><Link href={home}>Go to your console →</Link></p> : null}

      {requests.length > 0 ? (
        <section className="panel">
          <h2>Your requests</h2>
          <div className="table-wrap"><table>
            <thead><tr><th>Distributor</th><th>Role</th><th>Status</th><th>Note</th></tr></thead>
            <tbody>
              {requests.map((r) => (
                <tr key={r.id}>
                  <td>{r.organisations?.name}</td><td>{r.requested_role.replace('_', ' ')}</td>
                  <td><Status value={r.status} /></td><td className="muted">{r.decision_reason ?? ''}</td>
                </tr>
              ))}
            </tbody>
          </table></div>
        </section>
      ) : null}

      <div className="grid">
        {!hasShop ? (
          <section className="panel">
            <h2>Register my shop</h2>
            <form action={registerShop} className="stack">
              <label>Shop name<input name="businessName" required /></label>
              <label>Your full name<input name="fullName" autoComplete="name" required /></label>
              <label>Phone (+234…)<input name="phone" type="tel" placeholder="+2348012345678" pattern="\+[1-9][0-9]{7,14}" required /></label>
              <label>Distributor
                <select name="distributorId" required>
                  {directory.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
                </select>
              </label>
              <p className="muted">Stand inside your shop when capturing its location. Agent visits are checked against it.</p>
              <LocationFields />
              <button type="submit">Register shop</button>
            </form>
          </section>
        ) : null}

        <section className="panel">
          <h2>Join a distributor as staff</h2>
          <form action={requestToJoin} className="stack">
            <label>Distributor
              <select name="distributorId" required>
                {directory.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
              </select>
            </label>
            <label>Role
              <select name="role" required>
                <option value="agent">Sales agent</option>
                <option value="driver">Driver</option>
                <option value="warehouse_staff">Warehouse staff</option>
                <option value="branch_manager">Branch manager</option>
              </select>
            </label>
            <label>Your full name<input name="fullName" autoComplete="name" required /></label>
            <label>Phone (+234…)<input name="phone" type="tel" placeholder="+2348012345678" pattern="\+[1-9][0-9]{7,14}" required /></label>
            <label>Note for the approver (optional)<textarea name="note" maxLength={500} /></label>
            <button type="submit">Send request</button>
          </form>
        </section>
      </div>
    </Shell>
  );
}
