import 'server-only';
import { formatPieces } from '@solus/core';
import type { Repository } from '@solus/db';

export type SkuInfo = { id: string; code: string; name: string; cartonPieces: number | null };

/** SKU lookup with the carton factor, for display edges only (stock is always pieces). */
export async function skuMap(repo: Repository): Promise<Map<string, SkuInfo>> {
  const skus = await repo.catalogue.skus();
  return new Map(skus.map((s) => [s.id, {
    id: s.id, code: s.code, name: s.name,
    cartonPieces: s.sku_uom.find((u) => u.uom_code === 'carton')?.pieces_per_uom ?? null,
  }]));
}

export function showQty(pieces: number, sku: SkuInfo | undefined): string {
  return sku?.cartonPieces ? formatPieces(pieces, sku.cartonPieces) : `${pieces} pcs`;
}
