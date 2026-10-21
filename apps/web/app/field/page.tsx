import { formatNaira, kobo } from '@solus/core';
import { Flash, Shell, Status, type FlashParams } from '@/components/shell';
import { LocationFields } from '@/components/location-fields';
import { requireSession } from '@/lib/session';
import { showQty, skuMap } from '@/lib/catalogue';
import { acceptShipment, confirmReturn, declineShipment, recordDelivery } from './actions';
import { AgentPanel } from './agent-panel';

export default async function FieldPage({ searchParams }: { searchParams: FlashParams }) {
  const { ok, error } = await searchParams;
  const { repo, userId, memberships } = await requireSession();
  const field = memberships.filter((m) => (m.role === 'agent' || m.role === 'driver') && m.status === 'active');
  const locations = await repo.fulfilment.myCarrierLocations(userId);
  const allShipments = (await repo.fulfilment.shipments({ carrierLocationIds: locations.map((l) => l.id) }))
    .filter((s) => s.status !== 'cancelled' && s.status !== 'closed');
  const shipments = allShipments.filter((s) => s.kind === 'delivery');
  const agentOrg = field.find((m) => m.role === 'agent');
  const batchIds = shipments.map((s) => s.batch_id).filter((b): b is string => b !== null);
  const allocations = (await Promise.all(batchIds.map((b) => repo.orders.allocations({ batchId: b })))).flat();
  const orderIds = [...new Set(allocations.map((a) => a.order_id))];
  const [skus, orders, deliveries] = await Promise.all([
    skuMap(repo), repo.orders.list({}), repo.fulfilment.deliveries(orderIds),
  ]);
  const shops = await repo.organisations.byIds([...new Set(orders.filter((o) => orderIds.includes(o.id ?? '')).map((o) => o.retailer_org_id ?? ''))]);
  const shopOf = (orderId: string) => shops.find((s) => s.id === orders.find((o) => o.id === orderId)?.retailer_org_id);

  return (
    <Shell nav={[{ href: '/field', label: 'Field' }]}>
      <h1>Field</h1>
      <p className="muted">{field.map((m) => `${m.role} at ${m.orgName}`).join(' · ')}. The offline field app arrives in Phase 5b.</p>
      <Flash ok={ok} error={error} />
      {agentOrg ? <AgentPanel orgId={agentOrg.orgId} userId={userId} shipment={allShipments.find((s) => s.kind === 'push') ?? null} /> : null}
      <h2>Deliveries</h2>
      {shipments.length === 0 ? <p className="muted">No delivery assigned to you.</p> : shipments.map((s) => {
        const mine = allocations.filter((a) => a.batch_id === s.batch_id);
        const ordersInShipment = [...new Set(mine.map((a) => a.order_id))];
        return (
          <section key={s.id} className="panel">
            <h2 style={{ marginTop: 0 }}>Shipment <Status value={s.status} /></h2>
            {s.status_note ? <div className="flash err">{s.status_note}</div> : null}

            {s.status === 'awaiting_acceptance' ? (
              <>
                <ul>{mine.map((a) => <li key={a.id}>{skus.get(a.sku_id)?.name}: {showQty(a.qty_pieces, skus.get(a.sku_id))}</li>)}</ul>
                <p>Count the goods with the warehouse before accepting. Accepting makes you responsible for them.</p>
                <div className="grid">
                  <form action={acceptShipment}><input type="hidden" name="shipmentId" value={s.id} /><button type="submit">Accept shipment</button></form>
                  <form action={declineShipment} className="inline"><input type="hidden" name="shipmentId" value={s.id} />
                    <label>Reason<input name="reason" required /></label><button className="secondary" type="submit">Decline</button></form>
                </div>
              </>
            ) : null}

            {s.status === 'open' ? ordersInShipment.map((orderId) => {
              const shop = shopOf(orderId);
              const done = deliveries.find((d) => d.order_id === orderId);
              const lines = mine.filter((a) => a.order_id === orderId);
              return (
                <div key={orderId} className="panel">
                  <strong>{shop?.name ?? 'Shop'}</strong>
                  {shop?.lat ? <span className="muted"> · {shop.lat.toFixed(5)}, {shop.lng?.toFixed(5)}</span> : null}
                  {done ? (
                    <p>Delivered · invoiced {formatNaira(kobo(done.invoiced_kobo ?? '0'))} · geofence {done.geofence_ok ? 'OK' : `FAILED (${done.geofence_reason})`}</p>
                  ) : (
                    <form action={recordDelivery} className="stack" style={{ maxWidth: 'none' }}>
                      <input type="hidden" name="shipmentId" value={s.id} /><input type="hidden" name="orderId" value={orderId} />
                      <div className="table-wrap"><table>
                        <thead><tr><th>Item (pieces)</th><th>Delivered</th><th>Refused</th><th>Damaged</th><th>Missing</th></tr></thead>
                        <tbody>{lines.map((a) => (
                          <tr key={a.id}>
                            <td>{skus.get(a.sku_id)?.name}<div className="muted">{a.qty_pieces} pcs ({showQty(a.qty_pieces, skus.get(a.sku_id))})</div></td>
                            {(['delivered', 'refused', 'damaged', 'missing'] as const).map((f) => (
                              <td key={f}><input name={`${f}:${a.id}`} inputMode="numeric" size={4} defaultValue={f === 'delivered' ? a.qty_pieces : 0} aria-label={`${f} ${skus.get(a.sku_id)?.code}`} /></td>
                            ))}
                          </tr>
                        ))}</tbody>
                      </table></div>
                      <label>Received by (name)<input name="recipientName" required /></label>
                      <label>Photo of the delivered goods (not people's faces)
                        <input name="photo" type="file" accept="image/jpeg,image/png,image/webp" capture="environment" required />
                      </label>
                      <LocationFields />
                      <button type="submit">Record delivery</button>
                    </form>
                  )}
                </div>
              );
            }) : null}

            {s.status === 'returning' ? (
              <form action={confirmReturn}>
                <input type="hidden" name="shipmentId" value={s.id} />
                <p>The warehouse has counted your return. Confirm only if the count is right.</p>
                <button type="submit">Confirm return count</button>
              </form>
            ) : null}
          </section>
        );
      })}
    </Shell>
  );
}
