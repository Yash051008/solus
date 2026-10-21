'use server';
import { getRepo } from '@/lib/supabase/server';
import { mutate, num, optionalText, text } from '@/lib/forms';
import type { Enums } from '@solus/db';

const JOINABLE_ROLES = ['agent', 'driver', 'warehouse_staff', 'branch_manager'] as const;

export async function registerShop(fd: FormData) {
  await mutate('/onboarding', async () => {
    const repo = await getRepo();
    await repo.registration.registerRetailer({
      businessName: text(fd, 'businessName'),
      fullName: text(fd, 'fullName'),
      phoneE164: text(fd, 'phone'),
      lat: num(fd, 'lat'),
      lng: num(fd, 'lng'),
      accuracyM: num(fd, 'accuracy'),
      distributorId: text(fd, 'distributorId'),
    });
  }, 'Shop registered. The distributor will review it.');
}

export async function requestToJoin(fd: FormData) {
  await mutate('/onboarding', async () => {
    const role = text(fd, 'role');
    if (!(JOINABLE_ROLES as readonly string[]).includes(role)) throw new RangeError('choose a valid role');
    const repo = await getRepo();
    const note = optionalText(fd, 'note');
    await repo.registration.requestToJoin({
      distributorId: text(fd, 'distributorId'),
      role: role as Enums['member_role'],
      fullName: text(fd, 'fullName'),
      phoneE164: text(fd, 'phone'),
      ...(note === undefined ? {} : { note }),
    });
  }, 'Request sent. A distributor admin or branch manager will review it.');
}
