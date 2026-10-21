// Adapter-only repository (service_role key, SERVER-SIDE ONLY). Exposes exactly the functions that
// server adapters are granted; it never writes tables directly.
import type { RecordKycResult } from '@solus/integrations';
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
  return { recordKycResult };
}
