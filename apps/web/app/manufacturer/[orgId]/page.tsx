import { formatNaira, kobo } from '@solus/core';
import { Flash, Shell, Status, type FlashParams } from '@/components/shell';
import { requireOrgRole } from '@/lib/session';
import { createBrand, createSku } from './actions';

export default async function ManufacturerPage({ params, searchParams }: { params: Promise<{ orgId: string }>; searchParams: FlashParams }) {
  const { orgId } = await params;
  const { ok, error } = await searchParams;
  const { repo, membership } = await requireOrgRole(orgId, ['manufacturer_admin']);
  const [brands, skus, distributors, summary] = await Promise.all([
    repo.catalogue.brands(orgId), repo.catalogue.skus(), repo.organisations.byKind('distributor'), repo.reports.manufacturerSummary(orgId),
  ]);
  const byDist = new Map<string, { name: string; qty: number; revenue: bigint; onHand: number }>();
  for (const r of summary) {
    const e = byDist.get(r.distributor_org_id) ?? { name: r.distributor_name, qty: 0, revenue: 0n, onHand: 0 };
    e.qty += Number(r.qty_pieces); e.revenue += BigInt(String(r.revenue_kobo)); e.onHand += Number(r.on_hand);
    byDist.set(r.distributor_org_id, e);
  }
  const brandName = new Map(brands.map((b) => [b.id, b.name]));
  const own = skus.filter((s) => s.manufacturer_org_id === orgId);

  return (
    <Shell nav={[{ href: `/manufacturer/${orgId}`, label: membership.orgName }]}>
      <h1>{membership.orgName}</h1>
      <Flash ok={ok} error={error} />
      <h2>Sell-out by distributor</h2>
      <p className="muted">Totals only: no shop, person or order-level data is shared with manufacturers.</p>
      <div className="panel table-wrap"><table>
        <thead><tr><th>Distributor</th><th>Pieces sold</th><th>Sales value</th><th>Stock on hand (pcs)</th></tr></thead>
        <tbody>{[...byDist.entries()].map(([id, d]) => (
          <tr key={id}><td>{d.name}</td><td>{d.qty.toLocaleString('en-NG')}</td><td>{formatNaira(kobo(d.revenue))}</td><td>{d.onHand.toLocaleString('en-NG')}</td></tr>
        ))}</tbody>
      </table></div>
      <h2>Catalogue</h2>
      <div className="panel table-wrap"><table>
        <thead><tr><th>Code</th><th>Name</th><th>Brand</th><th>Units</th><th>Status</th></tr></thead>
        <tbody>{own.map((s) => (
          <tr key={s.id}>
            <td><code>{s.code}</code></td><td>{s.name}</td><td>{brandName.get(s.brand_id)}</td>
            <td>{s.sku_uom.map((u) => `${u.uom_code}${u.pieces_per_uom > 1 ? ` = ${u.pieces_per_uom} pcs` : ''}`).join(' · ')}</td>
            <td><Status value={s.active ? 'active' : 'suspended'} /></td>
          </tr>
        ))}</tbody>
      </table></div>

      <div className="grid">
        <form action={createSku} className="panel stack">
          <h2 style={{ marginTop: 0 }}>New SKU</h2>
          <input type="hidden" name="orgId" value={orgId} />
          <label>Brand<select name="brandId" required>{brands.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}</select></label>
          <label>Code (A-Z, 0-9, dashes)<input name="code" pattern="[A-Za-z0-9][A-Za-z0-9\-]{1,31}" required /></label>
          <label>Name<input name="name" required /></label>
          <label>Pieces per carton (optional)<input name="cartonPieces" inputMode="numeric" /></label>
          <button type="submit">Add SKU</button>
        </form>
        <form action={createBrand} className="panel stack">
          <h2 style={{ marginTop: 0 }}>New brand</h2>
          <input type="hidden" name="orgId" value={orgId} />
          <label>Brand name<input name="name" required /></label>
          <button type="submit">Add brand</button>
          <p className="muted">Supplied distributors: {distributors.map((d) => d.name).join(', ')}</p>
        </form>
      </div>
    </Shell>
  );
}
