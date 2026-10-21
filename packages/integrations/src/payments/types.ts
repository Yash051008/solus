// VirtualAccountProvider (ADR-0008). The platform never holds funds: accounts live at a licensed partner,
// money arrives by signed webhook, and amounts are normalised to integer kobo inside the adapter.

export type VirtualAccount = { provider: string; accountNumber: string; bankName: string; providerRef: string };

export type InboundTransfer = {
  provider: string;
  eventId: string;       // provider's unique event/transaction id (idempotency key)
  reference: string;     // narration/reference
  accountNumber: string; // the receiving virtual account
  amountKobo: string;    // integer kobo as a string (never a float)
  paidAt: string | null; // ISO-8601
};

export type StatementLine = { eventId: string; amountKobo: string };

export interface VirtualAccountProvider {
  readonly name: string;
  createAccount(input: { orgId: string; displayName: string }): Promise<VirtualAccount>;
  /** Must be called with the RAW request body, before any JSON parsing. */
  verifyWebhook(rawBody: string, headers: Record<string, string | undefined>): boolean;
  parseWebhook(rawBody: string): InboundTransfer | null;   // null = event type we ignore
  statement(): Promise<StatementLine[]>;
}

export class PaymentProviderError extends Error {
  readonly retryable: boolean;
  constructor(message: string, retryable: boolean) {
    super(message);
    this.name = 'PaymentProviderError';
    this.retryable = retryable;
  }
}
