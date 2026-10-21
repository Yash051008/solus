import { Flash, Status, type FlashParams } from '@/components/shell';
import { requireOrgRole } from '@/lib/session';
import { createBranch, createTerritory, createWarehouse, setWarehouseActive } from '../actions';

export default async function StructurePage({ params, searchParams }: {
  params: Promise<{ orgId: string }>;
  searchParams: FlashParams;
}) {
  const { orgId } = await params;
  const { ok, error } = await searchParams;
  const { repo, membership } = await requireOrgRole(orgId, ['distributor_admin', 'branch_manager', 'warehouse_staff']);
  const isAdmin = membership.role === 'distributor_admin';
  const canAddTerritory = isAdmin || membership.role === 'branch_manager';
  const [branches, territories, warehouses] = await Promise.all([
    repo.structure.branches(orgId), repo.structure.territories(orgId), repo.structure.warehouses(orgId),
  ]);
  const branchName = new Map(branches.map((b) => [b.id, b.name]));

  return (
    <>
      <h1>Branches, territories and warehouses</h1>
      <Flash ok={ok} error={error} />

      <h2>Branches</h2>
      <div className="panel">
        <ul>{branches.map((b) => <li key={b.id}>{b.name}</li>)}</ul>
        {isAdmin ? (
          <form action={createBranch} className="inline">
            <input type="hidden" name="orgId" value={orgId} />
            <label>New branch<input name="name" required /></label>
            <button type="submit">Add branch</button>
          </form>
        ) : null}
      </div>

      <h2>Territories</h2>
      <div className="panel">
        <div className="table-wrap"><table>
          <thead><tr><th>Territory</th><th>Branch</th><th>Boundary</th></tr></thead>
          <tbody>
            {territories.map((t) => (
              <tr key={t.id}><td>{t.name}</td><td>{branchName.get(t.branch_id ?? '')}</td><td>{t.has_boundary ? 'mapped' : 'none (nearest-warehouse fallback)'}</td></tr>
            ))}
          </tbody>
        </table></div>
        {canAddTerritory ? (
          <form action={createTerritory} className="stack" style={{ marginTop: 12 }}>
            <input type="hidden" name="orgId" value={orgId} />
            <label>Branch
              <select name="branchId" required>{branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}</select>
            </label>
            <label>Territory name<input name="name" required /></label>
            <label>Boundary, optional (GeoJSON Polygon or MultiPolygon, lng/lat)
              <textarea name="boundary" placeholder='{"type":"Polygon","coordinates":[[[3.34,6.57],[3.36,6.57],[3.36,6.59],[3.34,6.59],[3.34,6.57]]]}' />
            </label>
            <button type="submit">Add territory</button>
          </form>
        ) : null}
      </div>

      <h2>Warehouses</h2>
      <div className="panel">
        <div className="table-wrap"><table>
          <thead><tr><th>Warehouse</th><th>Branch</th><th>Location</th><th>Status</th><th /></tr></thead>
          <tbody>
            {warehouses.map((w) => (
              <tr key={w.id}>
                <td>{w.name}</td><td>{branchName.get(w.branch_id ?? '')}</td>
                <td>{w.lat?.toFixed(5)}, {w.lng?.toFixed(5)}</td>
                <td><Status value={w.active ? 'active' : 'suspended'} /></td>
                <td>
                  {isAdmin ? (
                    <form action={setWarehouseActive}>
                      <input type="hidden" name="orgId" value={orgId} />
                      <input type="hidden" name="warehouseId" value={w.id ?? ''} />
                      <input type="hidden" name="active" value={w.active ? 'false' : 'true'} />
                      <button className="secondary" type="submit">{w.active ? 'Deactivate' : 'Activate'}</button>
                    </form>
                  ) : null}
                </td>
              </tr>
            ))}
          </tbody>
        </table></div>
        {isAdmin ? (
          <form action={createWarehouse} className="inline" style={{ marginTop: 12 }}>
            <input type="hidden" name="orgId" value={orgId} />
            <label>Branch
              <select name="branchId" required>{branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}</select>
            </label>
            <label>Name<input name="name" required /></label>
            <label>Latitude<input name="lat" inputMode="decimal" required /></label>
            <label>Longitude<input name="lng" inputMode="decimal" required /></label>
            <button type="submit">Add warehouse</button>
          </form>
        ) : null}
      </div>
    </>
  );
}
