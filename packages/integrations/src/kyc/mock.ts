// Deterministic mock for tests, demos and local dev. Outcome is chosen by the LAST digit of the ID:
//   ...0 -> not_found   ...5 -> partial_match (last name mismatch)   ...7 -> provider outage (retryable)
//   ...9 -> no_match    anything else -> exact_match
import { createHash } from 'node:crypto';
import type { KycProvider, KycRequest, KycResult } from './types.ts';
import { KycProviderError, validateKycRequest } from './types.ts';

export class MockKycProvider implements KycProvider {
  readonly name = 'mock';

  async verifyIdentity(request: KycRequest): Promise<KycResult> {
    validateKycRequest(request);
    const last = request.idNumber.at(-1);
    if (last === '7') throw new KycProviderError('mock provider: simulated outage', true);

    const providerRef = `mock-${createHash('sha256').update(request.reference).digest('hex').slice(0, 24)}`;
    const dobField = request.dateOfBirth === undefined ? [] : [{ field: 'date_of_birth' as const, matched: last !== '9' }];

    switch (last) {
      case '0':
        return { provider: this.name, providerRef, outcome: 'not_found', fieldResults: [{ field: 'id_number', matched: false }] };
      case '9':
        return {
          provider: this.name, providerRef, outcome: 'no_match',
          fieldResults: [{ field: 'id_number', matched: true }, { field: 'first_name', matched: false },
                         { field: 'last_name', matched: false }, ...dobField],
        };
      case '5':
        return {
          provider: this.name, providerRef, outcome: 'partial_match',
          fieldResults: [{ field: 'id_number', matched: true }, { field: 'first_name', matched: true },
                         { field: 'last_name', matched: false }, ...dobField],
        };
      default:
        return {
          provider: this.name, providerRef, outcome: 'exact_match',
          fieldResults: [{ field: 'id_number', matched: true }, { field: 'first_name', matched: true },
                         { field: 'last_name', matched: true }, ...dobField],
        };
    }
  }
}
