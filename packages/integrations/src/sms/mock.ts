// Mock SMS provider for tests and local dev. Messages go to an in-memory inbox (per process), which the
// dev UI reads to show the recipient "their SMS". Never use in production: there is no real delivery.
// Numbers ending in 9 simulate a retryable provider outage.
import { createHash } from 'node:crypto';
import type { SmsMessage, SmsProvider, SmsResult } from './types.ts';
import { SmsProviderError, validateSms } from './types.ts';

type InboxEntry = SmsMessage & { providerMessageId: string; sentAt: Date };
// On globalThis: bundlers (e.g. Next.js server actions vs. page rendering) may load this module more than
// once in the same process, and the dev inbox must be shared between those copies.
const store = globalThis as typeof globalThis & { __solusMockSmsInbox?: InboxEntry[] };
const inbox: InboxEntry[] = (store.__solusMockSmsInbox ??= []);

export class MockSmsProvider implements SmsProvider {
  readonly name = 'mock';

  async send(message: SmsMessage): Promise<SmsResult> {
    validateSms(message);
    if (message.to.endsWith('9')) throw new SmsProviderError('mock sms: simulated outage', true);
    const providerMessageId = `mock-${createHash('sha256').update(message.reference).digest('hex').slice(0, 20)}`;
    const existing = inbox.find((m) => m.providerMessageId === providerMessageId);
    if (!existing) inbox.push({ ...message, providerMessageId, sentAt: new Date() });
    // Local dev on a simulator/emulator has no SMS: MOCK_SMS_LOG=1 prints the "delivered" text to the server log.
    if (!existing && process.env.MOCK_SMS_LOG === '1') console.info(`[mock sms] to ${message.to}: ${message.body}`);
    return { provider: this.name, providerMessageId };
  }

  /** Dev/test only: latest messages for a phone number, newest first. */
  static inboxFor(phone: string, limit = 5): readonly InboxEntry[] {
    return inbox.filter((m) => m.to === phone).sort((a, b) => b.sentAt.getTime() - a.sentAt.getTime()).slice(0, limit);
  }
}
