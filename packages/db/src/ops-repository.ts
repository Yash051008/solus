// Phase 4 repository: catalogue, stock, orders, fulfilment, deliveries. User-scoped (RLS applies).
import type { DbClient } from './client.ts';
import { command, rows, toDomainError } from './client.ts';

export type Line = { skuId: string; uomCode: string; uomQty: number };
const toLines = (lines: readonly Line[]) =>
  lines.map((l) => ({ sku_id: l.skuId, uom_code: l.uomCode, uom_qty: l.uomQty }));

export function createOpsRepository(db: DbClient) {
  return {
    catalogue: {
      async brands(manufacturerId?: string) {
        const q = db.from('brands').select('id, name, manufacturer_org_id').order('name');
        return rows(await (manufacturerId ? q.eq('manufacturer_org_id', manufacturerId) : q));
      },
      async skus() {
        return rows(await db.from('skus').select('id, code, name, active, brand_id, manufacturer_org_id, sku_uom(uom_code, pieces_per_uom)').order('code'));
      },
      createBrand: (manufacturerId: string, name: string) =>
        command(db, 'create_brand', { p_manufacturer_id: manufacturerId, p_name: name }),
      createSku: (i: { manufacturerId: string; brandId: string; code: string; name: string; cartonPieces?: number }) =>
        command(db, 'create_sku', {
          p_manufacturer_id: i.manufacturerId, p_brand_id: i.brandId, p_code: i.code, p_name: i.name,
          ...(i.cartonPieces === undefined ? {} : { p_carton_pieces: i.cartonPieces }),
        }),
      async currentPrices(distributorId: string) {
        return rows(await db.from('v_current_prices').select('sku_id, uom_code, price_kobo::text').eq('distributor_org_id', distributorId));
      },
    },

    stock: {
      async balances(orgId: string) {
        return rows(await db.from('stock_balances').select('location_id, sku_id, on_hand, reserved, available, location_kind')
          .eq('org_id', orgId));
      },
      async locations(orgId: string) {
        return rows(await db.from('stock_locations').select('id, kind, warehouse_id, user_id').eq('org_id', orgId));
      },
      async adjustments(orgId: string) {
        return rows(await db.from('adjustment_requests')
          .select('id, location_id, sku_id, qty_delta, reason, status, requested_by, created_at')
          .eq('org_id', orgId).order('created_at', { ascending: false }).limit(50));
      },
      recordReceipt: (warehouseId: string, reference: string, lines: readonly Line[], idempotencyKey: string) =>
        command(db, 'record_receipt', { p_warehouse_id: warehouseId, p_reference: reference, p_lines: toLines(lines) as never, p_idempotency_key: idempotencyKey }),
      requestAdjustment: (warehouseId: string, skuId: string, qtyDelta: number, reason: string) =>
        command(db, 'request_adjustment', { p_warehouse_id: warehouseId, p_sku_id: skuId, p_qty_delta: qtyDelta, p_reason: reason }),
      decideAdjustment: (requestId: string, approve: boolean, reason?: string) =>
        command(db, 'decide_adjustment', { p_request_id: requestId, p_approve: approve, ...(reason === undefined ? {} : { p_reason: reason }) }),
    },

    orders: {
      place: (i: { distributorId: string; retailerOrgId: string; lines: readonly Line[]; idempotencyKey: string }) =>
        command(db, 'place_order', {
          p_distributor_id: i.distributorId, p_retailer_org_id: i.retailerOrgId,
          p_lines: toLines(i.lines) as never, p_idempotency_key: i.idempotencyKey,
        }) as Promise<unknown> as Promise<{ order_id: string; status: string; routing_reason: string | null; replayed: boolean }>,
      async list(filter: { retailerOrgId?: string; distributorId?: string; statuses?: string[] }) {
        let q = db.from('v_orders').select('id, distributor_org_id, retailer_org_id, status, routing_reason, routing_decision, placed_by_role, created_at, confirmed_at, cancelled_reason, total_kobo::text').order('created_at', { ascending: false }).limit(100);
        if (filter.retailerOrgId) q = q.eq('retailer_org_id', filter.retailerOrgId);
        if (filter.distributorId) q = q.eq('distributor_org_id', filter.distributorId);
        if (filter.statuses) q = q.in('status', filter.statuses as never);
        return rows(await q);
      },
      async lines(orderIds: readonly string[]) {
        if (orderIds.length === 0) return [];
        return rows(await db.from('order_lines').select('id, order_id, sku_id, uom_code, uom_qty, qty_pieces, line_amount_kobo::text').in('order_id', [...orderIds]));
      },
      async allocations(filter: { orderIds?: readonly string[]; warehouseId?: string; statuses?: string[]; batchId?: string }) {
        let q = db.from('order_allocations').select('id, order_id, order_line_id, sku_id, warehouse_id, qty_pieces, status, batch_id');
        if (filter.orderIds) q = q.in('order_id', [...filter.orderIds]);
        if (filter.warehouseId) q = q.eq('warehouse_id', filter.warehouseId);
        if (filter.batchId) q = q.eq('batch_id', filter.batchId);
        if (filter.statuses) q = q.in('status', filter.statuses);
        return rows(await q);
      },
      cancel: (orderId: string, reason: string) => command(db, 'cancel_order', { p_order_id: orderId, p_reason: reason }),
      decideSplit: (orderId: string, choice: 'single' | 'split') => command(db, 'decide_split', { p_order_id: orderId, p_choice: choice }),
      confirmDelivery: (orderId: string) => command(db, 'confirm_delivery', { p_order_id: orderId }),
      disputeDelivery: (orderId: string, reason: string) => command(db, 'dispute_delivery', { p_order_id: orderId, p_reason: reason }),
    },

    fulfilment: {
      async batches(warehouseIds: readonly string[]) {
        if (warehouseIds.length === 0) return [];
        return rows(await db.from('batches').select('id, warehouse_id, status, created_at').in('warehouse_id', [...warehouseIds])
          .order('created_at', { ascending: false }).limit(50));
      },
      async shipments(filter: { warehouseIds?: readonly string[]; carrierLocationIds?: readonly string[] }) {
        let q = db.from('shipments').select('id, warehouse_id, carrier_location_id, batch_id, status, status_note, created_at')
          .order('created_at', { ascending: false }).limit(50);
        if (filter.warehouseIds) q = q.in('warehouse_id', [...filter.warehouseIds]);
        if (filter.carrierLocationIds) q = q.in('carrier_location_id', [...filter.carrierLocationIds]);
        return rows(await q);
      },
      async myCarrierLocations(userId: string) {
        return rows(await db.from('stock_locations').select('id, kind, org_id').eq('user_id', userId).in('kind', ['driver', 'agent']));
      },
      async carriers(orgId: string) {
        return rows(await db.from('stock_locations').select('id, kind, user_id, profiles(full_name)').eq('org_id', orgId).in('kind', ['driver', 'agent']));
      },
      async deliveries(orderIds: readonly string[]) {
        if (orderIds.length === 0) return [];
        return rows(await db.from('deliveries').select('id, shipment_id, order_id, invoiced_kobo::text, geofence_ok, geofence_reason, distance_m, recorded_at, photo_path').in('order_id', [...orderIds]));
      },
      createBatch: (warehouseId: string, orderIds: readonly string[]) =>
        command(db, 'create_batch', { p_warehouse_id: warehouseId, p_order_ids: [...orderIds] }),
      markPacked: (batchId: string) => command(db, 'mark_batch_packed', { p_batch_id: batchId }),
      dispatch: (batchId: string, carrierUserId: string) => command(db, 'dispatch_batch', { p_batch_id: batchId, p_carrier_user_id: carrierUserId }),
      accept: (shipmentId: string) => command(db, 'accept_dispatch', { p_shipment_id: shipmentId }),
      decline: (shipmentId: string, reason: string) => command(db, 'decline_dispatch', { p_shipment_id: shipmentId, p_reason: reason }),
      startReturn: (shipmentId: string, lines: readonly { skuId: string; qtyPieces: number }[]) =>
        command(db, 'start_return', { p_shipment_id: shipmentId, p_lines: lines.map((l) => ({ sku_id: l.skuId, qty_pieces: l.qtyPieces })) as never }),
      confirmReturn: (shipmentId: string) => command(db, 'confirm_return', { p_shipment_id: shipmentId }),
      async uploadEpod(path: string, file: Blob, contentType: string) {
        const { error } = await db.storage.from('epod').upload(path, file, { contentType, upsert: false });
        if (error) throw toDomainError({ message: `photo upload failed: ${error.message}` });
      },
      recordDelivery: (i: {
        shipmentId: string; orderId: string;
        lines: readonly { allocationId: string; delivered: number; refused: number; damaged: number; missing: number }[];
        lat: number; lng: number; accuracyM: number; photoPath: string; recipientName: string; idempotencyKey: string;
      }) => command(db, 'record_delivery', {
        p_shipment_id: i.shipmentId, p_order_id: i.orderId,
        p_lines: i.lines.map((l) => ({ allocation_id: l.allocationId, delivered: l.delivered, refused: l.refused, damaged: l.damaged, missing: l.missing })) as never,
        p_lat: i.lat, p_lng: i.lng, p_accuracy_m: i.accuracyM, p_photo_path: i.photoPath,
        p_recipient_name: i.recipientName, p_idempotency_key: i.idempotencyKey,
      }) as Promise<unknown> as Promise<{ delivery_id: string; invoiced_kobo: string; geofence_ok: boolean; geofence_reason: string }>,
    },
  };
}
