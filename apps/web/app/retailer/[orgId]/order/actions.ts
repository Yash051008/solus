'use server';
import { redirect } from 'next/navigation';
import { DomainError } from '@solus/core';
import type { Line } from '@solus/db';
import { getRepo } from '@/lib/supabase/server';
import { mutate, text } from '@/lib/forms';

const STATUS_TEXT: Record<string, string> = {
  reserved: 'Order placed and stock reserved.',
  awaiting_split_decision: 'Order placed. Your distributor is deciding which warehouses will supply it.',
  rejected: 'Order could not be fulfilled: not enough stock across the distributor\'s warehouses.',
};

export async function placeOrder(fd: FormData) {
  const orgId = text(fd, 'orgId');
  const lines: Line[] = [];
  for (const [key, value] of fd.entries()) {
    if (!key.startsWith('q:') || typeof value !== 'string' || value.trim() === '') continue;
    const [, skuId, uomCode] = key.split(':');
    const qty = Number(value);
    if (!Number.isSafeInteger(qty) || qty < 0) redirect(`/retailer/${orgId}/order?error=${encodeURIComponent('Quantities must be whole numbers.')}`);
    if (qty > 0 && skuId && uomCode) lines.push({ skuId, uomCode, uomQty: qty });
  }
  let message = '';
  await mutate(`/retailer/${orgId}/orders`, async () => {
    if (lines.length === 0) throw new DomainError('validation_failed', 'Enter a quantity for at least one product.');
    const result = await (await getRepo()).orders.place({
      distributorId: text(fd, 'distributorId'), retailerOrgId: orgId, lines, idempotencyKey: text(fd, 'idempotencyKey'),
    });
    message = STATUS_TEXT[result.status] ?? `Order ${result.status}.`;
    if (result.status === 'rejected') throw new DomainError('insufficient_stock', message);
  }, () => message);
}
