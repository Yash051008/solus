import { Flash, Shell, Status, type FlashParams } from '@/components/shell';
import { requireSession } from '@/lib/session';
import { openTicket, replyTicket } from './actions';

/** Tickets raised by the viewer's organisations (shops mostly). Distributors handle theirs under /distributor/[id]/support. */
export default async function SupportPage({ searchParams }: { searchParams: FlashParams }) {
  const { ok, error } = await searchParams;
  const { repo, memberships } = await requireSession();
  const myOrgs = memberships.filter((m) => m.status === 'active');
  const shops = myOrgs.filter((m) => m.role === 'retailer');
  const tickets = await repo.support.tickets({ openerOrgIds: myOrgs.map((m) => m.orgId) });
  const messages = await repo.support.messages(tickets.map((t) => t.id));
  const relationships = shops[0] ? (await repo.retailer.relationships(shops[0].orgId)).filter((r) => r.status === 'active') : [];

  return (
    <Shell nav={[{ href: '/', label: 'Home' }]}>
      <h1>Support</h1>
      <Flash ok={ok} error={error} />
      {shops[0] && relationships.length > 0 ? (
        <form action={openTicket} className="panel stack">
          <h2 style={{ marginTop: 0 }}>Open a ticket</h2>
          <input type="hidden" name="orgId" value={shops[0].orgId} />
          <label>Distributor<select name="distributorId">{relationships.map((r) => <option key={r.id} value={r.distributor_org_id}>{r.organisations?.name}</option>)}</select></label>
          <label>Topic<select name="category"><option value="delivery">Delivery</option><option value="payment">Payment</option><option value="stock">Products / stock</option><option value="account">Account</option><option value="other">Other</option></select></label>
          <label>Subject<input name="subject" required minLength={3} /></label>
          <label>Message<textarea name="body" required /></label>
          <button type="submit">Send</button>
        </form>
      ) : null}
      <h2>My tickets</h2>
      {tickets.length === 0 ? <p className="muted">No tickets.</p> : tickets.map((t) => (
        <section key={t.id} className="panel">
          <strong>{t.subject}</strong> <Status value={t.status} /> <span className="muted">{t.category}</span>
          <ul>{messages.filter((m) => m.ticket_id === t.id).map((m) => (
            <li key={m.id}><strong>{m.profiles?.full_name}:</strong> {m.body} <span className="muted">{new Date(m.created_at).toLocaleString('en-NG')}</span></li>
          ))}</ul>
          {t.resolution ? <p>Resolution: {t.resolution}</p> : (
            <form action={replyTicket} className="inline"><input type="hidden" name="ticketId" value={t.id} />
              <input name="body" required placeholder="Reply" style={{ flex: 1 }} /><button className="secondary" type="submit">Reply</button></form>
          )}
        </section>
      ))}
    </Shell>
  );
}
