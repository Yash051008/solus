import Link from 'next/link';
import { getRepo } from '@/lib/supabase/server';
import { Icon } from './nav-links';

/** Inbox link with the unread count (server component; RLS keeps it to the viewer's own notifications). */
export async function InboxLink() {
  let unread = 0;
  try {
    unread = await (await getRepo()).notifications.unread();
  } catch {
    unread = 0;
  }
  return (
    <Link href="/inbox" className="navitem"><Icon name="inbox" /><span>Inbox</span>{unread ? <span className="count">{unread}</span> : null}</Link>
  );
}
