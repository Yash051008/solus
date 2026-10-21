'use server';
import { getRepo } from '@/lib/supabase/server';
import { mutate, optionalText, text } from '@/lib/forms';

const back = (fd: FormData) => {
  const w = optionalText(fd, 'w');
  return `/distributor/${text(fd, 'orgId')}/fulfilment${w ? `?w=${w}` : ''}`;
};

export async function createBatch(fd: FormData) {
  await mutate(back(fd), async () => {
    const ids = fd.getAll('orderIds').filter((v): v is string => typeof v === 'string');
    if (ids.length === 0) throw new RangeError('Select at least one order.');
    await (await getRepo()).fulfilment.createBatch(text(fd, 'warehouseId'), ids);
  }, 'Batch created.');
}

export async function markPacked(fd: FormData) {
  await mutate(back(fd), async () => {
    await (await getRepo()).fulfilment.markPacked(text(fd, 'batchId'));
  }, 'Batch packed.');
}

export async function dispatchBatch(fd: FormData) {
  await mutate(back(fd), async () => {
    await (await getRepo()).fulfilment.dispatch(text(fd, 'batchId'), text(fd, 'carrierUserId'));
  }, 'Dispatched. Waiting for the carrier to accept in their app.');
}

export async function decideSplit(fd: FormData) {
  const choice = text(fd, 'choice') === 'single' ? 'single' : 'split';
  await mutate(back(fd), async () => {
    await (await getRepo()).orders.decideSplit(text(fd, 'orderId'), choice);
  }, choice === 'split' ? 'Split accepted; stock reserved.' : 'Single warehouse chosen; stock reserved.');
}

export async function startReturn(fd: FormData) {
  await mutate(back(fd), async () => {
    const lines: { skuId: string; qtyPieces: number }[] = [];
    for (const [k, v] of fd.entries()) {
      if (!k.startsWith('r:') || typeof v !== 'string') continue;
      const qty = Number(v || '0');
      if (!Number.isSafeInteger(qty) || qty < 0) throw new RangeError('Returned quantities must be whole numbers.');
      if (qty > 0) lines.push({ skuId: k.slice(2), qtyPieces: qty });
    }
    await (await getRepo()).fulfilment.startReturn(text(fd, 'shipmentId'), lines);
  }, 'Return counted. Waiting for the carrier to confirm.');
}
