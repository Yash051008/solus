import Link from 'next/link';
import { Flash, type FlashParams } from '@/components/shell';
import { signUp } from '../login/actions';

export default async function SignupPage({ searchParams }: { searchParams: FlashParams }) {
  const { ok, error } = await searchParams;
  return (
    <main className="auth">
      <h1>Create your account</h1>
      <p className="muted">After signing up you can register your shop, or ask to join a distributor as staff.</p>
      <Flash ok={ok} error={error} />
      <form action={signUp} className="stack panel">
        <label>Email<input name="email" type="email" autoComplete="email" required /></label>
        <label>Password (10+ characters)<input name="password" type="password" autoComplete="new-password" minLength={10} required /></label>
        <button type="submit">Create account</button>
      </form>
      <p>Already registered? <Link href="/login">Sign in</Link></p>
    </main>
  );
}
