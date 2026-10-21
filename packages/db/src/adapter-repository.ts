// Adapter-only repository (service_role key, SERVER-SIDE ONLY). Exposes exactly the functions that
// server adapters are granted; it never writes tables directly.
import type { IssueOtpCode, RecordKycResult, RecordProviderEvent, SmsPurpose, VirtualAccount } from '@solus/integrations';
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
  const recordProviderEvent: RecordProviderEvent = async (t) =>
    (await command(serviceDb, 'record_provider_event', {
      p_provider: t.provider, p_provider_event_id: t.eventId, p_reference: t.reference, p_account_number: t.accountNumber,
      p_amount_kobo: t.amountKobo as unknown as number, p_payload_hash: t.payloadHash, ...(t.paidAt ? { p_paid_at: t.paidAt } : {}),
    })) as unknown as { status: 'posted' | 'duplicate' | 'unmatched'; hash_match?: boolean };
  const provisionVirtualAccount = async (orgId: string, va: VirtualAccount) =>
    command(serviceDb, 'provision_virtual_account', {
      p_org_id: orgId, p_provider: va.provider, p_account_number: va.accountNumber, p_bank_name: va.bankName, p_provider_ref: va.providerRef,
    });
  const reconcile = async (provider: string, lines: { eventId: string; amountKobo: string }[]) =>
    command(serviceDb, 'reconcile_provider', { p_provider: provider, p_lines: lines.map((l) => ({ provider_event_id: l.eventId, amount_kobo: l.amountKobo })) as never }) as Promise<unknown> as
      Promise<{ missing_in_ledger: string[]; missing_in_statement: string[]; amount_mismatch: string[]; unmatched_accounts: string[]; statement_total_kobo: string; clearing_balance_kobo: string }>;
  return { recordKycResult, issueOtpCode, recordProviderEvent, provisionVirtualAccount, reconcile };
}
