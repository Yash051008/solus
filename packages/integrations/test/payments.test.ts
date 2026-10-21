import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MockVirtualAccountProvider, handlePaymentWebhook, mockAccountNumber } from '../src/index.ts';

const provider = () => new MockVirtualAccountProvider('test-webhook-secret-0001');

test('accounts are deterministic 10-digit numbers', async () => {
  const a = await provider().createAccount({ orgId: 'org-123', displayName: 'Shop' });
  assert.match(a.accountNumber, /^99\d{8}$/);
  assert.equal(a.accountNumber, mockAccountNumber('org-123'));
});

test('signature is verified on the raw body; tampering or a missing header fails', () => {
  const p = provider();
  const { rawBody, headers } = p.simulateTransfer({ accountNumber: '9900000001', amountKobo: 150000n, reference: 'x' });
  assert.equal(p.verifyWebhook(rawBody, headers), true);
  assert.equal(p.verifyWebhook(rawBody.replace('150000', '950000'), headers), false);
  assert.equal(p.verifyWebhook(rawBody, {}), false);
  assert.equal(new MockVirtualAccountProvider('another-secret-00001').verifyWebhook(rawBody, headers), false);
});

test('amounts are integer kobo strings; decimals are rejected', () => {
  const p = provider();
  const t = p.parseWebhook(p.simulateTransfer({ accountNumber: '9900000001', amountKobo: 9223372036854775807n, reference: 'big' }).rawBody);
  assert.equal(t?.amountKobo, '9223372036854775807', 'no precision lost at max bigint');
  assert.throws(() => p.parseWebhook(JSON.stringify({ event: 'transfer.received', data: { id: 'a', reference: 'r', account_number: '1', amount_kobo: '10.5', paid_at: '' } })), RangeError);
});

test('webhook handler: 401 on bad signature, 200 posted, 200 duplicate, 500 when the DB fails', async () => {
  const p = provider();
  const seen = new Set<string>();
  const record = async (t: { eventId: string }) => {
    if (seen.has(t.eventId)) return { status: 'duplicate' as const, hash_match: true };
    seen.add(t.eventId);
    return { status: 'posted' as const };
  };
  const { rawBody, headers } = p.simulateTransfer({ accountNumber: '9900000001', amountKobo: 5000n, reference: 'r' });
  assert.deepEqual(await handlePaymentWebhook({ provider: p, record }, rawBody, {}), { httpStatus: 401, result: 'bad_signature' });
  assert.deepEqual(await handlePaymentWebhook({ provider: p, record }, rawBody, headers), { httpStatus: 200, result: 'posted' });
  assert.deepEqual(await handlePaymentWebhook({ provider: p, record }, rawBody, headers), { httpStatus: 200, result: 'duplicate' });
  const failing = async () => { throw new Error('db down'); };
  assert.equal((await handlePaymentWebhook({ provider: p, record: failing }, rawBody, headers)).httpStatus, 500);
});
