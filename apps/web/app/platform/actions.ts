'use server';
import { getRepo } from '@/lib/supabase/server';
import { mutate, text } from '@/lib/forms';

export async function onboardOrganisation(fd: FormData) {
  await mutate('/platform', async () => {
    const kind = text(fd, 'kind');
    if (kind !== 'distributor' && kind !== 'manufacturer') throw new RangeError('choose distributor or manufacturer');
    await (await getRepo()).organisations.onboard({
      kind, name: text(fd, 'name'), slug: text(fd, 'slug'), adminUserId: text(fd, 'adminUserId'),
    });
  }, 'Organisation onboarded.');
}
