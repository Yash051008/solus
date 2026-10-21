// SmsProvider (ADR-0006). Transactional messages only (OTPs). Implementations must use the provider's
// transactional/DND route; message bodies are never logged by callers.

export type SmsPurpose = 'handover' | 'return' | 'credit';

export type SmsMessage = { to: string; body: string; purpose: SmsPurpose; reference: string };

export type SmsResult = { provider: string; providerMessageId: string };

export interface SmsProvider {
  readonly name: string;
  send(message: SmsMessage): Promise<SmsResult>;
}

export class SmsProviderError extends Error {
  readonly retryable: boolean;
  constructor(message: string, retryable: boolean) {
    super(message);
    this.name = 'SmsProviderError';
    this.retryable = retryable;
  }
}

const E164 = /^\+[1-9][0-9]{7,14}$/;

export function validateSms(message: SmsMessage): void {
  if (!E164.test(message.to)) throw new RangeError('recipient must be an E.164 phone number');
  if (message.body.trim() === '' || message.body.length > 160) throw new RangeError('body must be 1-160 characters (one SMS segment)');
  if (message.reference.trim().length < 8) throw new RangeError('reference must be at least 8 characters');
}

const PURPOSE_TEXT: Record<SmsPurpose, string> = {
  handover: 'stock handover',
  return: 'stock return count',
  credit: 'credit purchase',
};

/** One-segment OTP text. The code is the only secret; we never include amounts or names. */
export function otpMessageBody(code: string, purpose: SmsPurpose): string {
  return `Solus code ${code} confirms your ${PURPOSE_TEXT[purpose]}. Valid 5 min. Only give it to the person completing it with you.`;
}
