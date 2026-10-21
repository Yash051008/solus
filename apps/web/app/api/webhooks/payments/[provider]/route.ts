// Payment partner webhook: a thin adapter. Signature check, normalisation and idempotent posting happen in
// handlePaymentWebhook + app.record_provider_event (ADR-0008).
import { handlePaymentWebhook } from '@solus/integrations';
import { adapterRepository } from '@/lib/supabase/admin';
import { paymentProvider } from '@/lib/payments';

export async function POST(request: Request, { params }: { params: Promise<{ provider: string }> }) {
  const { provider: name } = await params;
  const provider = paymentProvider();
  if (name !== provider.name) return new Response('unknown provider', { status: 404 });
  const rawBody = await request.text();
  const headers = Object.fromEntries(request.headers.entries());
  const outcome = await handlePaymentWebhook({ provider, record: adapterRepository().recordProviderEvent }, rawBody, headers);
  return Response.json({ result: outcome.result }, { status: outcome.httpStatus });
}
