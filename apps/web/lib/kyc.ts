import 'server-only';
import { MockKycProvider, type KycProvider } from '@solus/integrations';

/** Only the mock exists until a real adapter is verified against current provider docs (ADR-0005). */
export function kycProvider(): KycProvider {
  const name = process.env.KYC_PROVIDER ?? 'mock';
  if (name !== 'mock') throw new Error(`KYC provider "${name}" is not implemented (ADR-0005)`);
  return new MockKycProvider();
}

export function kycPepper(): string {
  const pepper = process.env.KYC_ID_PEPPER;
  if (!pepper || pepper.length < 32) throw new Error('KYC_ID_PEPPER must be set (>= 32 chars)');
  return pepper;
}
