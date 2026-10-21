import { Flash, Status, type FlashParams } from '@/components/shell';
import { requireOrgRole } from '@/lib/session';
import { reply, resolve } from './actions';

export default async function DistributorSupport({ params, searchParams }: { params: Promise<{ orgId: string }>; searchParams: FlashParams }) {
  const { orgId } = await params;
  const { ok, error } = await searchParams;
  const { repo } = await requireOrgRole(orgId, ['distributor_admin', 'branch_manager']);
  const tickets = await repo.support.tickets({ distributorId: orgId });
  const [messages, shops] = await Promise.all([repo.support.messages(tickets.map((t) => t.id)), repo.organisations.byKind('retailer')]);
  const shopName = new Map(shops.map((s) => [s.id, s.name]));
  const open = tickets.filter((t) => t.status === 'open');
  return (
    <>
      <h1>Support ({open.length} open)</h1>
      <Flash ok={ok} error={error} />
      {tickets.map((t) => (
        <section key={t.id} className="panel">
          <strong>{t.subject}</strong> · {shopName.get(t.opener_org_id) ?? 'shop'} <Status value={t.status} />
          <span className="muted"> {t.category}{t.order_id ? ' · linked to an order' : ''}</span>
          <ul>{messages.filter((m) => m.ticket_id === t.id).map((m) => (
            <li key={m.id}><strong>{m.profiles?.full_name}:</strong> {m.body}</li>
          ))}</ul>
          {t.status === 'open' ? (
            <div className="grid">
              <form action={reply} className="inline"><input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="ticketId" value={t.id} />
                <input name="body" required placeholder="Reply" /><button className="secondary" type="submit">Reply</button></form>
              <form action={resolve} className="inline"><input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="ticketId" value={t.id} />
                <input name="resolution" required placeholder="Resolution" /><button type="submit">Resolve</button></form>
            </div>
          ) : <p className="muted">Resolved: {t.resolution}</p>}
        </section>
      ))}
    </>
  );
}
