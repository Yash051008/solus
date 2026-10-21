// Adapter glue (server-side only): call the provider, digest the ID, hand the outcome to Postgres.
// No business rules here. KYC level and duplicate-identity logic live in app.record_kyc_result.
import { randomUUID } from 'node:crypto';
import type { KycIdType, KycOutcome, KycProvider } from './types.ts';
import { validateKycRequest } from './types.ts';
import { identityDigest } from './digest.ts';

export type RecordKycResult = (args: {
  orgId: string;
  subjectUserId: string;
  idType: KycIdType;
  outcome: KycOutcome;
  provider: string;
  providerRef: string;
  idHash: string;
}) => Promise<{ kycLevel: number; sameIdentityOtherShops: number }>;

export type VerifyKycInput = {
  orgId: string;
  subjectUserId: string;
  idType: KycIdType;
  idNumber: string;
  firstName: string;
  lastName: string;
  dateOfBirth?: string;
};

export async function verifyAndRecordKyc(
  deps: { provider: KycProvider; pepper: string; record: RecordKycResult },
  input: VerifyKycInput,
): Promise<{ outcome: KycOutcome; kycLevel: number; sameIdentityOtherShops: number }> {
  const request = {
    idType: input.idType,
    idNumber: input.idNumber.trim(),
    firstName: input.firstName.trim(),
    lastName: input.lastName.trim(),
    reference: randomUUID(),
    ...(input.dateOfBirth === undefined ? {} : { dateOfBirth: input.dateOfBirth }),
  };
  validateKycRequest(request);

  const result = await deps.provider.verifyIdentity(request);
  const recorded = await deps.record({
    orgId: input.orgId,
    subjectUserId: input.subjectUserId,
    idType: input.idType,
    outcome: result.outcome,
    provider: result.provider,
    providerRef: result.providerRef,
    idHash: identityDigest(deps.pepper, input.idType, request.idNumber),
  });
  return { outcome: result.outcome, ...recorded };
}
