'use server';
import { getRepo } from '@/lib/supabase/server';
import { mutate, num, optionalInt, optionalText, text } from '@/lib/forms';

const back = (fd: FormData, page: string) => `/distributor/${text(fd, 'orgId')}/${page}`;

export async function decideCustomer(fd: FormData) {
  const approve = text(fd, 'decision') === 'approve';
  await mutate(back(fd, 'approvals'), async () => {
    const repo = await getRepo();
    const territoryId = optionalText(fd, 'territoryId');
    const reason = optionalText(fd, 'reason');
    await repo.approvals.decideCustomer({
      relationshipId: text(fd, 'relationshipId'), approve,
      ...(territoryId === undefined ? {} : { territoryId }),
      ...(reason === undefined ? {} : { reason }),
    });
  }, approve ? 'Customer approved.' : 'Customer rejected.');
}

export async function decideJoinRequest(fd: FormData) {
  const approve = text(fd, 'decision') === 'approve';
  await mutate(back(fd, 'approvals'), async () => {
    const repo = await getRepo();
    const branchId = optionalText(fd, 'branchId');
    const territoryId = optionalText(fd, 'territoryId');
    const reason = optionalText(fd, 'reason');
    await repo.approvals.decideJoinRequest({
      requestId: text(fd, 'requestId'), approve,
      ...(branchId === undefined ? {} : { branchId }),
      ...(territoryId === undefined ? {} : { territoryId }),
      ...(reason === undefined ? {} : { reason }),
    });
  }, approve ? 'Request approved.' : 'Request rejected.');
}

export async function createBranch(fd: FormData) {
  await mutate(back(fd, 'structure'), async () => {
    await (await getRepo()).structure.createBranch(text(fd, 'orgId'), text(fd, 'name'));
  }, 'Branch created.');
}

export async function createTerritory(fd: FormData) {
  await mutate(back(fd, 'structure'), async () => {
    const raw = optionalText(fd, 'boundary');
    let boundary: unknown;
    if (raw !== undefined) {
      try {
        boundary = JSON.parse(raw);
      } catch {
        throw new RangeError('boundary must be valid GeoJSON');
      }
    }
    await (await getRepo()).structure.createTerritory(text(fd, 'branchId'), text(fd, 'name'), boundary);
  }, 'Territory created.');
}

export async function createWarehouse(fd: FormData) {
  await mutate(back(fd, 'structure'), async () => {
    await (await getRepo()).structure.createWarehouse(text(fd, 'branchId'), text(fd, 'name'), num(fd, 'lat'), num(fd, 'lng'));
  }, 'Warehouse created.');
}

export async function setWarehouseActive(fd: FormData) {
  const active = text(fd, 'active') === 'true';
  await mutate(back(fd, 'structure'), async () => {
    await (await getRepo()).structure.setWarehouseActive(text(fd, 'warehouseId'), active);
  }, active ? 'Warehouse activated.' : 'Warehouse deactivated.');
}

export async function updateSettings(fd: FormData) {
  await mutate(back(fd, 'settings'), async () => {
    await (await getRepo()).structure.updateSettings(text(fd, 'orgId'), {
      splitThresholdM: optionalInt(fd, 'splitThresholdM'),
      geofenceRadiusM: optionalInt(fd, 'geofenceRadiusM'),
      geofenceMaxAccuracyM: optionalInt(fd, 'geofenceMaxAccuracyM'),
    });
  }, 'Settings saved.');
}

/** Read-only probe of the server-side geofence; a FAIL is reported as an error flash. */
export async function testGeofence(fd: FormData) {
  let summary = 'Geofence check returned no result';
  await mutate(back(fd, 'settings'), async () => {
    const [r] = await (await getRepo()).geofence.check({
      distributorId: text(fd, 'orgId'), retailerOrgId: text(fd, 'retailerOrgId'),
      lat: num(fd, 'lat'), lng: num(fd, 'lng'), accuracyM: num(fd, 'accuracy'),
    });
    if (!r) throw new RangeError(summary);
    summary = `Geofence ${r.ok ? 'PASS' : 'FAIL'} (${r.reason.replaceAll('_', ' ')}): ${r.distance_m ?? '?'} m from the shop; `
      + `radius ${r.radius_m} m, max GPS accuracy ${r.max_accuracy_m} m.`;
    if (!r.ok) throw new RangeError(summary);
  }, 'Geofence PASS: inside the radius with an acceptable GPS fix.');
}
