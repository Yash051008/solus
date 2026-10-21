// Webhook adapter (server-side; the Next.js route is a one-line wrapper). Verify the signature on the raw
// body, normalise, hand to Postgres. Duplicates are 200 (stop retrying); DB failure is 500 (retry).
import { createHash } from 'node:crypto';
import type { InboundTransfer, VirtualAccountProvider } from './types.ts';

export type RecordProviderEvent = (t: InboundTransfer & { payloadHash: string }) =>
  Promise<{ status: 'posted' | 'duplicate' | 'unmatched'; hash_match?: boolean }>;

export type WebhookOutcome = { httpStatus: 200 | 401 | 400 | 500; result: string };

export async function handlePaymentWebhook(
  deps: { provider: VirtualAccountProvider; record: RecordProviderEvent },
  rawBody: string,
  headers: Record<string, string | undefined>,
): Promise<WebhookOutcome> {
  if (!deps.provider.verifyWebhook(rawBody, headers)) return { httpStatus: 401, result: 'bad_signature' };
  let transfer: InboundTransfer | null;
  try {
    transfer = deps.provider.parseWebhook(rawBody);
  } catch {
    return { httpStatus: 400, result: 'malformed' };
  }
  if (!transfer) return { httpStatus: 200, result: 'ignored' };
  try {
    const r = await deps.record({ ...transfer, payloadHash: createHash('sha256').update(rawBody).digest('hex') });
    return { httpStatus: 200, result: r.status === 'duplicate' && r.hash_match === false ? 'duplicate_hash_conflict' : r.status };
  } catch {
    return { httpStatus: 500, result: 'retry_later' };
  }
}
