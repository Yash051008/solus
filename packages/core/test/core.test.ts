import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  kobo, nairaToKobo, formatNaira, toPieces, splitPieces, formatPieces,
  haversineMeters, advisoryGeofence, domainCodeFor, homePathFor,
} from '../src/index.ts';

test('money: parsing and formatting never touch floats', () => {
  assert.equal(nairaToKobo('1,234.56'), 123456n);
  assert.equal(nairaToKobo('1234.5'), 123450n);
  assert.equal(nairaToKobo('0.05'), 5n);
  assert.equal(nairaToKobo('-10'), -1000n);
  assert.equal(nairaToKobo('92233720368547758.07'), 9223372036854775807n, 'max bigint is exact');
  assert.throws(() => nairaToKobo('1.234'), RangeError, 'three decimals rejected');
  assert.throws(() => nairaToKobo('1,23.00'), RangeError, 'bad grouping rejected');
  assert.throws(() => nairaToKobo('abc'), RangeError);
  assert.equal(formatNaira(kobo('123456')), '₦1,234.56');
  assert.equal(formatNaira(kobo(-5n)), '-₦0.05');
  assert.equal(formatNaira(kobo('100000000000')), '₦1,000,000,000.00');
  assert.throws(() => kobo('12.5'), RangeError);
});

test('uom: cartons convert to pieces exactly and display back', () => {
  assert.equal(toPieces(30, 24), 720);
  assert.throws(() => toPieces(1.5, 24), RangeError);
  assert.throws(() => toPieces(0, 24), RangeError);
  assert.deepEqual(splitPieces(100, 24), { units: 4, remainder: 4 });
  assert.equal(formatPieces(100, 24), '4 ctn + 4 pcs');
  assert.equal(formatPieces(96, 24), '4 ctn');
  assert.equal(formatPieces(5, 24), '5 pcs');
  assert.equal(formatPieces(7, 1), '7 pcs');
});

test('geo: advisory geofence mirrors the server rules (fails closed)', () => {
  const shop = { lat: 6.62, lng: 3.345 };
  assert.ok(Math.abs(haversineMeters(shop, { lat: 6.6209, lng: 3.345 }) - 100) < 1, '0.0009 deg lat is ~100 m');
  assert.deepEqual(advisoryGeofence({ shop, fix: shop, accuracyM: 10 }), { ok: true, reason: 'ok', distanceM: 0 });
  assert.equal(advisoryGeofence({ shop, fix: { lat: 6.6227, lng: 3.345 }, accuracyM: 10 }).reason, 'outside_radius');
  assert.equal(advisoryGeofence({ shop, fix: shop, accuracyM: 80 }).reason, 'low_accuracy');
  assert.equal(advisoryGeofence({ shop, fix: shop, accuracyM: null }).reason, 'low_accuracy');
  assert.equal(advisoryGeofence({ shop, fix: { lat: 6.6227, lng: 3.345 }, accuracyM: 80, radiusM: 500, maxAccuracyM: 100 }).ok, true);
  assert.throws(() => haversineMeters(shop, { lat: 91, lng: 0 }), RangeError);
});

test('errors: SQLSTATE maps to domain codes', () => {
  assert.equal(domainCodeFor('SOL01'), 'insufficient_stock');
  assert.equal(domainCodeFor('SOL03'), 'forbidden');
  assert.equal(domainCodeFor('23514'), 'unexpected');
  assert.equal(domainCodeFor(undefined), 'unexpected');
});

test('roles: landing route by broadest active membership', () => {
  assert.equal(homePathFor([]), '/onboarding');
  assert.equal(homePathFor([{ role: 'retailer', orgId: 'r1', status: 'active' }]), '/retailer/r1');
  assert.equal(homePathFor([{ role: 'agent', orgId: 'd1', status: 'active' }]), '/field');
  assert.equal(
    homePathFor([
      { role: 'retailer', orgId: 'r1', status: 'active' },
      { role: 'branch_manager', orgId: 'd1', status: 'active' },
    ]),
    '/distributor/d1',
  );
  assert.equal(homePathFor([{ role: 'distributor_admin', orgId: 'd1', status: 'suspended' }]), '/onboarding');
  assert.equal(homePathFor([{ role: 'platform_admin', orgId: 'p', status: 'active' }]), '/platform');
});
