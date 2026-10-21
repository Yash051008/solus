// End-to-end through the real stack: Supabase Auth -> PostgREST -> RLS -> app.* commands, using the
// same repository layer the web app uses. Proves the Phase 3 flows work for genuine signed-in users.
import { test } from 'node:test';
import { randomInt, randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
import { homePathFor, DomainError } from '@solus/core';
import { createRepository, createAdapterRepository } from '@solus/db';
import { MockKycProvider, verifyAndRecordKyc } from '@solus/integrations';
import { signIn, signUpFresh, serviceClient } from '../support/supabase.ts';
import { connect, one } from '../support/db.ts';

const PEPPER = 'integration-pepper-integration-pepper-0001';
// Unique per run: the stack is not reset between `npm run test:node` invocations.
const RUN = randomUUID().slice(0, 6);
const uniqueBvn = () => `${String(randomInt(1e9, 1e10 - 1))}1`;   // 11 digits, ends in 1 => mock exact_match

// Fixture lookups go straight to Postgres (service_role deliberately has no table privileges).
async function orgIdBySlug(slug: string): Promise<string> {
  const c = await connect();
  try {
    return (await one<{ id: string }>(c, 'select id from public.organisations where slug = $1', [slug])).id;
  } finally {
    await c.end();
  }
}

test('retailer self-registration -> branch manager approval -> KYC (mock) -> console routing', async () => {
  const lagosPrime = await orgIdBySlug('lagos-prime');
  const { db: shopDb } = await signUpFresh('shop');
  const shop = createRepository(shopDb);

  assert.equal(homePathFor(await shop.me.memberships()), '/onboarding', 'a newcomer lands on onboarding');
  const directory = await shop.registration.directory();
  assert.deepEqual(directory.map((d) => d.name).sort(), ['Abuja Central Distributors Ltd', 'Lagos Prime Distribution Ltd']);

  const orgId = await shop.registration.registerRetailer({
    businessName: 'Integration Mart', fullName: 'Chidi Okeke', phoneE164: '+2348099990001',
    lat: 6.4515, lng: 3.4795, accuracyM: 9, distributorId: lagosPrime,
  });
  assert.equal(homePathFor(await shop.me.memberships()), `/retailer/${orgId}`, 'the shop owner is routed to their shop console');
  assert.equal((await shop.retailer.relationships(orgId))[0]?.status, 'pending');

  // Wrong branch manager cannot approve; the right one can.
  const ikejaBm = createRepository(await signIn('lp.bm.ikeja'));
  const lekkiBm = createRepository(await signIn('lp.bm.lekki'));
  const pending = (await lekkiBm.approvals.pendingCustomers(lagosPrime)).find((c) => c.retailer_org_id === orgId);
  assert.ok(pending, 'Lekki branch manager sees the pending shop');
  await assert.rejects(ikejaBm.approvals.decideCustomer({ relationshipId: pending.id, approve: true }),
    (e) => e instanceof DomainError && e.code === 'forbidden');
  await lekkiBm.approvals.decideCustomer({ relationshipId: pending.id, approve: true });

  const rel = (await shop.retailer.relationships(orgId))[0];
  assert.equal(rel?.status, 'active');
  assert.equal(rel?.organisations?.name, 'Lagos Prime Distribution Ltd');

  // KYC through the adapter: provider -> digest -> service_role records the outcome.
  const userId = await shop.me.userId();
  assert.ok(userId);
  const kyc = await verifyAndRecordKyc(
    { provider: new MockKycProvider(), pepper: PEPPER, record: createAdapterRepository(serviceClient()).recordKycResult },
    { orgId, subjectUserId: userId, idType: 'BVN', idNumber: uniqueBvn(), firstName: 'Chidi', lastName: 'Okeke' },
  );
  assert.deepEqual(kyc, { outcome: 'exact_match', kycLevel: 1, sameIdentityOtherShops: 0 });
  assert.equal(await shop.retailer.kycLevel(orgId), 1);
  assert.deepEqual((await shop.retailer.kycChecks(orgId)).map((c) => c.outcome), ['exact_match']);

  // The client can neither read the identity digest nor record its own verification.
  const digest = await shopDb.from('kyc_checks').select('id_hash');
  assert.ok(digest.error, 'id_hash is not readable by clients');
  const selfVerify = await (shopDb.schema('app') as unknown as {
    rpc: (f: string, a: unknown) => Promise<{ error: unknown }>;
  }).rpc('record_kyc_result', {
    p_org_id: orgId, p_subject_user_id: userId, p_id_type: 'NIN', p_outcome: 'exact_match',
    p_provider: 'mock', p_provider_ref: 'forged', p_id_hash: 'f'.repeat(64),
  });
  assert.ok(selfVerify.error, 'clients cannot call record_kyc_result');
  assert.equal(await shop.retailer.kycLevel(orgId), 1, 'level unchanged by the forged attempt');
});

test('agent join request -> branch manager approval with territory -> field routing', async () => {
  const lagosPrime = await orgIdBySlug('lagos-prime');
  const { db: agentDb } = await signUpFresh('agent');
  const agent = createRepository(agentDb);
  await agent.registration.requestToJoin({ distributorId: lagosPrime, role: 'agent', fullName: `Bola Ade ${RUN}`, phoneE164: '+2348099990002' });
  assert.equal((await agent.me.joinRequests())[0]?.status, 'pending');

  const bm = createRepository(await signIn('lp.bm.ikeja'));
  const req = (await bm.approvals.pendingJoinRequests(lagosPrime)).find((r) => r.profiles?.full_name === `Bola Ade ${RUN}`);
  assert.ok(req, 'branch manager sees the request with the applicant name');
  const branches = await bm.structure.branches(lagosPrime);
  const territories = await bm.structure.territories(lagosPrime);
  const ikeja = branches.find((b) => b.name === 'Ikeja');
  const ikejaNorth = territories.find((t) => t.name === 'Ikeja North');
  assert.ok(ikeja && ikejaNorth?.id);
  await bm.approvals.decideJoinRequest({ requestId: req.id, approve: true, branchId: ikeja.id, territoryId: ikejaNorth.id });

  assert.equal(homePathFor(await agent.me.memberships()), '/field');
  const locations = await agentDb.from('stock_locations').select('kind');
  assert.deepEqual(locations.data, [{ kind: 'agent' }], 'the new agent sees exactly their own stock location');
});

test('geofence via the API as an agent; clients and service_role cannot write ledgers', async () => {
  const lagosPrime = await orgIdBySlug('lagos-prime');
  const retailer01 = await orgIdBySlug('retailer-01');
  const agent = createRepository(await signIn('lp.agent1'));
  const [inside] = await agent.geofence.check({ distributorId: lagosPrime, retailerOrgId: retailer01, lat: 6.6201, lng: 3.3451, accuracyM: 8 });
  assert.equal(inside?.ok, true);
  const [far] = await agent.geofence.check({ distributorId: lagosPrime, retailerOrgId: retailer01, lat: 6.63, lng: 3.345, accuracyM: 8 });
  assert.deepEqual([far?.ok, far?.reason], [false, 'outside_radius']);

  const admin = await signIn('lp.admin');
  const clientWrite = await admin.from('stock_balances').update({ on_hand: 999999 }).eq('org_id', lagosPrime);
  assert.ok(clientWrite.error, 'clients cannot write projections');
  const serviceWrite = await serviceClient().from('journals').insert({ journal_type: 'forged', idempotency_key: 'forged-0001', request_hash: 'x' });
  assert.ok(serviceWrite.error, 'even service_role cannot write the money ledger directly');
});
