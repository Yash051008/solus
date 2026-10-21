'use server';
import { randomUUID } from 'node:crypto';
import { formatNaira, kobo } from '@solus/core';
import { getRepo } from '@/lib/supabase/server';
import { mutate, num, text } from '@/lib/forms';

const PHOTO_TYPES: Record<string, string> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };

export async function acceptShipment(fd: FormData) {
  await mutate('/field', async () => {
    await (await getRepo()).fulfilment.accept(text(fd, 'shipmentId'));
  }, 'Shipment accepted. The goods are now in your custody.');
}

export async function declineShipment(fd: FormData) {
  await mutate('/field', async () => {
    await (await getRepo()).fulfilment.decline(text(fd, 'shipmentId'), text(fd, 'reason'));
  }, 'Shipment declined.');
}

/** Upload the photo (storage policy: only the carrier of an open shipment), then record the e-POD. */
export async function recordDelivery(fd: FormData) {
  let message = '';
  await mutate('/field', async () => {
    const shipmentId = text(fd, 'shipmentId');
    const orderId = text(fd, 'orderId');
    const photo = fd.get('photo');
    if (!(photo instanceof File) || photo.size === 0) throw new RangeError('A photo of the delivered goods is required.');
    const ext = PHOTO_TYPES[photo.type];
    if (!ext) throw new RangeError('Photo must be JPEG, PNG or WebP.');
    if (photo.size > 5 * 1024 * 1024) throw new RangeError('Photo must be 5 MB or smaller.');

    const byAllocation = new Map<string, { delivered: number; refused: number; damaged: number; missing: number }>();
    for (const [key, value] of fd.entries()) {
      const [field, allocationId] = key.split(':');
      if (!allocationId || !['delivered', 'refused', 'damaged', 'missing'].includes(field ?? '')) continue;
      const n = Number(value);
      if (!Number.isSafeInteger(n) || n < 0) throw new RangeError('Quantities must be whole numbers.');
      const entry = byAllocation.get(allocationId) ?? { delivered: 0, refused: 0, damaged: 0, missing: 0 };
      entry[field as keyof typeof entry] = n;
      byAllocation.set(allocationId, entry);
    }

    const repo = await getRepo();
    const photoPath = `${shipmentId}/${orderId}/${randomUUID()}.${ext}`;
    await repo.fulfilment.uploadEpod(photoPath, photo, photo.type);
    const result = await repo.fulfilment.recordDelivery({
      shipmentId, orderId,
      lines: [...byAllocation.entries()].map(([allocationId, c]) => ({ allocationId, ...c })),
      lat: num(fd, 'lat'), lng: num(fd, 'lng'), accuracyM: num(fd, 'accuracy'),
      photoPath, recipientName: text(fd, 'recipientName'), idempotencyKey: `web:delivery:${shipmentId}:${orderId}`,
    });
    message = `Delivery recorded. Invoiced ${formatNaira(kobo(result.invoiced_kobo))}.`
      + (result.geofence_ok ? '' : ` Location check failed (${result.geofence_reason.replaceAll('_', ' ')}); flagged for review.`);
  }, () => message);
}

export async function confirmReturn(fd: FormData) {
  let message = '';
  await mutate('/field', async () => {
    const status = await (await getRepo()).fulfilment.confirmReturn(text(fd, 'shipmentId'));
    message = status === 'closed' ? 'Return confirmed. Shipment closed.' : 'Return confirmed. Some stock is unaccounted for and needs review.';
  }, () => message);
}
