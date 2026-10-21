import { Flash, Status, type FlashParams } from '@/components/shell';
import { requireOrgRole } from '@/lib/session';
import { showQty, skuMap } from '@/lib/catalogue';
import { decideAdjustment, recordReceipt, requestAdjustment } from './actions';

export default async function StockPage({ params, searchParams }: { params: Promise<{ orgId: string }>; searchParams: FlashParams }) {
  const { orgId } = await params;
  const { ok, error } = await searchParams;
  const { repo, membership } = await requireOrgRole(orgId, ['distributor_admin', 'branch_manager', 'warehouse_staff']);
  const [skus, balances, locations, warehouses, adjustments] = await Promise.all([
    skuMap(repo), repo.stock.balances(orgId), repo.stock.locations(orgId), repo.structure.warehouses(orgId), repo.stock.adjustments(orgId),
  ]);
  const whName = new Map(warehouses.map((w) => [w.id, w.name]));
  const locLabel = new Map(locations.map((l) => [l.id, l.warehouse_id ? whName.get(l.warehouse_id) ?? 'warehouse' : `${l.kind} (carried)`]));
  const rows = balances
    .filter((b) => b.on_hand > 0 || b.reserved > 0)
    .sort((a, b) => (locLabel.get(a.location_id) ?? '').localeCompare(locLabel.get(b.location_id) ?? '')
      || (skus.get(a.sku_id)?.code ?? '').localeCompare(skus.get(b.sku_id)?.code ?? ''));
  const canApprove = membership.role !== 'warehouse_staff';
  const visibleWh = new Set(locations.map((l) => l.warehouse_id).filter(Boolean));
  const activeWarehouses = warehouses.filter((w) => w.active && visibleWh.has(w.id));
  const skuList = [...skus.values()].sort((a, b) => a.code.localeCompare(b.code));

  return (
    <>
      <h1>Stock</h1>
      <p className="muted">Live balances from the stock ledger. Quantities are stored in pieces; cartons are shown for convenience.</p>
      <Flash ok={ok} error={error} />
      <div className="panel table-wrap"><table>
        <thead><tr><th>Location</th><th>SKU</th><th>On hand</th><th>Reserved</th><th>Available</th></tr></thead>
        <tbody>{rows.map((b) => {
          const s = skus.get(b.sku_id);
          return (
            <tr key={`${b.location_id}:${b.sku_id}`}>
              <td>{locLabel.get(b.location_id)}</td><td><code>{s?.code}</code> {s?.name}</td>
              <td>{showQty(b.on_hand, s)}</td><td>{b.reserved ? showQty(b.reserved, s) : ''}</td><td><strong>{showQty(b.available ?? 0, s)}</strong></td>
            </tr>
          );
        })}</tbody>
      </table></div>

      <div className="grid">
        <form action={recordReceipt} className="panel stack">
          <h2 style={{ marginTop: 0 }}>Record a receipt</h2>
          <input type="hidden" name="orgId" value={orgId} />
          <label>Warehouse<select name="warehouseId" required>{activeWarehouses.map((w) => <option key={w.id} value={w.id ?? ''}>{w.name}</option>)}</select></label>
          <label>Reference (GRN / waybill)<input name="reference" required /></label>
          <label>SKU<select name="skuId" required>{skuList.map((s) => <option key={s.id} value={s.id}>{s.code}: {s.name}</option>)}</select></label>
          <label>Unit<select name="uomCode"><option value="carton">carton</option><option value="piece">piece</option></select></label>
          <label>Quantity<input name="uomQty" inputMode="numeric" required /></label>
          <button type="submit">Record receipt</button>
        </form>
        <form action={requestAdjustment} className="panel stack">
          <h2 style={{ marginTop: 0 }}>Request an adjustment</h2>
          <p className="muted">Needs approval by a branch manager who did not request it.</p>
          <input type="hidden" name="orgId" value={orgId} />
          <label>Warehouse<select name="warehouseId" required>{activeWarehouses.map((w) => <option key={w.id} value={w.id ?? ''}>{w.name}</option>)}</select></label>
          <label>SKU<select name="skuId" required>{skuList.map((s) => <option key={s.id} value={s.id}>{s.code}: {s.name}</option>)}</select></label>
          <label>Change in pieces (negative to remove)<input name="qtyDelta" inputMode="numeric" required /></label>
          <label>Reason<input name="reason" required minLength={3} /></label>
          <button type="submit">Request</button>
        </form>
      </div>

      <h2>Adjustment requests</h2>
      <div className="panel table-wrap"><table>
        <thead><tr><th>Location</th><th>SKU</th><th>Change</th><th>Reason</th><th>Status</th><th /></tr></thead>
        <tbody>{adjustments.map((a) => (
          <tr key={a.id}>
            <td>{locLabel.get(a.location_id)}</td><td>{skus.get(a.sku_id)?.code}</td><td>{a.qty_delta > 0 ? '+' : ''}{a.qty_delta} pcs</td>
            <td>{a.reason}</td><td><Status value={a.status} /></td>
            <td>{canApprove && a.status === 'pending' ? (
              <form action={decideAdjustment} className="inline">
                <input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="requestId" value={a.id} />
                <button name="decision" value="approve" type="submit">Approve</button>
                <input name="reason" placeholder="reason to reject" />
                <button name="decision" value="reject" className="danger" type="submit">Reject</button>
              </form>
            ) : null}</td>
          </tr>
        ))}</tbody>
      </table></div>
    </>
  );
}
