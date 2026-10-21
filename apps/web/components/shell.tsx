import Link from 'next/link';
import { signOut } from '@/app/login/actions';
import { InboxLink } from './inbox-link';
import { Icon, NavLinks } from './nav-links';

export function Shell({ nav, children }: { nav?: { href: string; label: string }[]; children: React.ReactNode }) {
  return (
    <div className="app">
      <aside className="sidebar">
        <Link href="/" className="brand"><span className="logo">S</span><span>Solus</span></Link>
        <nav className="navlist"><NavLinks nav={nav ?? []} /></nav>
        <div className="navfoot">
          <InboxLink />
          <Link href="/support" className="navitem"><Icon name="support" /><span>Help</span></Link>
          <form action={signOut}><button className="secondary signout" type="submit">Sign out</button></form>
        </div>
      </aside>
      <main className="content">{children}</main>
    </div>
  );
}

export function Flash({ ok, error }: { ok?: string | undefined; error?: string | undefined }) {
  return (
    <>
      {ok ? <div className="flash ok" role="status">{ok}</div> : null}
      {error ? <div className="flash err" role="alert">{error}</div> : null}
    </>
  );
}

export function Status({ value }: { value: string }) {
  return <span className={`badge ${value}`}>{value.replaceAll('_', ' ')}</span>;
}

export type FlashParams = Promise<{ ok?: string; error?: string }>;
