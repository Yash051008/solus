// Payments on the real stack: seeded VA numbers match the mock provider, the duplicate-webhook rule
// (one credit, second call 200 + logged), and a trade-credit payment confirmed by an SMS OTP.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createRepository, createAdapterRepository } from '@solus/db';
import { MockSmsProvider, MockVirtualAccountProvider, handlePaymentWebhook, mockAccountNumber, sendOtp } from '@solus/integrations';
import { signIn, serviceClient } from '../support/supabase.ts';
import { connect, one, assertProjectionsMatchLedgers } from '../support/db.ts';

const provider = new MockVirtualAccountProvider('integration-webhook-secret-01');

test('seeded virtual accounts use the mock provider\'s numbering', async () => {
  const c = await connect();
  try {
    const rows = (await c.query<{ org_id: string; account_number: string }>('select org_id, account_number from public.virtual_accounts')).rows;
    assert.ok(rows.length >= 22);
    for (const r of rows) assert.equal(r.account_number, mockAccountNumber(r.org_id));
  } finally { await c.end(); }
});

test('duplicate webhook: one wallet credit; the second delivery returns 200 and is logged as a duplicate', async () => {
  const c = await connect();
  try {
    const shop = await one<{ org_id: string; account_number: string }>(c, `select va.org_id, va.account_number from public.virtual_accounts va
      join public.organisations o on o.id = va.org_id where o.slug = 'retailer-08'`);
    const walletBefore = await one<{ b: string }>(c, `select coalesce(b.balance_kobo, 0)::text as b from public.accounts a
      left join public.account_balances b on b.account_id = a.id where a.account_type = 'wallet' and a.holder_org_id = $1`, [shop.org_id]);
    const record = createAdapterRepository(serviceClient()).recordProviderEvent;
    const { rawBody, headers, eventId } = provider.simulateTransfer({ accountNumber: shop.account_number, amountKobo: 123456n, reference: `TOPUP ${randomUUID()}` });

    assert.deepEqual(await handlePaymentWebhook({ provider, record }, rawBody, { 'x-mock-signature': '0'.repeat(128) }), { httpStatus: 401, result: 'bad_signature' });
    assert.deepEqual(await handlePaymentWebhook({ provider, record }, rawBody, headers), { httpStatus: 200, result: 'posted' });
    assert.deepEqual(await handlePaymentWebhook({ provider, record }, rawBody, headers), { httpStatus: 200, result: 'duplicate' });

    const after = await one<{ b: string; dups: number }>(c, `select (select b.balance_kobo::text from public.accounts a join public.account_balances b on b.account_id = a.id
        where a.account_type = 'wallet' and a.holder_org_id = $1) as b,
      (select duplicate_count from public.provider_events where provider_event_id = $2) as dups`, [shop.org_id, eventId]);
    assert.equal(BigInt(after.b), BigInt(walletBefore.b) - 123456n, 'credited exactly once');
    assert.equal(after.dups, 1, 'the duplicate is logged');
  } finally { await c.end(); }
});

test('credit purchase: limit set by the admin, SMS OTP to the shop owner, one journal', async () => {
  const c = await connect();
  const f = await one<{ rel: string; ord: string; phone: string }>(c, `select
      (select cr.id from public.customer_relationships cr join public.organisations r on r.id = cr.retailer_org_id where r.slug = 'retailer-05') as rel,
      (select o.id from public.orders o join public.organisations r on r.id = o.retailer_org_id where r.slug = 'retailer-05' and o.status = 'partially_delivered') as ord,
      (select p.phone_e164 from public.profiles p join auth.users u on u.id = p.user_id where u.email = 'retailer05@solus.test') as phone`);
  await c.end();
  const admin = createRepository(await signIn('lp.admin'));
  await admin.finance.setCreditLimit(f.rel, 50_000_000n);
  const shop = createRepository(await signIn('retailer05'));
  const due = Number(await shop.finance.amountDue(f.ord));
  assert.ok(due >= 200);
  const start = await shop.finance.startPayment(f.ord, 100n, 100n, `int:pay:${randomUUID()}`);
  assert.equal(start.status, 'pending_otp');
  assert.ok(start.challenge_id);

  const sent = await sendOtp({ issue: createAdapterRepository(serviceClient()).issueOtpCode, sms: new MockSmsProvider() }, start.challenge_id);
  assert.match(sent.sentTo, /…/);
  const sms = MockSmsProvider.inboxFor(f.phone, 1)[0];
  const code = /\b(\d{6})\b/.exec(sms?.body ?? '')?.[1];
  assert.ok(code, 'the shop owner received the code by SMS');
  assert.equal((await shop.push.verifyOtp(start.challenge_id, code)).result, 'settled');
  assert.equal(Number(await shop.finance.amountDue(f.ord)), due - 200);

  const c2 = await connect();
  try { await assertProjectionsMatchLedgers(c2); } finally { await c2.end(); }
});
