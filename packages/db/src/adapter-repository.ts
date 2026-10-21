// Adapter-only repository (service_role key, SERVER-SIDE ONLY). Exposes exactly the functions that
// server adapters are granted; it never writes tables directly.
import type { IssueOtpCode, RecordKycResult, SmsPurpose } from '@solus/integrations';
import type { DbClient } from './client.ts';
import { command } from './client.ts';

export function createAdapterRepository(serviceDb: DbClient) {
  const recordKycResult: RecordKycResult = async (a) => {
    const res = (await command(serviceDb, 'record_kyc_result', {
      p_org_id: a.orgId, p_subject_user_id: a.subjectUserId, p_id_type: a.idType, p_outcome: a.outcome,
      p_provider: a.provider, p_provider_ref: a.providerRef, p_id_hash: a.idHash,
    })) as { kyc_level: number; same_identity_other_shops: number };
    return { kycLevel: res.kyc_level, sameIdentityOtherShops: res.same_identity_other_shops };
  };
  const issueOtpCode: IssueOtpCode = async (challengeId) => {
    const rows = (await command(serviceDb, 'issue_otp_code', { p_challenge_id: challengeId })) as unknown as
      { code: string; phone_e164: string; purpose: SmsPurpose }[];
    const row = rows[0];
    if (!row) throw new Error('no code issued');
    return { code: row.code, phoneE164: row.phone_e164, purpose: row.purpose };
  };
  return { recordKycResult, issueOtpCode };
}
