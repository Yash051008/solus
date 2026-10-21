// ADVISORY geofence for instant UX feedback on devices. The authoritative check is server-side
// (app.evaluate_geofence, PostGIS spheroid distance). Same rules, same fail-closed behaviour.

export type LatLng = { lat: number; lng: number };

export type GeofenceReason = 'ok' | 'outside_radius' | 'low_accuracy';

export type GeofenceResult = { ok: boolean; reason: GeofenceReason; distanceM: number };

const EARTH_MEAN_RADIUS_M = 6_371_008.8;

export function assertLatLng(p: LatLng): void {
  if (!Number.isFinite(p.lat) || !Number.isFinite(p.lng) || Math.abs(p.lat) > 90 || Math.abs(p.lng) > 180) {
    throw new RangeError(`invalid coordinates (${p.lat}, ${p.lng})`);
  }
}

/** Great-circle distance on a sphere. Within ~0.5% of the spheroid distance PostGIS computes. */
export function haversineMeters(a: LatLng, b: LatLng): number {
  assertLatLng(a);
  assertLatLng(b);
  const rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad;
  const dLng = (b.lng - a.lng) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_MEAN_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

export const GEOFENCE_DEFAULTS = { radiusM: 150, maxAccuracyM: 50 } as const;

export function advisoryGeofence(input: {
  shop: LatLng;
  fix: LatLng;
  accuracyM: number | null;
  radiusM?: number;
  maxAccuracyM?: number;
}): GeofenceResult {
  const radiusM = input.radiusM ?? GEOFENCE_DEFAULTS.radiusM;
  const maxAccuracyM = input.maxAccuracyM ?? GEOFENCE_DEFAULTS.maxAccuracyM;
  const distanceM = Math.round(haversineMeters(input.shop, input.fix));
  if (input.accuracyM === null || !Number.isFinite(input.accuracyM) || input.accuracyM < 0 || input.accuracyM > maxAccuracyM) {
    return { ok: false, reason: 'low_accuracy', distanceM };
  }
  if (distanceM > radiusM) return { ok: false, reason: 'outside_radius', distanceM };
  return { ok: true, reason: 'ok', distanceM };
}
