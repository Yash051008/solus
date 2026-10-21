import { GEOFENCE_DEFAULTS } from '@solus/core';
import { Flash, type FlashParams } from '@/components/shell';
import { requireOrgRole } from '@/lib/session';
import { testGeofence, updateSettings } from '../actions';

export default async function SettingsPage({ params, searchParams }: {
  params: Promise<{ orgId: string }>;
  searchParams: FlashParams;
}) {
  const { orgId } = await params;
  const { ok, error } = await searchParams;
  const { repo } = await requireOrgRole(orgId, ['distributor_admin']);
  const [[org], retailers] = await Promise.all([repo.organisations.byIds([orgId]), repo.organisations.byKind('retailer')]);
  const activeRetailers = retailers.filter((r) => r.status === 'active');

  return (
    <>
      <h1>Settings</h1>
      <Flash ok={ok} error={error} />
      <section className="panel">
        <h2>Routing and geofence</h2>
        <form action={updateSettings} className="stack">
          <input type="hidden" name="orgId" value={orgId} />
          <label>Split-order threshold (metres extra travel before offering a split)
            <input name="splitThresholdM" inputMode="numeric" defaultValue={org?.split_threshold_m ?? ''} />
          </label>
          <label>Geofence radius (metres, default {GEOFENCE_DEFAULTS.radiusM})
            <input name="geofenceRadiusM" inputMode="numeric" defaultValue={org?.geofence_radius_m ?? ''} />
          </label>
          <label>Maximum GPS accuracy accepted (metres, default {GEOFENCE_DEFAULTS.maxAccuracyM})
            <input name="geofenceMaxAccuracyM" inputMode="numeric" defaultValue={org?.geofence_max_accuracy_m ?? ''} />
          </label>
          <button type="submit">Save</button>
        </form>
      </section>

      <section className="panel">
        <h2>Test the geofence</h2>
        <p className="muted">Runs the same server-side check agents' visits will use. A poor GPS fix always fails.</p>
        <form action={testGeofence} className="inline">
          <input type="hidden" name="orgId" value={orgId} />
          <label>Shop
            <select name="retailerOrgId" required>
              {activeRetailers.map((r) => <option key={r.id} value={r.id ?? ''}>{r.name}</option>)}
            </select>
          </label>
          <label>Latitude<input name="lat" inputMode="decimal" required /></label>
          <label>Longitude<input name="lng" inputMode="decimal" required /></label>
          <label>Accuracy (m)<input name="accuracy" inputMode="numeric" defaultValue="10" required /></label>
          <button type="submit">Check</button>
        </form>
      </section>
    </>
  );
}
