// Contract every SmsProvider must pass (mock now; a real adapter in sandbox mode later).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { SmsProvider } from './types.ts';
import { SmsProviderError, otpMessageBody } from './types.ts';

export function smsProviderContract(name: string, make: () => SmsProvider, fixtures: { okPhone: string; outagePhone?: string }): void {
  test(`[${name}] sends a one-segment OTP and returns a provider message id`, async () => {
    const r = await make().send({ to: fixtures.okPhone, body: otpMessageBody('123456', 'handover'), purpose: 'handover', reference: 'contract-sms-0001' });
    assert.equal(r.provider, make().name);
    assert.ok(r.providerMessageId.length > 0);
  });

  test(`[${name}] the same reference is idempotent (one message id)`, async () => {
    const a = await make().send({ to: fixtures.okPhone, body: otpMessageBody('111111', 'return'), purpose: 'return', reference: 'contract-sms-idem1' });
    const b = await make().send({ to: fixtures.okPhone, body: otpMessageBody('111111', 'return'), purpose: 'return', reference: 'contract-sms-idem1' });
    assert.equal(a.providerMessageId, b.providerMessageId);
  });

  test(`[${name}] rejects bad numbers and multi-segment bodies before sending`, async () => {
    await assert.rejects(make().send({ to: '08012345678', body: 'x', purpose: 'handover', reference: 'contract-sms-bad1' }), RangeError);
    await assert.rejects(make().send({ to: fixtures.okPhone, body: 'x'.repeat(161), purpose: 'handover', reference: 'contract-sms-bad2' }), RangeError);
  });

  test(`[${name}] OTP text fits one SMS segment and carries no names or amounts`, () => {
    const body = otpMessageBody('987654', 'credit');
    assert.ok(body.length <= 160);
    assert.ok(body.includes('987654'));
    assert.ok(!/₦|NGN|\d{7,}/.test(body.replace('987654', '')));
  });

  if (fixtures.outagePhone !== undefined) {
    const outage = fixtures.outagePhone;
    test(`[${name}] surfaces outages as retryable SmsProviderError`, async () => {
      await assert.rejects(make().send({ to: outage, body: 'x', purpose: 'handover', reference: 'contract-sms-out1' }),
        (e) => e instanceof SmsProviderError && e.retryable);
    });
  }
}
