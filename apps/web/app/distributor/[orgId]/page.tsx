import Link from 'next/link';
import { formatNaira, kobo } from '@solus/core';
import { requireOrgRole } from '@/lib/session';
import { skuMap } from '@/lib/catalogue';

const DAYS = 14;

export default async function DistributorHome({ params }: { params: Promise<{ orgId: string }> }) {
  const { orgId } = await params;
  const { repo, membership } = await requireOrgRole(orgId, ['distributor_admin', 'branch_manager', 'warehouse_staff']);
  const manager = membership.role !== 'warehouse_staff';
  const [sales, skuPerf, board, inventory, skus, customers, joins, reviews] = await Promise.all([
    repo.reports.salesDaily(orgId), repo.reports.skuPerformance(orgId), repo.reports.leaderboard(orgId),
    repo.reports.inventoryValue(orgId), skuMap(repo),
    manager ? repo.approvals.pendingCustomers(orgId) : Promise.resolve([]),
    manager ? repo.approvals.pendingJoinRequests(orgId) : Promise.resolve([]),
    manager ? repo.push.reviewItems(orgId) : Promise.resolve([]),
  ]);

  // Last 14 days, both channels summed per day (one series; channel split is in the tooltip and table).
  const today = new Date();
  const days = Array.from({ length: DAYS }, (_, i) => {
    const d = new Date(today); d.setDate(today.getDate() - (DAYS - 1 - i));
    return d.toISOString().slice(0, 10);
  });
  const byDay = new Map(days.map((d) => [d, { pull: 0n, push: 0n }]));
  for (const s of sales) {
    const e = byDay.get(s.day ?? '');
    if (e) e[s.channel === 'push' ? 'push' : 'pull'] += BigInt(s.revenue_kobo ?? '0');
  }
  const totals = days.map((d) => { const e = byDay.get(d)!; return { day: d, ...e, total: e.pull + e.push }; });
  const max = totals.reduce((m, t) => (t.total > m ? t.total : m), 0n);
  const revenue14 = totals.reduce((s, t) => s + t.total, 0n);
  const stockValue = inventory.reduce((s, i) => s + BigInt(i.value_kobo ?? '0'), 0n);
  const carried = inventory.filter((i) => i.location_kind !== 'warehouse').reduce((s, i) => s + BigInt(i.value_kobo ?? '0'), 0n);
  const topSkus = [...skuPerf].sort((a, b) => Number(BigInt(b.revenue_kobo ?? '0') - BigInt(a.revenue_kobo ?? '0'))).slice(0, 8);
  const topMax = topSkus.reduce((m, s) => (BigInt(s.revenue_kobo ?? '0') > m ? BigInt(s.revenue_kobo ?? '0') : m), 1n);
  const ranked = [...board].sort((a, b) => Number(BigInt(b.sales_kobo ?? '0') - BigInt(a.sales_kobo ?? '0')));
  const base = `/distributor/${orgId}`;
  const label = (d: string) => new Date(`${d}T12:00:00Z`).toLocaleDateString('en-NG', { day: 'numeric', month: 'short' });

  return (
    <>
      <h1>{membership.orgName}</h1>
      <p className="muted">Signed in as {membership.role.replace('_', ' ')} · figures cover what your role can see</p>
      <div className="grid">
        <div className="panel"><div className="muted">Sales, last {DAYS} days</div><div className="stat">{formatNaira(kobo(revenue14))}</div></div>
        <div className="panel"><div className="muted">Stock value (current prices)</div><div className="stat">{formatNaira(kobo(stockValue))}</div>
          <div className="muted">{formatNaira(kobo(carried))} with field staff</div></div>
        {manager ? (
          <Link href={`${base}/approvals`} className="panel"><div className="muted">Waiting for you</div>
            <div className="stat">{customers.length + joins.length + reviews.length}</div>
            <div className="muted">{customers.length} shops · {joins.length} staff · {reviews.length} offline reviews</div></Link>
        ) : null}
      </div>

      <h2>Sales per day</h2>
      <div className="panel">
        <div className="bars" role="img" aria-label={`Daily sales for the last ${DAYS} days; table below`}>
          {totals.map((t) => (
            <div key={t.day} className="bar" tabIndex={0}
              style={{ height: `${max === 0n ? 0 : Math.max(Number((t.total * 1000n) / max) / 10, t.total > 0n ? 2 : 0)}%` }}
              title={`${label(t.day)}: ${formatNaira(kobo(t.total))} (deliveries ${formatNaira(kobo(t.pull))}, agent sales ${formatNaira(kobo(t.push))})`} />
          ))}
        </div>
        <div className="bars-axis"><span>{label(days[0] ?? '')}</span><span>{label(days[days.length - 1] ?? '')}</span></div>
        <details style={{ marginTop: 8 }}>
          <summary className="muted">Table view</summary>
          <div className="table-wrap"><table>
            <thead><tr><th>Day</th><th>Deliveries</th><th>Agent sales</th><th>Total</th></tr></thead>
            <tbody>{totals.filter((t) => t.total > 0n).map((t) => (
              <tr key={t.day}><td>{label(t.day)}</td><td>{formatNaira(kobo(t.pull))}</td><td>{formatNaira(kobo(t.push))}</td><td>{formatNaira(kobo(t.total))}</td></tr>
            ))}</tbody>
          </table></div>
        </details>
      </div>

      <div className="grid">
        <section className="panel">
          <h2 style={{ marginTop: 0 }}>Top products</h2>
          <table><tbody>{topSkus.map((s) => (
            <tr key={s.sku_id}>
              <td style={{ width: '45%' }}>{skus.get(s.sku_id ?? '')?.name}</td>
              <td style={{ width: '35%' }}><div className="hbar" style={{ width: `${Number((BigInt(s.revenue_kobo ?? '0') * 100n) / topMax)}%` }} /></td>
              <td>{formatNaira(kobo(s.revenue_kobo ?? '0'))}<div className="muted">{s.qty_pieces} pcs</div></td>
            </tr>
          ))}</tbody></table>
        </section>
        <section className="panel">
          <h2 style={{ marginTop: 0 }}>Agent leaderboard</h2>
          <table>
            <thead><tr><th>#</th><th>Agent</th><th>Sales</th><th>Visits in geofence</th><th>Pending variance</th></tr></thead>
            <tbody>{ranked.map((a, i) => (
              <tr key={a.agent_user_id}>
                <td>{i + 1}</td><td>{a.full_name}</td><td>{formatNaira(kobo(a.sales_kobo ?? '0'))}<div className="muted">{a.sales_count} sales</div></td>
                <td>{a.visits_in_geofence}/{a.visits}</td><td>{a.pending_variance ? <span className="badge rejected">{a.pending_variance}</span> : '0'}</td>
              </tr>
            ))}</tbody>
          </table>
        </section>
      </div>
    </>
  );
}
