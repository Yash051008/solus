import { randomUUID } from 'node:crypto';
import Link from 'next/link';
import { formatNaira, kobo } from '@solus/core';
import { Flash, Shell, type FlashParams } from '@/components/shell';
import { requireOrgRole } from '@/lib/session';
import { skuMap } from '@/lib/catalogue';
import { placeOrder } from './actions';

export default async function OrderPage({ params, searchParams }: {
  params: Promise<{ orgId: string }>;
  searchParams: Promise<{ ok?: string; error?: string; d?: string }>;
}) {
  const { orgId } = await params;
  const { ok, error, d } = await searchParams;
  const { repo, membership } = await requireOrgRole(orgId, ['retailer']);
  const relationships = (await repo.retailer.relationships(orgId)).filter((r) => r.status === 'active');
  const distributorId = relationships.find((r) => r.distributor_org_id === d)?.distributor_org_id ?? relationships[0]?.distributor_org_id;
  const [skus, prices] = await Promise.all([skuMap(repo), distributorId ? repo.catalogue.currentPrices(distributorId) : Promise.resolve([])]);

  const bySku = new Map<string, { carton?: string; piece?: string }>();
  for (const p of prices) {
    if (!p.sku_id || !p.price_kobo) continue;
    const entry = bySku.get(p.sku_id) ?? {};
    if (p.uom_code === 'carton' || p.uom_code === 'piece') entry[p.uom_code] = p.price_kobo;
    bySku.set(p.sku_id, entry);
  }
  const items = [...bySku.entries()]
    .map(([skuId, price]) => ({ sku: skus.get(skuId), price }))
    .filter((x) => x.sku)
    .sort((a, b) => (a.sku?.code ?? '').localeCompare(b.sku?.code ?? ''));

  return (
    <Shell nav={[{ href: `/retailer/${orgId}`, label: membership.orgName }, { href: `/retailer/${orgId}/order`, label: 'Order' }, { href: `/retailer/${orgId}/orders`, label: 'My orders' }]}>
      <h1>Place an order</h1>
      <Flash ok={ok} error={error} />
      {relationships.length === 0 ? <p>Your shop has no approved distributor yet.</p> : (
        <>
          {relationships.length > 1 ? (
            <p>Distributor: {relationships.map((r) => (
              <Link key={r.id} href={`/retailer/${orgId}/order?d=${r.distributor_org_id}`} style={{ marginRight: 12, fontWeight: r.distributor_org_id === distributorId ? 700 : 400 }}>
                {r.organisations?.name}
              </Link>))}
            </p>
          ) : <p className="muted">Distributor: {relationships[0]?.organisations?.name}</p>}
          <form action={placeOrder}>
            <input type="hidden" name="orgId" value={orgId} />
            <input type="hidden" name="distributorId" value={distributorId ?? ''} />
            {/* One key per rendered form: a double submit replays the same order instead of creating two. */}
            <input type="hidden" name="idempotencyKey" value={`web:order:${randomUUID()}`} />
            <div className="panel table-wrap"><table>
              <thead><tr><th>Product</th><th>Per carton</th><th>Cartons</th><th>Per piece</th><th>Pieces</th></tr></thead>
              <tbody>{items.map(({ sku, price }) => sku ? (
                <tr key={sku.id}>
                  <td><code>{sku.code}</code> {sku.name}{sku.cartonPieces ? <div className="muted">{sku.cartonPieces} pcs / carton</div> : null}</td>
                  <td>{price.carton ? formatNaira(kobo(price.carton)) : '–'}</td>
                  <td>{price.carton ? <input name={`q:${sku.id}:carton`} inputMode="numeric" size={4} aria-label={`${sku.code} cartons`} /> : null}</td>
                  <td>{price.piece ? formatNaira(kobo(price.piece)) : '–'}</td>
                  <td>{price.piece ? <input name={`q:${sku.id}:piece`} inputMode="numeric" size={4} aria-label={`${sku.code} pieces`} /> : null}</td>
                </tr>
              ) : null)}</tbody>
            </table></div>
            <p className="muted">Prices are confirmed by the distributor's current price list when you submit. Stock is reserved at the nearest warehouse that can supply the whole order.</p>
            <button type="submit">Place order</button>
          </form>
        </>
      )}
    </Shell>
  );
}
