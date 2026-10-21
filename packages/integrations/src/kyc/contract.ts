// Contract tests every KycProvider implementation must pass (the mock now; real adapters in sandbox later).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { KycOutcome, KycProvider, KycRequest } from './types.ts';
import { KycProviderError } from './types.ts';

export type KycContractFixtures = {
  /** ID numbers that the implementation (or its sandbox) resolves to each outcome. */
  ids: Record<KycOutcome, string>;
  /** Optional ID that triggers a retryable provider failure (sandbox may not support this). */
  outageId?: string;
};

const ALLOWED_RESULT_KEYS = ['provider', 'providerRef', 'outcome', 'fieldResults'];
const ALLOWED_FIELD_KEYS = ['field', 'matched'];

function request(idNumber: string, reference: string, overrides: Partial<KycRequest> = {}): KycRequest {
  return { idType: 'BVN', idNumber, firstName: 'Ada', lastName: 'Obi', dateOfBirth: '1990-01-31', reference, ...overrides };
}

export function kycProviderContract(name: string, makeProvider: () => KycProvider, fixtures: KycContractFixtures): void {
  for (const outcome of ['exact_match', 'partial_match', 'no_match', 'not_found'] as const) {
    test(`[${name}] resolves the ${outcome} fixture to ${outcome} with a provider reference`, async () => {
      const result = await makeProvider().verifyIdentity(request(fixtures.ids[outcome], `contract-${outcome}-1`));
      assert.equal(result.outcome, outcome);
      assert.equal(result.provider, makeProvider().name);
      assert.ok(result.providerRef.length > 0);
    });
  }

  test(`[${name}] returns no personal data: only match flags`, async () => {
    const result = await makeProvider().verifyIdentity(request(fixtures.ids.exact_match, 'contract-pii-0001'));
    assert.deepEqual(Object.keys(result).sort(), [...ALLOWED_RESULT_KEYS].sort());
    for (const f of result.fieldResults) {
      assert.deepEqual(Object.keys(f).sort(), [...ALLOWED_FIELD_KEYS].sort());
      assert.ok(f.matched === null || typeof f.matched === 'boolean');
    }
    const serialised = JSON.stringify(result);
    assert.ok(!serialised.includes(fixtures.ids.exact_match), 'the ID number is not echoed back');
    assert.ok(!serialised.includes('Ada') && !serialised.includes('1990-01-31'), 'submitted PII is not echoed back');
  });

  test(`[${name}] the same reference yields the same provider reference (idempotent retries)`, async () => {
    const a = await makeProvider().verifyIdentity(request(fixtures.ids.exact_match, 'contract-idem-0001'));
    const b = await makeProvider().verifyIdentity(request(fixtures.ids.exact_match, 'contract-idem-0001'));
    assert.equal(a.providerRef, b.providerRef);
  });

  test(`[${name}] rejects malformed input before contacting anyone`, async () => {
    await assert.rejects(makeProvider().verifyIdentity(request('1234567890', 'contract-bad-0001')), RangeError);
    await assert.rejects(makeProvider().verifyIdentity(request(fixtures.ids.exact_match, 'contract-bad-0002', { lastName: ' ' })), RangeError);
    await assert.rejects(makeProvider().verifyIdentity(request(fixtures.ids.exact_match, 'contract-bad-0003', { dateOfBirth: '31/01/1990' })), RangeError);
  });

  if (fixtures.outageId !== undefined) {
    const outageId = fixtures.outageId;
    test(`[${name}] surfaces provider outages as retryable KycProviderError`, async () => {
      await assert.rejects(makeProvider().verifyIdentity(request(outageId, 'contract-outage-01')),
        (err) => err instanceof KycProviderError && err.retryable);
    });
  }
}
