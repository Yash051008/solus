import { test } from 'node:test';
import assert from 'node:assert/strict';
import { kycProviderContract } from '../src/kyc/contract.ts';
import { MockKycProvider, identityDigest, verifyAndRecordKyc } from '../src/index.ts';

kycProviderContract('mock', () => new MockKycProvider(), {
  ids: { exact_match: '22222222221', partial_match: '22222222225', no_match: '22222222229', not_found: '22222222220' },
  outageId: '22222222227',
});

const PEPPER = 'test-pepper-test-pepper-test-pepper-0001';

test('identity digest: deterministic, type-scoped, never the raw number', () => {
  const a = identityDigest(PEPPER, 'BVN', '22222222221');
  assert.match(a, /^[0-9a-f]{64}$/);
  assert.equal(a, identityDigest(PEPPER, 'BVN', '22222222221'));
  assert.notEqual(a, identityDigest(PEPPER, 'NIN', '22222222221'), 'same digits as BVN vs NIN differ');
  assert.notEqual(a, identityDigest(`${PEPPER}x`, 'BVN', '22222222221'), 'pepper matters');
  assert.ok(!a.includes('22222222221'));
  assert.throws(() => identityDigest('short', 'BVN', '22222222221'), RangeError);
});

test('verifyAndRecordKyc passes only outcome, reference and digest to the recorder', async () => {
  let recorded: Record<string, unknown> | undefined;
  const result = await verifyAndRecordKyc(
    {
      provider: new MockKycProvider(),
      pepper: PEPPER,
      record: async (args) => {
        recorded = args;
        return { kycLevel: 1, sameIdentityOtherShops: 0 };
      },
    },
    { orgId: 'org-1', subjectUserId: 'user-1', idType: 'BVN', idNumber: ' 22222222221 ', firstName: 'Ada', lastName: 'Obi' },
  );
  assert.deepEqual(result, { outcome: 'exact_match', kycLevel: 1, sameIdentityOtherShops: 0 });
  assert.ok(recorded);
  assert.deepEqual(Object.keys(recorded).sort(), ['idHash', 'idType', 'orgId', 'outcome', 'provider', 'providerRef', 'subjectUserId']);
  assert.equal(recorded['idHash'], identityDigest(PEPPER, 'BVN', '22222222221'), 'digest of the trimmed number');
  assert.ok(!JSON.stringify(recorded).includes('22222222221'), 'raw ID never reaches the recorder');
});

test('verifyAndRecordKyc records nothing when the provider fails', async () => {
  let calls = 0;
  await assert.rejects(
    verifyAndRecordKyc(
      { provider: new MockKycProvider(), pepper: PEPPER, record: async () => { calls++; return { kycLevel: 0, sameIdentityOtherShops: 0 }; } },
      { orgId: 'o', subjectUserId: 'u', idType: 'NIN', idNumber: '22222222227', firstName: 'Ada', lastName: 'Obi' },
    ),
  );
  assert.equal(calls, 0);
});
