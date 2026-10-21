// KycProvider: match-only identity verification (ADR-0005). The result type deliberately has no slot
// for names, dates of birth, phones or images, so no adapter can leak provider-returned PII to callers.

export type KycIdType = 'BVN' | 'NIN';

export type KycOutcome = 'exact_match' | 'partial_match' | 'no_match' | 'not_found';

export type KycRequest = {
  idType: KycIdType;
  idNumber: string;      // 11 digits for both BVN and NIN; never persisted by us
  firstName: string;
  lastName: string;
  dateOfBirth?: string;  // YYYY-MM-DD
  reference: string;     // our unique reference for this attempt (provider-side idempotency)
};

export type KycField = 'id_number' | 'first_name' | 'last_name' | 'date_of_birth';

export type KycFieldResult = { field: KycField; matched: boolean | null };

export type KycResult = {
  provider: string;
  providerRef: string;
  outcome: KycOutcome;
  fieldResults: readonly KycFieldResult[];
};

export interface KycProvider {
  readonly name: string;
  verifyIdentity(request: KycRequest): Promise<KycResult>;
}

export class KycProviderError extends Error {
  readonly retryable: boolean;
  constructor(message: string, retryable: boolean) {
    super(message);
    this.name = 'KycProviderError';
    this.retryable = retryable;
  }
}

const ID_NUMBER = /^\d{11}$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

/** Input validation shared by every caller, before any provider is contacted. */
export function validateKycRequest(request: KycRequest): void {
  if (request.idType !== 'BVN' && request.idType !== 'NIN') throw new RangeError('idType must be BVN or NIN');
  if (!ID_NUMBER.test(request.idNumber)) throw new RangeError(`${request.idType} must be exactly 11 digits`);
  if (request.firstName.trim() === '' || request.lastName.trim() === '') throw new RangeError('first and last name are required');
  if (request.dateOfBirth !== undefined && !DATE.test(request.dateOfBirth)) throw new RangeError('dateOfBirth must be YYYY-MM-DD');
  if (request.reference.trim().length < 8) throw new RangeError('reference must be at least 8 characters');
}
