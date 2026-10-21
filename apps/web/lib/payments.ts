import 'server-only';
import { MockVirtualAccountProvider } from '@solus/integrations';
import { adapterRepository } from './supabase/admin';

/** Only the mock exists until a real adapter is verified against current partner docs (ADR-0008). */
export function paymentProvider(): MockVirtualAccountProvider {
  const name = process.env.PAYMENTS_PROVIDER ?? 'mock';
  if (name !== 'mock') throw new Error(`payments provider "${name}" is not implemented (ADR-0008)`);
  const secret = process.env.PAYMENTS_WEBHOOK_SECRET;
  if (!secret) throw new Error('PAYMENTS_WEBHOOK_SECRET is not set (npm run web:env)');
  return new MockVirtualAccountProvider(secret);
}

export async function ensureVirtualAccount(orgId: string, displayName: string) {
  const va = await paymentProvider().createAccount({ orgId, displayName });
  await adapterRepository().provisionVirtualAccount(orgId, va);
  return va;
}

/** Dev only: deliver a signed mock "transfer received" webhook to our own endpoint, exactly as the partner would. */
export async function simulateInboundTransfer(accountNumber: string, amountKobo: bigint, reference: string, eventId?: string) {
  const sim = paymentProvider().simulateTransfer({ accountNumber, amountKobo, reference, ...(eventId ? { eventId } : {}) });
  const base = process.env.WEBHOOK_BASE_URL ?? `http://localhost:${process.env.PORT ?? '3100'}`;
  const res = await fetch(`${base}/api/webhooks/payments/mock`, { method: 'POST', body: sim.rawBody, headers: { 'content-type': 'application/json', ...sim.headers } });
  return { status: res.status, result: ((await res.json()) as { result: string }).result, eventId: sim.eventId };
}
