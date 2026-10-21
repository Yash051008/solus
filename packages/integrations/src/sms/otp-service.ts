// Adapter glue (server-side only): obtain a fresh code from Postgres (service_role) and text it to the
// recipient. The code is passed straight through and never returned or logged.
import type { SmsProvider, SmsPurpose } from './types.ts';
import { otpMessageBody } from './types.ts';

export type IssueOtpCode = (challengeId: string) => Promise<{ code: string; phoneE164: string; purpose: SmsPurpose }>;

export async function sendOtp(deps: { issue: IssueOtpCode; sms: SmsProvider }, challengeId: string): Promise<{ sentTo: string }> {
  const { code, phoneE164, purpose } = await deps.issue(challengeId);
  await deps.sms.send({ to: phoneE164, body: otpMessageBody(code, purpose), purpose, reference: `otp:${challengeId}:${code.length}:${Date.now()}` });
  return { sentTo: `${phoneE164.slice(0, 7)}…${phoneE164.slice(-2)}` };   // masked for UI
}
