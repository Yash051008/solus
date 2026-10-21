import Link from 'next/link';
import { signOut } from '@/app/login/actions';

export function Shell({ nav, children }: { nav?: { href: string; label: string }[]; children: React.ReactNode }) {
  return (
    <>
      <header className="top">
        <Link href="/" className="brand">Solus</Link>
        <nav>
          {(nav ?? []).map((n) => <Link key={n.href} href={n.href}>{n.label}</Link>)}
        </nav>
        <form action={signOut}><button className="secondary" type="submit">Sign out</button></form>
      </header>
      <main>{children}</main>
    </>
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
