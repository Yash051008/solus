'use server';
import { verifyAndRecordKyc, type KycIdType } from '@solus/integrations';
import { getRepo } from '@/lib/supabase/server';
import { adapterRepository } from '@/lib/supabase/admin';
import { kycPepper, kycProvider } from '@/lib/kyc';
import { mutate, optionalText, text } from '@/lib/forms';

const OUTCOME_TEXT = {
  exact_match: 'Verified: your details match.',
  partial_match: 'Partially matched. A distributor will review it.',
  no_match: 'Your details did not match this ID. Check the spelling of your name.',
  not_found: 'That ID number was not found.',
} as const;

/**
 * KYC adapter flow (server-side only). The subject is the SIGNED-IN user, and the shop must be one they
 * own (checked via RLS before anything is sent to a provider). The raw ID number goes to the provider
 * and is digested here. It is never stored or logged.
 */
export async function submitKyc(fd: FormData) {
  const orgId = text(fd, 'orgId');
  let message = '';
  await mutate(`/retailer/${orgId}`, async () => {
    const repo = await getRepo();
    const userId = await repo.me.userId();
    const owns = (await repo.me.memberships()).some((m) => m.orgId === orgId && m.role === 'retailer' && m.status === 'active');
    if (userId === null || !owns) throw new RangeError('You can only verify your own shop.');

    const idType = text(fd, 'idType');
    if (idType !== 'BVN' && idType !== 'NIN') throw new RangeError('Choose BVN or NIN.');
    const dateOfBirth = optionalText(fd, 'dateOfBirth');
    const result = await verifyAndRecordKyc(
      { provider: kycProvider(), pepper: kycPepper(), record: adapterRepository().recordKycResult },
      {
        orgId, subjectUserId: userId, idType: idType as KycIdType, idNumber: text(fd, 'idNumber'),
        firstName: text(fd, 'firstName'), lastName: text(fd, 'lastName'),
        ...(dateOfBirth === undefined ? {} : { dateOfBirth }),
      },
    );
    message = `${OUTCOME_TEXT[result.outcome]} KYC level is now ${result.kycLevel}.`;
    if (result.outcome !== 'exact_match') throw new RangeError(message);
  }, 'Verified: your details match.');
}

export async function requestDistributor(fd: FormData) {
  const orgId = text(fd, 'orgId');
  await mutate(`/retailer/${orgId}`, async () => {
    await (await getRepo()).registration.requestDistributor(orgId, text(fd, 'distributorId'));
  }, 'Request sent to the distributor.');
}
