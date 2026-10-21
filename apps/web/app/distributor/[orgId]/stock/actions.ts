'use server';
import { randomUUID } from 'node:crypto';
import { getRepo } from '@/lib/supabase/server';
import { mutate, num, optionalText, text } from '@/lib/forms';

const back = (fd: FormData) => `/distributor/${text(fd, 'orgId')}/stock`;

export async function recordReceipt(fd: FormData) {
  await mutate(back(fd), async () => {
    await (await getRepo()).stock.recordReceipt(text(fd, 'warehouseId'), text(fd, 'reference'),
      [{ skuId: text(fd, 'skuId'), uomCode: text(fd, 'uomCode'), uomQty: num(fd, 'uomQty') }], `web:receipt:${randomUUID()}`);
  }, 'Receipt recorded.');
}

export async function requestAdjustment(fd: FormData) {
  await mutate(back(fd), async () => {
    await (await getRepo()).stock.requestAdjustment(text(fd, 'warehouseId'), text(fd, 'skuId'), num(fd, 'qtyDelta'), text(fd, 'reason'));
  }, 'Adjustment requested.');
}

export async function decideAdjustment(fd: FormData) {
  const approve = text(fd, 'decision') === 'approve';
  await mutate(back(fd), async () => {
    await (await getRepo()).stock.decideAdjustment(text(fd, 'requestId'), approve, optionalText(fd, 'reason'));
  }, approve ? 'Adjustment approved and posted.' : 'Adjustment rejected.');
}
