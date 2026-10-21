import { Flash, type FlashParams } from '@/components/shell';
import { requireOrgRole } from '@/lib/session';
import { decideCustomer, decideJoinRequest } from '../actions';

export default async function ApprovalsPage({ params, searchParams }: {
  params: Promise<{ orgId: string }>;
  searchParams: FlashParams;
}) {
  const { orgId } = await params;
  const { ok, error } = await searchParams;
  const { repo } = await requireOrgRole(orgId, ['distributor_admin', 'branch_manager']);
  const [customers, joins, territories, branches] = await Promise.all([
    repo.approvals.pendingCustomers(orgId),
    repo.approvals.pendingJoinRequests(orgId),
    repo.structure.territories(orgId),
    repo.structure.branches(orgId),
  ]);
  const shops = await repo.organisations.byIds(customers.map((c) => c.retailer_org_id));
  const kycLevels = new Map(await Promise.all(
    customers.map(async (c) => [c.retailer_org_id, await repo.retailer.kycLevel(c.retailer_org_id)] as const),
  ));
  const shopById = new Map(shops.map((s) => [s.id, s]));

  return (
    <>
      <h1>Approvals</h1>
      <p className="muted">Branch managers can approve customers in their own branch's territories and staff into their own branch.</p>
      <Flash ok={ok} error={error} />

      <h2>Shops waiting for approval ({customers.length})</h2>
      {customers.length === 0 ? <p className="muted">Nothing pending.</p> : (
        <div className="table-wrap"><table>
          <thead><tr><th>Shop</th><th>Location</th><th>KYC</th><th>Decision</th></tr></thead>
          <tbody>
            {customers.map((c) => {
              const s = shopById.get(c.retailer_org_id);
              return (
                <tr key={c.id}>
                  <td>{s?.name}<div className="muted">registered {new Date(c.created_at).toLocaleDateString('en-NG')}</div></td>
                  <td>{s?.lat?.toFixed(5)}, {s?.lng?.toFixed(5)}<div className="muted">±{s?.location_accuracy_m ?? '?'} m</div></td>
                  <td>Level {kycLevels.get(c.retailer_org_id) ?? 0}</td>
                  <td>
                    <form action={decideCustomer} className="inline">
                      <input type="hidden" name="orgId" value={orgId} />
                      <input type="hidden" name="relationshipId" value={c.id} />
                      <label>Territory
                        <select name="territoryId" defaultValue={c.territory_id}>
                          {territories.map((t) => <option key={t.id} value={t.id ?? ''}>{t.name}</option>)}
                        </select>
                      </label>
                      <button name="decision" value="approve" type="submit">Approve</button>
                    </form>
                    <form action={decideCustomer} className="inline" style={{ marginTop: 8 }}>
                      <input type="hidden" name="orgId" value={orgId} />
                      <input type="hidden" name="relationshipId" value={c.id} />
                      <label>Reason<input name="reason" placeholder="required to reject" /></label>
                      <button name="decision" value="reject" className="danger" type="submit">Reject</button>
                    </form>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table></div>
      )}

      <h2>Staff and agent requests ({joins.length})</h2>
      {joins.length === 0 ? <p className="muted">Nothing pending.</p> : (
        <div className="table-wrap"><table>
          <thead><tr><th>Person</th><th>Role</th><th>Decision</th></tr></thead>
          <tbody>
            {joins.map((j) => (
              <tr key={j.id}>
                <td>{j.profiles?.full_name}<div className="muted">{j.profiles?.phone_e164}</div>{j.note ? <div className="muted">"{j.note}"</div> : null}</td>
                <td>{j.requested_role.replace('_', ' ')}</td>
                <td>
                  <form action={decideJoinRequest} className="inline">
                    <input type="hidden" name="orgId" value={orgId} />
                    <input type="hidden" name="requestId" value={j.id} />
                    <label>Branch
                      <select name="branchId" required>
                        {branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
                      </select>
                    </label>
                    {j.requested_role === 'agent' ? (
                      <label>Territory (must be in that branch)
                        <select name="territoryId" required>
                          {territories.map((t) => <option key={t.id} value={t.id ?? ''}>{t.name}</option>)}
                        </select>
                      </label>
                    ) : null}
                    <button name="decision" value="approve" type="submit">Approve</button>
                  </form>
                  <form action={decideJoinRequest} className="inline" style={{ marginTop: 8 }}>
                    <input type="hidden" name="orgId" value={orgId} />
                    <input type="hidden" name="requestId" value={j.id} />
                    <label>Reason<input name="reason" placeholder="required to reject" /></label>
                    <button name="decision" value="reject" className="danger" type="submit">Reject</button>
                  </form>
                </td>
              </tr>
            ))}
          </tbody>
        </table></div>
      )}
    </>
  );
}
