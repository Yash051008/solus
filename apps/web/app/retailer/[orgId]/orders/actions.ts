'use server';
import { getRepo } from '@/lib/supabase/server';
import { mutate, text } from '@/lib/forms';

const back = (fd: FormData) => `/retailer/${text(fd, 'orgId')}/orders`;

export async function cancelOrder(fd: FormData) {
  await mutate(back(fd), async () => {
    await (await getRepo()).orders.cancel(text(fd, 'orderId'), text(fd, 'reason'));
  }, 'Order cancelled and stock released.');
}

export async function confirmDelivery(fd: FormData) {
  await mutate(back(fd), async () => {
    await (await getRepo()).orders.confirmDelivery(text(fd, 'orderId'));
  }, 'Delivery confirmed.');
}

export async function disputeDelivery(fd: FormData) {
  await mutate(back(fd), async () => {
    await (await getRepo()).orders.disputeDelivery(text(fd, 'orderId'), text(fd, 'reason'));
  }, 'Problem reported to the distributor.');
}
