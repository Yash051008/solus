// HMAC-SHA256(pepper, "<idType>:<idNumber>") -> 64 hex chars. Lets us detect one identity across many
// shops without ever storing the ID number (ADR-0005). Computed server-side only.
import { createHmac } from 'node:crypto';
import type { KycIdType } from './types.ts';

export function identityDigest(pepper: string, idType: KycIdType, idNumber: string): string {
  if (pepper.length < 32) throw new RangeError('KYC_ID_PEPPER must be at least 32 characters');
  return createHmac('sha256', pepper).update(`${idType}:${idNumber}`).digest('hex');
}
