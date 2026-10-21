import Link from 'next/link';
import { formatNaira, kobo } from '@solus/core';
import { Flash, Status } from '@/components/shell';
import { requireOrgRole } from '@/lib/session';
import { showQty, skuMap } from '@/lib/catalogue';
import { decideRequest, dismissReview, acceptIntoVariance, resolveVariance, startHandover, startReturn, verifyOtp } from './actions';

export default async function PushPage({ params, searchParams }: {
  params: Promise<{ orgId: string }>;
  searchParams: Promise<{ ok?: string; error?: string; w?: string; challenge?: string; sentTo?: string; what?: string }>;
}) {
  const { orgId } = await params;
  const sp = await searchParams;
  const { repo, membership } = await requireOrgRole(orgId, ['distributor_admin', 'branch_manager', 'warehouse_staff']);
  const isManager = membership.role !== 'warehouse_staff';
  const [locations, warehouses] = await Promise.all([repo.stock.locations(orgId), repo.structure.warehouses(orgId)]);
  const visible = warehouses.filter((x) => x.active && locations.some((l) => l.warehouse_id === x.id));
  const wh = visible.find((x) => x.id === sp.w) ?? visible[0];
  const base = `/distributor/${orgId}/push`;
  if (!wh?.id) return <><h1>Agent stock</h1><p className="muted">No warehouse in your scope.</p></>;
  const whId = wh.id;

  const [skus, requests, shipments, carriers, balances] = await Promise.all([
    skuMap(repo), repo.push.stockRequests({ warehouseIds: [whId] }),
    repo.fulfilment.shipments({ warehouseIds: [whId] }), repo.fulfilment.carriers(orgId), repo.stock.balances(orgId),
  ]);
  const push = shipments.filter((s) => s.kind === 'push' && s.status !== 'closed' && s.status !== 'cancelled');
  const [lines, cases, reviews] = await Promise.all([
    repo.push.shipmentLines(push.map((s) => s.id)),
    repo.push.varianceCases({ shipmentIds: shipments.map((s) => s.id), status: 'pending' }),
    isManager ? repo.push.reviewItems(orgId) : Promise.resolve([]),
  ]);
  const who = new Map(carriers.map((c) => [c.id, c.profiles?.full_name ?? 'agent']));
  const whoByUser = new Map(carriers.map((c) => [c.user_id, c.profiles?.full_name ?? 'agent']));
  const hidden = (extra: Record<string, string>) => (
    <>{Object.entries({ orgId, w: whId, ...extra }).map(([k, v]) => <input key={k} type="hidden" name={k} value={v} />)}</>
  );

  return (
    <>
      <h1>Agent stock (push)</h1>
      <p>Warehouse: {visible.map((x) => (
        <Link key={x.id} href={`${base}?w=${x.id}`} style={{ marginRight: 12, fontWeight: x.id === whId ? 700 : 400 }}>{x.name}</Link>
      ))}</p>
      <Flash ok={sp.ok} error={sp.error} />

      {sp.challenge ? (
        <form action={verifyOtp} className="panel stack">
          <h2 style={{ marginTop: 0 }}>Enter the agent's code</h2>
          <p>A code was sent by SMS to the agent ({sp.sentTo}) for the {sp.what}. Ask them to read it to you. Never ask for it over the phone.</p>
          {hidden({ challengeId: sp.challenge, sentTo: sp.sentTo ?? '', what: sp.what ?? '' })}
          <label>6-digit code<input name="code" inputMode="numeric" pattern="\d{6}" autoComplete="one-time-code" required /></label>
          <button type="submit">Confirm</button>
        </form>
      ) : null}

      {isManager ? (
        <>
          <h2>Stock requests</h2>
          {requests.filter((r) => r.status === 'pending').length === 0 ? <p className="muted">No pending requests.</p> : null}
          {requests.filter((r) => r.status === 'pending').map((r) => (
            <div key={r.id} className="panel">
              <strong>{r.profiles?.full_name}</strong>: {r.stock_request_lines.map((l) => `${skus.get(l.sku_id)?.code} ${showQty(l.qty_pieces, skus.get(l.sku_id))}`).join(', ')}
              {r.note ? <span className="muted"> · "{r.note}"</span> : null}
              <form action={decideRequest} className="inline" style={{ marginTop: 8 }}>
                {hidden({ requestId: r.id })}
                <button name="decision" value="approve" type="submit">Approve</button>
                <input name="reason" placeholder="reason to reject" />
                <button name="decision" value="reject" className="danger" type="submit">Reject</button>
              </form>
            </div>
          ))}
        </>
      ) : null}

      <h2>Agent shipments</h2>
      {push.length === 0 ? <p className="muted">None in progress.</p> : push.map((s) => {
        const held = balances.filter((b) => b.location_id === s.carrier_location_id && b.on_hand > 0);
        return (
          <div key={s.id} className="panel">
            <strong>{who.get(s.carrier_location_id)}</strong> · <Status value={s.status} />
            {s.status_note ? <div className="flash err">{s.status_note}</div> : null}
            <div className="muted">Approved: {lines.filter((l) => l.shipment_id === s.id).map((l) => `${skus.get(l.sku_id)?.code} ${l.qty_pieces} pcs`).join(', ')}</div>
            {s.status === 'awaiting_acceptance' ? (
              <form action={startHandover} style={{ marginTop: 8 }}>{hidden({ shipmentId: s.id })}
                <button type="submit">Count with the agent, then send handover code</button></form>
            ) : null}
            {s.status === 'open' || s.status === 'returning' ? (
              <form action={startReturn} className="inline" style={{ marginTop: 8 }}>{hidden({ shipmentId: s.id })}
                {held.map((b) => (
                  <span key={b.sku_id} style={{ display: 'flex', gap: 6, alignItems: 'end' }}>
                    <label>{skus.get(b.sku_id)?.code} returned (of {b.on_hand})<input name={`r:${b.sku_id}`} inputMode="numeric" defaultValue="0" size={4} /></label>
                    <label>damaged<input name={`d:${b.sku_id}`} inputMode="numeric" defaultValue="0" size={4} /></label>
                  </span>
                ))}
                <button type="submit">Record return count, send code</button>
              </form>
            ) : null}
          </div>
        );
      })}

      {isManager ? (
        <>
          <h2>Offline events needing review ({reviews.length})</h2>
          <p className="muted">Rejected by the server when the agent synced. A sale that really happened can be accepted into variance:
            it is recorded, and the stock it exceeded becomes a pending case against the agent.</p>
          {reviews.map((r) => {
            const lines2 = (r.sync_events?.payload as { lines?: { sku_id: string; qty_pieces: number }[] } | undefined)?.lines ?? [];
            return (
              <div key={r.id} className="panel">
                <strong>{r.profiles?.full_name}</strong> · {r.sync_events?.type} · <span className="badge rejected">{r.reason.replaceAll('_', ' ')}</span>
                <div className="muted">{lines2.map((l) => `${skus.get(l.sku_id)?.code} × ${l.qty_pieces}`).join(', ')} · recorded on the phone {r.sync_events?.client_ts ? new Date(r.sync_events.client_ts).toLocaleString('en-NG') : ''}</div>
                <form action={acceptIntoVariance} className="inline" style={{ marginTop: 8 }}>{hidden({ itemId: r.id })}
                  <label>Note<input name="note" required /></label>
                  {r.sync_events?.type === 'sale.recorded' ? <button type="submit">Accept into variance</button> : null}
                  <button formAction={dismissReview} className="secondary" type="submit">Dismiss</button>
                </form>
              </div>
            );
          })}

          <h2>Variance awaiting approval</h2>
          {cases.length === 0 ? <p className="muted">None.</p> : cases.map((c) => (
            <div key={c.id} className="panel">
              <strong>{whoByUser.get(c.carrier_user_id)}</strong>: {c.qty_pieces} × {skus.get(c.sku_id)?.name}{' '}
              {c.kind === 'unrecorded_stock' ? 'sold beyond recorded stock' : `unaccounted for (${formatNaira(kobo(c.value_kobo ?? '0'))})`}
              <form action={resolveVariance} className="inline" style={{ marginTop: 8 }}>{hidden({ caseId: c.id })}
                <label>Note<input name="note" required /></label>
                {c.kind === 'unrecorded_stock' ? (
                  <>
                    <button name="decision" value="link_handover" type="submit">Link to a missed handover</button>
                    <button name="decision" value="write_off" className="secondary" type="submit">Accept as is</button>
                  </>
                ) : (
                  <>
                    <button name="decision" value="write_off" className="secondary" type="submit">Write off</button>
                    <button name="decision" value="charge_agent" type="submit">Charge agent</button>
                  </>
                )}
              </form>
            </div>
          ))}
        </>
      ) : null}
    </>
  );
}
