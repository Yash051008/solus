import Link from 'next/link';
import { Flash, type FlashParams } from '@/components/shell';
import { signIn } from './actions';

export default async function LoginPage({ searchParams }: { searchParams: FlashParams }) {
  const { ok, error } = await searchParams;
  return (
    <main>
      <h1>Sign in to Solus</h1>
      <p className="muted">Distributors, branch staff, retailers and platform administrators.</p>
      <Flash ok={ok} error={error} />
      <form action={signIn} className="stack panel">
        <label>Email<input name="email" type="email" autoComplete="email" required /></label>
        <label>Password<input name="password" type="password" autoComplete="current-password" required /></label>
        <button type="submit">Sign in</button>
      </form>
      <p>New here? <Link href="/signup">Create an account</Link></p>
    </main>
  );
}
