'use server';
import { nairaToKobo } from '@solus/core';
import { getRepo } from '@/lib/supabase/server';
import { mutate, text } from '@/lib/forms';

const back = (fd: FormData) => `/distributor/${text(fd, 'orgId')}/finance`;

export async function setCreditLimit(fd: FormData) {
  await mutate(back(fd), async () => {
    await (await getRepo()).finance.setCreditLimit(text(fd, 'relationshipId'), nairaToKobo(text(fd, 'naira')));
  }, 'Credit limit updated.');
}

export async function allocateReceipt(fd: FormData) {
  await mutate(back(fd), async () => {
    const [kind, id] = text(fd, 'target').split(':');
    if ((kind !== 'agent_cash' && kind !== 'shop_debt') || !id) throw new RangeError('Choose where to allocate it.');
    await (await getRepo()).finance.allocateReceipt(text(fd, 'eventId'), kind, id, nairaToKobo(text(fd, 'naira')));
  }, 'Receipt allocated.');
}
