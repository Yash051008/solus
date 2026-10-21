import Link from 'next/link';
import { Shell } from '@/components/shell';
import { requireSession } from '@/lib/session';
import { markAllRead } from './actions';

export default async function InboxPage() {
  const { repo } = await requireSession();
  const items = await repo.notifications.list();
  return (
    <Shell nav={[{ href: '/', label: 'Home' }]}>
      <h1>Inbox</h1>
      <form action={markAllRead}><button className="secondary" type="submit">Mark all as read</button></form>
      {items.length === 0 ? <p className="muted">Nothing yet.</p> : (
        <div className="panel"><ul style={{ listStyle: 'none', padding: 0, margin: 0 }}>
          {items.map((n) => (
            <li key={n.id} style={{ padding: '8px 0', borderBottom: '1px solid var(--line)', fontWeight: n.read_at ? 400 : 600 }}>
              {n.link ? <Link href={n.link}>{n.title}</Link> : n.title}
              {n.body ? <div className="muted" style={{ fontWeight: 400 }}>{n.body}</div> : null}
              <div className="muted" style={{ fontWeight: 400, fontSize: '.8rem' }}>{new Date(n.created_at).toLocaleString('en-NG')}</div>
            </li>
          ))}
        </ul></div>
      )}
    </Shell>
  );
}
