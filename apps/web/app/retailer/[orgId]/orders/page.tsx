import { formatNaira, kobo } from '@solus/core';
import { Flash, Shell, Status, type FlashParams } from '@/components/shell';
import { requireOrgRole } from '@/lib/session';
import { showQty, skuMap } from '@/lib/catalogue';
import { randomUUID } from 'node:crypto';
import { mockInbox } from '@/lib/sms';
import { cancelOrder, confirmDelivery, disputeDelivery, startPayment, verifyPayment } from './actions';

const CANCELLABLE = new Set(['placed', 'awaiting_split_decision', 'reserved', 'batched', 'packed']);
const DELIVERED = new Set(['delivered', 'partially_delivered', 'failed_delivery']);

export default async function MyOrdersPage({ params, searchParams }: {
  params: Promise<{ orgId: string }>;
  searchParams: Promise<{ ok?: string; error?: string; challenge?: string; order?: string }>;
}) {
  const { orgId } = await params;
  const { ok, error, challenge, order: challengeOrder } = await searchParams;
  const { repo, membership } = await requireOrgRole(orgId, ['retailer']);
  const orders = await repo.orders.list({ retailerOrgId: orgId });
  const ids = orders.map((o) => o.id ?? '');
  const [skus, lines, deliveries, phone] = await Promise.all([skuMap(repo), repo.orders.lines(ids), repo.fulfilment.deliveries(ids),
    repo.me.userId().then((u) => (u ? repo.push.myPhone(u) : null))]);
  const delivered = orders.filter((o) => deliveries.some((d) => d.order_id === o.id) && o.status !== 'settled');
  const dues = new Map(await Promise.all(delivered.map(async (o) => [o.id ?? '', BigInt(String(await repo.finance.amountDue(o.id ?? '')))] as const)));
  const [sms] = challenge ? mockInbox(phone) : [];

  return (
    <Shell nav={[{ href: `/retailer/${orgId}`, label: membership.orgName }, { href: `/retailer/${orgId}/order`, label: 'Order' }, { href: `/retailer/${orgId}/orders`, label: 'My orders' }, { href: `/retailer/${orgId}/wallet`, label: 'Wallet' }]}>
      <h1>My orders</h1>
      <Flash ok={ok} error={error} />
      {orders.length === 0 ? <p className="muted">No orders yet.</p> : orders.map((o) => {
        const delivery = deliveries.find((d) => d.order_id === o.id);
        return (
          <section key={o.id} className="panel">
            <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'center' }}>
              <strong>{new Date(o.created_at ?? '').toLocaleString('en-NG')}</strong>
              <Status value={o.status ?? 'placed'} />
              <span>Total {formatNaira(kobo(o.total_kobo ?? '0'))}</span>
              {o.placed_by_role === 'agent' ? <span className="muted">placed by your agent</span> : null}
            </div>
            <ul>{lines.filter((l) => l.order_id === o.id).map((l) => (
              <li key={l.id}>{skus.get(l.sku_id)?.name}: {showQty(l.qty_pieces, skus.get(l.sku_id))} · {formatNaira(kobo(l.line_amount_kobo ?? '0'))}</li>
            ))}</ul>
            {o.status === 'rejected' ? <p className="muted">Not enough stock across the distributor's warehouses.</p> : null}
            {o.cancelled_reason ? <p className="muted">Cancelled: {o.cancelled_reason}</p> : null}
            {delivery ? <p>Delivered value invoiced: <strong>{formatNaira(kobo(delivery.invoiced_kobo ?? '0'))}</strong>
              {dues.get(o.id ?? '') !== undefined ? <> · amount due <strong>{formatNaira(kobo(dues.get(o.id ?? '') ?? 0n))}</strong></> : null}</p> : null}
            {challenge && challengeOrder === o.id ? (
              <form action={verifyPayment} className="inline panel">
                <input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="challengeId" value={challenge} /><input type="hidden" name="orderId" value={o.id ?? ''} />
                {sms ? <div className="flash ok" style={{ width: '100%' }}>SMS to your phone (dev mock): “{sms.body}”</div> : null}
                <label>Code sent to your phone to confirm the credit<input name="code" inputMode="numeric" pattern="\d{6}" required /></label>
                <button type="submit">Confirm payment</button>
              </form>
            ) : (dues.get(o.id ?? '') ?? 0n) > 0n ? (
              <form action={startPayment} className="inline">
                <input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="orderId" value={o.id ?? ''} />
                <input type="hidden" name="idempotencyKey" value={`web:pay:${randomUUID()}`} />
                <label>From wallet (₦)<input name="wallet" inputMode="decimal" size={8} defaultValue="0" /></label>
                <label>On credit (₦)<input name="credit" inputMode="decimal" size={8} defaultValue="0" /></label>
                <button type="submit">Pay</button>
              </form>
            ) : null}
            <div className="grid">
              {CANCELLABLE.has(o.status ?? '') ? (
                <form action={cancelOrder} className="inline">
                  <input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="orderId" value={o.id ?? ''} />
                  <label>Reason<input name="reason" required /></label>
                  <button className="danger" type="submit">Cancel order</button>
                </form>
              ) : null}
              {DELIVERED.has(o.status ?? '') && !o.confirmed_at ? (
                <>
                  <form action={confirmDelivery}>
                    <input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="orderId" value={o.id ?? ''} />
                    <button type="submit">Confirm delivery</button>
                  </form>
                  <form action={disputeDelivery} className="inline">
                    <input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="orderId" value={o.id ?? ''} />
                    <label>What was wrong?<input name="reason" required minLength={3} /></label>
                    <button className="secondary" type="submit">Report a problem</button>
                  </form>
                </>
              ) : null}
              {o.confirmed_at ? <span className="muted">Confirmed {new Date(o.confirmed_at).toLocaleDateString('en-NG')}</span> : null}
            </div>
          </section>
        );
      })}
    </Shell>
  );
}
