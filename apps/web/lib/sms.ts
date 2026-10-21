import 'server-only';
import { MockSmsProvider, sendOtp, type SmsProvider } from '@solus/integrations';
import { adapterRepository } from './supabase/admin';

/** Only the mock exists until a real adapter is verified against current provider docs (ADR-0006). */
export function smsProvider(): SmsProvider {
  const name = process.env.SMS_PROVIDER ?? 'mock';
  if (name !== 'mock') throw new Error(`SMS provider "${name}" is not implemented (ADR-0006)`);
  return new MockSmsProvider();
}

export const isMockSms = () => (process.env.SMS_PROVIDER ?? 'mock') === 'mock';

/** Issue a fresh code (service_role) and text it to the challenge's recipient. Returns a masked number. */
export async function sendOtpFor(challengeId: string) {
  return sendOtp({ issue: adapterRepository().issueOtpCode, sms: smsProvider() }, challengeId);
}

/** Local dev only: what the mock "delivered" to this phone. */
export function mockInbox(phone: string | null) {
  return isMockSms() && phone ? MockSmsProvider.inboxFor(phone, 1) : [];
}
