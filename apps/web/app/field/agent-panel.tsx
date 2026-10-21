import { randomUUID } from 'node:crypto';
import { Status } from '@/components/shell';
import { LocationFields } from '@/components/location-fields';
import { getRepo } from '@/lib/supabase/server';
import { showQty, skuMap } from '@/lib/catalogue';
import { mockInbox } from '@/lib/sms';
import { recordSale, requestStock } from './agent-actions';

type PushShipment = { id: string; status: string; status_note: string | null; carrier_location_id: string } | null;

/** Agent view: request stock, receive the handover/return code (SMS), sell at shops in the territory. */
export async function AgentPanel({ orgId, userId, shipment }: { orgId: string; userId: string; shipment: PushShipment }) {
  const repo = await getRepo();
  const [skus, warehouses, requests, phone, retailers, balances] = await Promise.all([
    skuMap(repo), repo.structure.warehouses(orgId), repo.push.stockRequests({ agentUserId: userId }),
    repo.push.myPhone(userId), repo.organisations.byKind('retailer'),
    shipment ? repo.stock.balances(orgId) : Promise.resolve([]),
  ]);
  const carried = balances.filter((b) => b.location_id === shipment?.carrier_location_id && b.on_hand > 0);
  const [sms] = mockInbox(phone);
  const shops = retailers.filter((r) => r.status === 'active');
  const skuList = [...skus.values()].filter((s) => s.cartonPieces).sort((a, b) => a.code.localeCompare(b.code));

  return (
    <section className="panel">
      <h2 style={{ marginTop: 0 }}>My stock {shipment ? <Status value={shipment.status} /> : null}</h2>
      {sms && shipment && (shipment.status === 'awaiting_acceptance' || shipment.status === 'returning') ? (
        <div className="flash ok">SMS to your phone (dev mock): “{sms.body}”</div>
      ) : null}
      {shipment?.status_note ? <div className="flash err">{shipment.status_note}</div> : null}

      {!shipment ? (
        <form action={requestStock} className="inline">
          <input type="hidden" name="orgId" value={orgId} />
          <label>Warehouse<select name="warehouseId">{warehouses.filter((w) => w.active).map((w) => <option key={w.id} value={w.id ?? ''}>{w.name}</option>)}</select></label>
          <label>Product<select name="skuId">{skuList.map((s) => <option key={s.id} value={s.id}>{s.code}: {s.name}</option>)}</select></label>
          <label>Cartons<input name="cartons" inputMode="numeric" size={4} required /></label>
          <label>Note<input name="note" /></label>
          <button type="submit">Request stock</button>
        </form>
      ) : null}
      {shipment?.status === 'awaiting_acceptance' ? <p>Approved. Go to the warehouse: staff will count the stock with you and a code will be sent to your phone. Read it to them, in person only.</p> : null}

      {shipment?.status === 'open' ? (
        <>
          <p>Carrying: {carried.map((b) => `${skus.get(b.sku_id)?.code} ${showQty(b.on_hand, skus.get(b.sku_id))}`).join(', ') || 'nothing'}</p>
          <form action={recordSale} className="stack" style={{ maxWidth: 'none' }}>
            <input type="hidden" name="shipmentId" value={shipment.id} />
            <input type="hidden" name="idempotencyKey" value={`web:sale:${randomUUID()}`} />
            <label>Shop (you must be at the shop)<select name="retailerOrgId">{shops.map((r) => <option key={r.id} value={r.id ?? ''}>{r.name}</option>)}</select></label>
            {carried.map((b) => (
              <label key={b.sku_id}>{skus.get(b.sku_id)?.name}: pieces sold (carrying {b.on_hand})<input name={`s:${b.sku_id}`} inputMode="numeric" defaultValue="0" /></label>
            ))}
            <LocationFields />
            <button type="submit">Record cash sale</button>
          </form>
        </>
      ) : null}

      <h3>My requests</h3>
      <ul>{requests.slice(0, 5).map((r) => (
        <li key={r.id}><Status value={r.status} /> {r.stock_request_lines.map((l) => `${skus.get(l.sku_id)?.code} ${l.qty_approved ?? l.qty_pieces} pcs`).join(', ')}
          {r.decision_reason ? <span className="muted"> · {r.decision_reason}</span> : null}</li>
      ))}</ul>
      <p className="muted">Sales are valued at the distributor's piece price and recorded as cash you hold until you remit it.</p>
    </section>
  );
}
