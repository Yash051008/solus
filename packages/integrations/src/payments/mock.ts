// Mock partner: deterministic 10-digit account numbers ('99' + 8 digits from sha256(orgId), matching the
// SQL seed), HMAC-SHA512 webhook signatures in `x-mock-signature` (the scheme Paystack reportedly uses),
// and an in-memory statement of every transfer it "received".
import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import type { InboundTransfer, StatementLine, VirtualAccount, VirtualAccountProvider } from './types.ts';

type MockEvent = { event: 'transfer.received'; data: { id: string; reference: string; account_number: string; amount_kobo: number | string; paid_at: string } };

const store = globalThis as typeof globalThis & { __solusMockStatement?: StatementLine[] };
const statementLines: StatementLine[] = (store.__solusMockStatement ??= []);

export function mockAccountNumber(orgId: string): string {
  const n = Number.parseInt(createHash('sha256').update(orgId, 'utf8').digest('hex').slice(0, 8), 16) % 100_000_000;
  return `99${String(n).padStart(8, '0')}`;
}

export class MockVirtualAccountProvider implements VirtualAccountProvider {
  readonly name = 'mock';
  private readonly secret: string;
  constructor(secret: string) {
    if (secret.length < 16) throw new RangeError('webhook secret must be at least 16 characters');
    this.secret = secret;
  }

  async createAccount(input: { orgId: string; displayName: string }): Promise<VirtualAccount> {
    return { provider: this.name, accountNumber: mockAccountNumber(input.orgId), bankName: 'Mock Bank', providerRef: `mock-va-${input.orgId}` };
  }

  sign(rawBody: string): string {
    return createHmac('sha512', this.secret).update(rawBody, 'utf8').digest('hex');
  }

  verifyWebhook(rawBody: string, headers: Record<string, string | undefined>): boolean {
    const given = headers['x-mock-signature'];
    if (!given || !/^[0-9a-f]{128}$/.test(given)) return false;
    return timingSafeEqual(Buffer.from(this.sign(rawBody), 'hex'), Buffer.from(given, 'hex'));
  }

  parseWebhook(rawBody: string): InboundTransfer | null {
    const body = JSON.parse(rawBody) as MockEvent;
    if (body.event !== 'transfer.received') return null;
    const amount = String(body.data.amount_kobo);
    if (!/^[1-9]\d*$/.test(amount)) throw new RangeError('amount_kobo must be a positive integer');
    return { provider: this.name, eventId: body.data.id, reference: body.data.reference, accountNumber: body.data.account_number,
             amountKobo: amount, paidAt: body.data.paid_at ?? null };
  }

  async statement(): Promise<StatementLine[]> {
    return [...statementLines];
  }

  /** Dev/test: build a signed "transfer received" webhook (and add it to the partner's statement). */
  simulateTransfer(input: { accountNumber: string; amountKobo: bigint; reference: string; eventId?: string }) {
    const eventId = input.eventId ?? `mock-${createHash('sha256').update(`${input.accountNumber}:${input.reference}:${Date.now()}:${Math.random()}`).digest('hex').slice(0, 16)}`;
    const rawBody = JSON.stringify({ event: 'transfer.received', data: { id: eventId, reference: input.reference, account_number: input.accountNumber,
                                                                         amount_kobo: input.amountKobo.toString(), paid_at: new Date().toISOString() } });
    if (!statementLines.some((l) => l.eventId === eventId)) statementLines.push({ eventId, amountKobo: input.amountKobo.toString() });
    return { rawBody, headers: { 'x-mock-signature': this.sign(rawBody) }, eventId };
  }
}
