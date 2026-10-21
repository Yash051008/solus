// User-scoped repository: every call runs as the signed-in user, so RLS and app.* authorisation apply.
import type { ActiveMembership, MemberRole } from '@solus/core';
import type { DbClient, Enums } from './client.ts';
import { command, rows } from './client.ts';

export type Membership = ActiveMembership & {
  orgName: string;
  orgKind: Enums['org_kind'];
  branchId: string | null;
  territoryId: string | null;
};

export function createRepository(db: DbClient) {
  return {
    me: {
      async userId(): Promise<string | null> {
        const { data } = await db.auth.getUser();
        return data.user?.id ?? null;
      },
      async memberships(): Promise<Membership[]> {
        const userId = await this.userId();
        if (userId === null) return [];
        const list = rows(await db.from('memberships')
          .select('role, org_id, status, branch_id, territory_id, organisations(name, kind)')
          .eq('user_id', userId));
        return list.map((m) => ({
          role: m.role as MemberRole,
          orgId: m.org_id,
          status: m.status as ActiveMembership['status'],
          branchId: m.branch_id,
          territoryId: m.territory_id,
          orgName: m.organisations?.name ?? '',
          orgKind: m.organisations?.kind ?? 'retailer',
        }));
      },
      async joinRequests() {
        const userId = await this.userId();
        if (userId === null) return [];
        return rows(await db.from('join_requests')
          .select('id, org_id, requested_role, status, decision_reason, created_at, organisations(name)')
          .eq('user_id', userId).order('created_at', { ascending: false }));
      },
      upsertProfile: (fullName: string, phoneE164: string) =>
        command(db, 'upsert_my_profile', { p_full_name: fullName, p_phone_e164: phoneE164 }),
    },

    registration: {
      directory: () => command(db, 'registration_directory', {}),
      registerRetailer: (i: {
        businessName: string; fullName: string; phoneE164: string;
        lat: number; lng: number; accuracyM: number; distributorId: string;
      }) => command(db, 'register_retailer', {
        p_business_name: i.businessName, p_full_name: i.fullName, p_phone_e164: i.phoneE164,
        p_lat: i.lat, p_lng: i.lng, p_accuracy_m: Math.round(i.accuracyM), p_distributor_id: i.distributorId,
      }),
      requestToJoin: (i: { distributorId: string; role: Enums['member_role']; fullName: string; phoneE164: string; note?: string }) =>
        command(db, 'request_to_join', {
          p_distributor_id: i.distributorId, p_role: i.role, p_full_name: i.fullName, p_phone_e164: i.phoneE164,
          ...(i.note === undefined ? {} : { p_note: i.note }),
        }),
      requestDistributor: (retailerOrgId: string, distributorId: string) =>
        command(db, 'request_distributor', { p_retailer_org_id: retailerOrgId, p_distributor_id: distributorId }),
    },

    approvals: {
      async pendingCustomers(distributorId: string) {
        return rows(await db.from('customer_relationships')
          .select('id, retailer_org_id, territory_id, created_at, status')
          .eq('distributor_org_id', distributorId).eq('status', 'pending').order('created_at'));
      },
      async pendingJoinRequests(distributorId: string) {
        return rows(await db.from('join_requests')
          .select('id, user_id, requested_role, note, created_at, profiles!join_requests_user_id_fkey(full_name, phone_e164)')
          .eq('org_id', distributorId).eq('status', 'pending').order('created_at'));
      },
      decideCustomer: (i: { relationshipId: string; approve: boolean; territoryId?: string; reason?: string }) =>
        command(db, 'decide_customer', {
          p_relationship_id: i.relationshipId, p_approve: i.approve,
          ...(i.territoryId === undefined ? {} : { p_territory_id: i.territoryId }),
          ...(i.reason === undefined ? {} : { p_reason: i.reason }),
        }),
      decideJoinRequest: (i: { requestId: string; approve: boolean; branchId?: string; territoryId?: string; reason?: string }) =>
        command(db, 'decide_join_request', {
          p_request_id: i.requestId, p_approve: i.approve,
          ...(i.branchId === undefined ? {} : { p_branch_id: i.branchId }),
          ...(i.territoryId === undefined ? {} : { p_territory_id: i.territoryId }),
          ...(i.reason === undefined ? {} : { p_reason: i.reason }),
        }),
    },

    organisations: {
      async byIds(ids: readonly string[]) {
        if (ids.length === 0) return [];
        return rows(await db.from('v_organisations').select('*').in('id', [...ids]));
      },
      async byKind(kind: Enums['org_kind']) {
        return rows(await db.from('v_organisations').select('*').eq('kind', kind).order('name'));
      },
      onboard: (i: { kind: Enums['org_kind']; name: string; slug: string; adminUserId: string }) =>
        command(db, 'onboard_organisation', { p_kind: i.kind, p_name: i.name, p_slug: i.slug, p_admin_user_id: i.adminUserId }),
    },

    structure: {
      async branches(orgId: string) {
        return rows(await db.from('branches').select('id, name').eq('org_id', orgId).order('name'));
      },
      async territories(orgId: string) {
        return rows(await db.from('v_territories').select('*').eq('org_id', orgId).order('name'));
      },
      async warehouses(orgId: string) {
        return rows(await db.from('v_warehouses').select('*').eq('org_id', orgId).order('name'));
      },
      createBranch: (orgId: string, name: string) => command(db, 'create_branch', { p_org_id: orgId, p_name: name }),
      createTerritory: (branchId: string, name: string, boundaryGeoJson?: unknown) =>
        command(db, 'create_territory', {
          p_branch_id: branchId, p_name: name,
          ...(boundaryGeoJson === undefined ? {} : { p_boundary: boundaryGeoJson as never }),
        }),
      createWarehouse: (branchId: string, name: string, lat: number, lng: number) =>
        command(db, 'create_warehouse', { p_branch_id: branchId, p_name: name, p_lat: lat, p_lng: lng }),
      setWarehouseActive: (warehouseId: string, active: boolean) =>
        command(db, 'set_warehouse_active', { p_warehouse_id: warehouseId, p_active: active }),
      updateSettings: (orgId: string, s: { splitThresholdM: number | null; geofenceRadiusM: number | null; geofenceMaxAccuracyM: number | null }) =>
        command(db, 'update_distributor_settings', {
          p_org_id: orgId,
          p_split_threshold_m: s.splitThresholdM as number,
          p_geofence_radius_m: s.geofenceRadiusM as number,
          p_geofence_max_accuracy_m: s.geofenceMaxAccuracyM as number,
        }),
    },

    retailer: {
      async relationships(retailerOrgId: string) {
        return rows(await db.from('customer_relationships')
          .select('id, distributor_org_id, status, decision_reason, credit_limit_kobo, organisations!customer_relationships_distributor_org_id_distributor_kind_fkey(name)')
          .eq('retailer_org_id', retailerOrgId));
      },
      async kycChecks(orgId: string) {
        return rows(await db.from('kyc_checks').select('id, id_type, outcome, provider, checked_at')
          .eq('org_id', orgId).order('checked_at', { ascending: false }));
      },
      kycLevel: (orgId: string) => command(db, 'kyc_level', { p_org_id: orgId }),
    },

    geofence: {
      check: (i: { distributorId: string; retailerOrgId: string; lat: number; lng: number; accuracyM: number }) =>
        command(db, 'check_geofence', {
          p_distributor_id: i.distributorId, p_retailer_org_id: i.retailerOrgId,
          p_lat: i.lat, p_lng: i.lng, p_accuracy_m: i.accuracyM,
        }),
    },
  };
}

export type Repository = ReturnType<typeof createRepository>;
