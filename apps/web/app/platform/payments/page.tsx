import { notFound } from 'next/navigation';
import { formatNaira, kobo } from '@solus/core';
import { Flash, Shell, Status } from '@/components/shell';
import { requireSession } from '@/lib/session';
import { reconcile } from './actions';

export default async function PlatformPayments({ searchParams }: { searchParams: Promise<{ ok?: string; error?: string; r?: string }> }) {
  const { ok, error, r } = await searchParams;
  const { repo, memberships } = await requireSession();
  if (!memberships.some((m) => m.role === 'platform_admin' && m.status === 'active')) notFound();
  const events = await repo.finance.providerEvents();
  const result = r ? (JSON.parse(r) as Record<string, string[] | string>) : null;

  return (
    <Shell nav={[{ href: '/platform', label: 'Platform' }, { href: '/platform/payments', label: 'Payments' }]}>
      <h1>Payments</h1>
      <p className="muted">Webhook events from the partner, mirrored into the ledger. Solus never holds funds.</p>
      <Flash ok={ok} error={error} />
      <form action={reconcile} className="panel inline">
        <span>Reconcile the ledger against the partner's statement (mock provider statement for this server process).</span>
        <button type="submit">Run reconciliation</button>
      </form>
      {result ? (
        <div className="panel">
          <h2 style={{ marginTop: 0 }}>Reconciliation</h2>
          <ul>
            <li>Statement total {formatNaira(kobo(String(result['statement_total_kobo'] ?? '0')))} · ledger clearing balance {formatNaira(kobo(String(result['clearing_balance_kobo'] ?? '0')))}</li>
            <li>On the statement but not in the ledger (lost webhooks): {(result['missing_in_ledger'] as string[]).join(', ') || 'none'}</li>
            <li>In the ledger but not on this statement: {(result['missing_in_statement'] as string[]).length}</li>
            <li>Amount mismatches: {(result['amount_mismatch'] as string[]).join(', ') || 'none'}</li>
            <li>Unmatched account numbers: {(result['unmatched_accounts'] as string[]).join(', ') || 'none'}</li>
          </ul>
        </div>
      ) : null}
      <div className="panel table-wrap"><table>
        <thead><tr><th>Received</th><th>Event</th><th>Account</th><th>Amount</th><th>Status</th><th>Duplicates</th></tr></thead>
        <tbody>{events.map((e) => (
          <tr key={e.id}>
            <td>{new Date(e.received_at).toLocaleString('en-NG')}</td><td><code>{e.provider_event_id}</code><div className="muted">{e.reference}</div></td>
            <td>{e.account_number}</td><td>{formatNaira(kobo(e.amount_kobo ?? '0'))}</td>
            <td><Status value={e.status === 'posted' ? 'active' : 'pending'} /> {e.status}</td>
            <td>{e.duplicate_count}{e.hash_conflict ? ' (payload differed!)' : ''}</td>
          </tr>
        ))}</tbody>
      </table></div>
    </Shell>
  );
}
