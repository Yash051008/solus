import { test } from 'node:test';
import assert from 'node:assert/strict';
import { smsProviderContract } from '../src/sms/contract.ts';
import { MockSmsProvider, sendOtp } from '../src/index.ts';

smsProviderContract('mock', () => new MockSmsProvider(), { okPhone: '+2348000000101', outagePhone: '+2348000000109' });

test('sendOtp texts the issued code to the recipient and only returns a masked number', async () => {
  const result = await sendOtp(
    { issue: async () => ({ code: '424242', phoneE164: '+2348000000202', purpose: 'handover' }), sms: new MockSmsProvider() },
    'challenge-0001',
  );
  assert.deepEqual(result, { sentTo: '+234800…02' });
  assert.ok(!JSON.stringify(result).includes('424242'), 'the code is never returned');
  const [msg] = MockSmsProvider.inboxFor('+2348000000202');
  assert.ok(msg?.body.includes('424242'), 'the recipient received the code');
});
