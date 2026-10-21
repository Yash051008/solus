'use server';
import { formatNaira, kobo } from '@solus/core';
import { getRepo } from '@/lib/supabase/server';
import { mutate, num, optionalText, text } from '@/lib/forms';

const REASONS: Record<string, string> = {
  outside_geofence: 'You are not at the shop (or your GPS fix is too weak). Move closer and try again.',
  insufficient_carried_stock: 'You are not carrying that much.',
  unknown_retailer: 'That shop is not in your territory.',
};

export async function requestStock(fd: FormData) {
  await mutate('/field', async () => {
    await (await getRepo()).push.requestStock(text(fd, 'warehouseId'),
      [{ skuId: text(fd, 'skuId'), uomCode: 'carton', uomQty: num(fd, 'cartons') }], optionalText(fd, 'note'));
  }, 'Request sent to your branch manager.');
}

export async function recordSale(fd: FormData) {
  let message = '';
  await mutate('/field', async () => {
    const lines: { skuId: string; qtyPieces: number }[] = [];
    for (const [k, v] of fd.entries()) {
      if (!k.startsWith('s:') || typeof v !== 'string') continue;
      const n = Number(v || '0');
      if (!Number.isSafeInteger(n) || n < 0) throw new RangeError('Quantities must be whole numbers.');
      if (n > 0) lines.push({ skuId: k.slice(2), qtyPieces: n });
    }
    if (lines.length === 0) throw new RangeError('Enter at least one quantity sold.');
    try {
      const r = await (await getRepo()).push.recordSale({
        shipmentId: text(fd, 'shipmentId'), retailerOrgId: text(fd, 'retailerOrgId'), lines,
        lat: num(fd, 'lat'), lng: num(fd, 'lng'), accuracyM: num(fd, 'accuracy'), idempotencyKey: text(fd, 'idempotencyKey'),
      });
      message = `Sale recorded: ${formatNaira(kobo(r.total_kobo))} cash collected.`;
    } catch (err) {
      const reason = err instanceof Error ? REASONS[err.message] : undefined;
      if (reason) throw new RangeError(reason);
      throw err;
    }
  }, () => message);
}
