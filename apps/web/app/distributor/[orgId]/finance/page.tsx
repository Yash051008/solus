import { formatNaira, kobo } from '@solus/core';
import { Flash, type FlashParams } from '@/components/shell';
import { requireOrgRole } from '@/lib/session';
import { allocateReceipt, setCreditLimit } from './actions';

export default async function FinancePage({ params, searchParams }: { params: Promise<{ orgId: string }>; searchParams: FlashParams }) {
  const { orgId } = await params;
  const { ok, error } = await searchParams;
  const { repo } = await requireOrgRole(orgId, ['distributor_admin']);
  const [positions, accounts, events, allocations, retailers, carriers, va] = await Promise.all([
    repo.finance.creditPositions({ distributorId: orgId }), repo.finance.balances(), repo.finance.providerEvents(orgId),
    repo.finance.allocations(orgId), repo.organisations.byKind('retailer'), repo.fulfilment.carriers(orgId), repo.finance.virtualAccount(orgId),
  ]);
  const shopName = new Map(retailers.map((r) => [r.id, r.name]));
  const bal = (a: (typeof accounts)[number]) => BigInt(a.account_balances?.balance_kobo ?? '0');
  const book = accounts.filter((a) => a.book_org_id === orgId);
  const sum = (type: string) => book.filter((a) => a.account_type === type).reduce((s, a) => s + bal(a), 0n);
  const walletD = accounts.find((a) => a.account_type === 'wallet' && a.holder_org_id === orgId);
  const cash = book.filter((a) => a.account_type === 'cash_in_transit' && bal(a) !== 0n);
  const carrierName = new Map(carriers.map((c) => [c.user_id, c.profiles?.full_name ?? 'carrier']));
  const allocated = new Map<string, bigint>();
  for (const a of allocations) allocated.set(a.provider_event_id, (allocated.get(a.provider_event_id) ?? 0n) + BigInt(a.amount_kobo ?? '0'));
  const open = events.filter((e) => e.status === 'posted' && BigInt(e.amount_kobo ?? '0') > (allocated.get(e.id) ?? 0n));

  return (
    <>
      <h1>Finance</h1>
      <Flash ok={ok} error={error} />
      <div className="grid">
        <div className="panel"><div className="muted">Funds at partner bank</div><strong>{formatNaira(kobo(-BigInt(walletD?.account_balances?.balance_kobo ?? '0')))}</strong>
          {va ? <div className="muted">Account {va.account_number} · {va.bank_name}</div> : null}</div>
        <div className="panel"><div className="muted">Owed by shops (deliveries)</div><strong>{formatNaira(kobo(sum('receivables')))}</strong></div>
        <div className="panel"><div className="muted">Trade credit drawn</div><strong>{formatNaira(kobo(sum('trade_credit')))}</strong></div>
        <div className="panel"><div className="muted">Cash held by field staff</div><strong>{formatNaira(kobo(sum('cash_in_transit')))}</strong></div>
        <div className="panel"><div className="muted">Received, not yet allocated</div><strong>{formatNaira(kobo(-sum('unallocated_receipts')))}</strong></div>
        <div className="panel"><div className="muted">Revenue recognised</div><strong>{formatNaira(kobo(-sum('sales_revenue')))}</strong></div>
      </div>

      <h2>Unallocated receipts</h2>
      <p className="muted">Transfers into your account (e.g. agents remitting cash). Allocate each to the agent's cash or a shop's debt.</p>
      {open.length === 0 ? <p className="muted">Nothing to allocate.</p> : open.map((e) => {
        const remaining = BigInt(e.amount_kobo ?? '0') - (allocated.get(e.id) ?? 0n);
        return (
          <form key={e.id} action={allocateReceipt} className="panel inline">
            <input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="eventId" value={e.id} />
            <span><strong>{formatNaira(kobo(remaining))}</strong> of {formatNaira(kobo(e.amount_kobo ?? '0'))} · “{e.reference}” · {new Date(e.received_at).toLocaleString('en-NG')}</span>
            <label>Allocate to
              <select name="target" required>
                {cash.map((a) => <option key={a.id} value={`agent_cash:${a.counterparty_user_id}`}>{carrierName.get(a.counterparty_user_id ?? '') ?? 'agent'} cash ({formatNaira(kobo(bal(a)))})</option>)}
                {positions.filter((p) => BigInt(p.receivable_kobo ?? '0') > 0n).map((p) => (
                  <option key={p.relationship_id} value={`shop_debt:${p.retailer_org_id}`}>{shopName.get(p.retailer_org_id ?? '')} debt ({formatNaira(kobo(p.receivable_kobo ?? '0'))})</option>
                ))}
              </select>
            </label>
            <label>₦<input name="naira" inputMode="decimal" size={10} required /></label>
            <button type="submit">Allocate</button>
          </form>
        );
      })}

      <h2>Customer credit</h2>
      <div className="panel table-wrap"><table>
        <thead><tr><th>Shop</th><th>Limit</th><th>Drawn</th><th>Owed on deliveries</th><th>Set limit (₦)</th></tr></thead>
        <tbody>{positions.map((p) => (
          <tr key={p.relationship_id}>
            <td>{shopName.get(p.retailer_org_id ?? '')}</td><td>{formatNaira(kobo(p.credit_limit_kobo ?? '0'))}</td>
            <td>{formatNaira(kobo(p.drawn_kobo ?? '0'))}</td><td>{formatNaira(kobo(p.receivable_kobo ?? '0'))}</td>
            <td><form action={setCreditLimit} className="inline">
              <input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="relationshipId" value={p.relationship_id ?? ''} />
              <input name="naira" inputMode="decimal" size={10} required aria-label="New limit in naira" /><button className="secondary" type="submit">Set</button>
            </form></td>
          </tr>
        ))}</tbody>
      </table></div>
    </>
  );
}
