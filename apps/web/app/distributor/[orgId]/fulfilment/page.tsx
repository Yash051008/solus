import Link from 'next/link';
import { Flash, Status } from '@/components/shell';
import { requireOrgRole } from '@/lib/session';
import { showQty, skuMap } from '@/lib/catalogue';
import { createBatch, decideSplit, dispatchBatch, markPacked, startReturn } from './actions';

export default async function FulfilmentPage({ params, searchParams }: {
  params: Promise<{ orgId: string }>;
  searchParams: Promise<{ ok?: string; error?: string; w?: string }>;
}) {
  const { orgId } = await params;
  const { ok, error, w } = await searchParams;
  const { repo, membership } = await requireOrgRole(orgId, ['distributor_admin', 'branch_manager', 'warehouse_staff']);
  const [locations, warehouses] = await Promise.all([repo.stock.locations(orgId), repo.structure.warehouses(orgId)]);
  const visible = warehouses.filter((x) => x.active && locations.some((l) => l.warehouse_id === x.id));
  const warehouse = visible.find((x) => x.id === w) ?? visible[0];
  const base = `/distributor/${orgId}/fulfilment`;
  if (!warehouse?.id) return <><h1>Fulfilment</h1><p className="muted">No warehouse in your scope.</p></>;
  const whId = warehouse.id;

  const [skus, reserved, batches, shipments, carriers, awaiting, balances] = await Promise.all([
    skuMap(repo),
    repo.orders.allocations({ warehouseId: whId, statuses: ['reserved'] }),
    repo.fulfilment.batches([whId]),
    repo.fulfilment.shipments({ warehouseIds: [whId] }),
    repo.fulfilment.carriers(orgId),
    membership.role === 'warehouse_staff' ? Promise.resolve([]) : repo.orders.list({ distributorId: orgId, statuses: ['awaiting_split_decision'] }),
    repo.stock.balances(orgId),
  ]);
  const orderIds = [...new Set(reserved.map((a) => a.order_id))];
  const orders = await repo.orders.list({ distributorId: orgId, statuses: ['reserved', 'batched', 'packed', 'dispatched', 'partially_delivered', 'delivered', 'failed_delivery'] });
  const shops = await repo.organisations.byIds([...new Set([...orders, ...awaiting].map((o) => o.retailer_org_id ?? ''))]);
  const shopName = new Map(shops.map((s) => [s.id, s.name]));
  const orderShop = new Map(orders.map((o) => [o.id, shopName.get(o.retailer_org_id ?? '') ?? 'shop']));
  const carrierName = new Map(carriers.map((c) => [c.id, `${c.profiles?.full_name ?? 'carrier'} (${c.kind})`]));
  const activeShipmentByBatch = new Map(shipments.filter((s) => s.status !== 'cancelled').map((s) => [s.batch_id, s]));
  const items = (list: { sku_id: string; qty_pieces: number }[]) =>
    list.map((a) => `${skus.get(a.sku_id)?.code} × ${showQty(a.qty_pieces, skus.get(a.sku_id))}`).join(', ');

  return (
    <>
      <h1>Fulfilment</h1>
      <p>Warehouse: {visible.map((x) => (
        <Link key={x.id} href={`${base}?w=${x.id}`} style={{ marginRight: 12, fontWeight: x.id === whId ? 700 : 400 }}>{x.name}</Link>
      ))}</p>
      <Flash ok={ok} error={error} />

      {awaiting.length > 0 ? (
        <>
          <h2>Orders awaiting a split decision</h2>
          {awaiting.map((o) => {
            const decision = o.routing_decision as { penalty_m?: number; options?: { single?: unknown; split?: unknown } } | null;
            return (
              <div key={o.id} className="panel">
                <strong>{shopName.get(o.retailer_org_id ?? '')}</strong> · {o.routing_reason?.replaceAll('_', ' ')}
                {decision?.penalty_m ? <span className="muted"> · single source is {Math.round(decision.penalty_m / 1000)} km further</span> : null}
                <form action={decideSplit} className="inline" style={{ marginTop: 8 }}>
                  <input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="orderId" value={o.id ?? ''} /><input type="hidden" name="w" value={whId} />
                  {decision?.options?.single ? <button name="choice" value="single" className="secondary" type="submit">Single warehouse</button> : null}
                  {decision?.options?.split ? <button name="choice" value="split" type="submit">Split across warehouses</button> : null}
                </form>
              </div>
            );
          })}
        </>
      ) : null}

      <h2>Reserved, not yet batched ({orderIds.length} orders)</h2>
      {orderIds.length === 0 ? <p className="muted">Nothing waiting.</p> : (
        <form action={createBatch} className="panel">
          <input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="warehouseId" value={whId} />
          {orderIds.map((id) => (
            <label key={id} style={{ display: 'flex', gap: 8, color: 'inherit', fontSize: 'inherit' }}>
              <input type="checkbox" name="orderIds" value={id} defaultChecked />
              <span><strong>{orderShop.get(id)}</strong>: {items(reserved.filter((a) => a.order_id === id))}</span>
            </label>
          ))}
          <button type="submit" style={{ marginTop: 10 }}>Create batch</button>
        </form>
      )}

      <h2>Batches</h2>
      <div className="panel table-wrap"><table>
        <thead><tr><th>Created</th><th>Status</th><th>Shipment</th><th>Action</th></tr></thead>
        <tbody>{batches.map((b) => {
          const shipment = activeShipmentByBatch.get(b.id);
          return (
            <tr key={b.id}>
              <td>{new Date(b.created_at).toLocaleString('en-NG')}</td>
              <td><Status value={b.status} /></td>
              <td>{shipment ? <>{carrierName.get(shipment.carrier_location_id)} · <Status value={shipment.status} /></> : '–'}</td>
              <td>
                {b.status === 'open' ? (
                  <form action={markPacked}><input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="batchId" value={b.id} /><input type="hidden" name="w" value={whId} /><button type="submit">Mark packed</button></form>
                ) : null}
                {b.status === 'packed' && !shipment ? (
                  <form action={dispatchBatch} className="inline">
                    <input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="batchId" value={b.id} /><input type="hidden" name="w" value={whId} />
                    <select name="carrierUserId" required aria-label="Carrier">
                      {carriers.map((c) => <option key={c.id} value={c.user_id ?? ''}>{carrierName.get(c.id)}</option>)}
                    </select>
                    <button type="submit">Dispatch</button>
                  </form>
                ) : null}
              </td>
            </tr>
          );
        })}</tbody>
      </table></div>

      <h2>Returns</h2>
      <p className="muted">After every delivery on a shipment is recorded, count what the carrier brings back. The carrier confirms the count in their own app.</p>
      {shipments.filter((s) => s.status === 'open' || s.status === 'reconciling' || s.status === 'returning').map((s) => {
        const held = balances.filter((b) => b.location_id === s.carrier_location_id && b.on_hand > 0);
        return (
          <div key={s.id} className="panel">
            <strong>{carrierName.get(s.carrier_location_id)}</strong> · <Status value={s.status} />
            {s.status_note ? <div className="flash err">{s.status_note}</div> : null}
            <div className="muted">Carrier holds: {held.length ? held.map((b) => `${skus.get(b.sku_id)?.code} ${b.on_hand} pcs`).join(', ') : 'nothing'}</div>
            {s.status === 'open' ? (
              <form action={startReturn} className="inline" style={{ marginTop: 8 }}>
                <input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="shipmentId" value={s.id} /><input type="hidden" name="w" value={whId} />
                {held.map((b) => (
                  <label key={b.sku_id}>{skus.get(b.sku_id)?.code} returned (pcs)<input name={`r:${b.sku_id}`} inputMode="numeric" defaultValue="0" size={4} /></label>
                ))}
                <button type="submit">Record return count</button>
              </form>
            ) : null}
          </div>
        );
      })}
    </>
  );
}
