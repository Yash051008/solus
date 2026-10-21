import { randomUUID } from 'node:crypto';
import { formatNaira, kobo } from '@solus/core';
import { Flash, Shell, type FlashParams } from '@/components/shell';
import { requireOrgRole } from '@/lib/session';
import { createAccount, repayCredit, simulateTopUp } from './actions';

const nav = (orgId: string, name: string) => [
  { href: `/retailer/${orgId}`, label: name }, { href: `/retailer/${orgId}/order`, label: 'Order' },
  { href: `/retailer/${orgId}/orders`, label: 'My orders' }, { href: `/retailer/${orgId}/wallet`, label: 'Wallet' },
];

const JOURNAL_TEXT: Record<string, string> = {
  va_inflow: 'Transfer received', settle_wallet: 'Order paid from wallet', settle_credit: 'Order paid on credit',
  split_payment: 'Order paid (wallet + credit)', credit_repaid: 'Credit repaid', delivery_invoiced: 'Goods delivered',
  cash_collected: 'Cash paid to driver',
};

export default async function WalletPage({ params, searchParams }: { params: Promise<{ orgId: string }>; searchParams: FlashParams }) {
  const { orgId } = await params;
  const { ok, error } = await searchParams;
  const { repo, membership } = await requireOrgRole(orgId, ['retailer']);
  const [va, accounts, positions, distributors] = await Promise.all([
    repo.finance.virtualAccount(orgId), repo.finance.balances(), repo.finance.creditPositions({ retailerOrgId: orgId }),
    repo.organisations.byKind('distributor'),
  ]);
  const wallet = accounts.find((a) => a.account_type === 'wallet' && a.holder_org_id === orgId);
  const walletKobo = -BigInt(wallet?.account_balances?.balance_kobo ?? '0');
  const entries = await repo.finance.entries(accounts.map((a) => a.id));
  const accountType = new Map(accounts.map((a) => [a.id, a.account_type]));
  const distName = new Map(distributors.map((d) => [d.id, d.name]));

  return (
    <Shell nav={nav(orgId, membership.orgName)}>
      <h1>Wallet</h1>
      <Flash ok={ok} error={error} />
      <div className="grid">
        <section className="panel">
          <h2 style={{ marginTop: 0 }}>Balance</h2>
          <p style={{ fontSize: '1.8rem', margin: 0 }}>{formatNaira(kobo(walletKobo))}</p>
          <p className="muted">Held at our licensed partner bank. Solus never holds your money.</p>
        </section>
        <section className="panel">
          <h2 style={{ marginTop: 0 }}>Your account number</h2>
          {va ? (
            <>
              <p style={{ fontSize: '1.4rem', margin: 0 }}><code>{va.account_number}</code></p>
              <p className="muted">{va.bank_name}. Transfer from any bank app to top up.</p>
              {va.provider === 'mock' ? (
                <form action={simulateTopUp} className="inline">
                  <input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="accountNumber" value={va.account_number} />
                  <label>Dev: simulate a transfer (₦)<input name="naira" inputMode="decimal" defaultValue="5000" size={8} /></label>
                  <button className="secondary" type="submit">Send test transfer</button>
                </form>
              ) : null}
            </>
          ) : (
            <form action={createAccount}><input type="hidden" name="orgId" value={orgId} /><button type="submit">Create my account number</button></form>
          )}
        </section>
      </div>

      <h2>Trade credit</h2>
      <div className="panel table-wrap"><table>
        <thead><tr><th>Distributor</th><th>Limit</th><th>Used</th><th>Available</th><th>Owed on deliveries</th><th>Repay from wallet</th></tr></thead>
        <tbody>{positions.map((p) => {
          const limit = BigInt(p.credit_limit_kobo ?? '0'); const drawn = BigInt(p.drawn_kobo ?? '0');
          return (
            <tr key={p.relationship_id}>
              <td>{distName.get(p.distributor_org_id ?? '')}</td><td>{formatNaira(kobo(limit))}</td><td>{formatNaira(kobo(drawn))}</td>
              <td>{formatNaira(kobo(limit - drawn))}</td><td>{formatNaira(kobo(p.receivable_kobo ?? '0'))}</td>
              <td>{drawn > 0n ? (
                <form action={repayCredit} className="inline">
                  <input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="distributorId" value={p.distributor_org_id ?? ''} />
                  <input type="hidden" name="idempotencyKey" value={`web:repay:${randomUUID()}`} />
                  <input name="naira" inputMode="decimal" size={8} aria-label="Amount in naira" required />
                  <button type="submit">Repay</button>
                </form>
              ) : '–'}</td>
            </tr>
          );
        })}</tbody>
      </table></div>

      <h2>Statement</h2>
      <div className="panel table-wrap"><table>
        <thead><tr><th>Date</th><th>What</th><th>Account</th><th>Amount</th></tr></thead>
        <tbody>{entries.map((e) => (
          <tr key={e.id}>
            <td>{new Date(e.created_at).toLocaleString('en-NG')}</td>
            <td>{JOURNAL_TEXT[e.journals?.journal_type ?? ''] ?? e.journals?.journal_type}</td>
            <td className="muted">{(accountType.get(e.account_id) ?? '').replace('_', ' ')}</td>
            <td>{formatNaira(kobo(e.amount_kobo ?? '0'))}</td>
          </tr>
        ))}</tbody>
      </table></div>
      <p className="muted">Amounts are shown as ledger debits (+) and credits (−) on each account.</p>
    </Shell>
  );
}
