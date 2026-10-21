'use server';
import { getRepo } from '@/lib/supabase/server';
import { mutate, optionalInt, text } from '@/lib/forms';

export async function createBrand(fd: FormData) {
  const orgId = text(fd, 'orgId');
  await mutate(`/manufacturer/${orgId}`, async () => {
    await (await getRepo()).catalogue.createBrand(orgId, text(fd, 'name'));
  }, 'Brand added.');
}

export async function createSku(fd: FormData) {
  const orgId = text(fd, 'orgId');
  await mutate(`/manufacturer/${orgId}`, async () => {
    const cartonPieces = optionalInt(fd, 'cartonPieces');
    await (await getRepo()).catalogue.createSku({
      manufacturerId: orgId, brandId: text(fd, 'brandId'), code: text(fd, 'code'), name: text(fd, 'name'),
      ...(cartonPieces === null ? {} : { cartonPieces }),
    });
  }, 'SKU added.');
}
