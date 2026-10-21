# ADR-0005: KYC provider and the KycProvider interface
- Status: Accepted (interface + mock built in Phase 3; real adapter not built)
- Date: 2026-10-21
- Related: [ADR-0002](0002-regulatory-findings-2026-10.md) (NDPA minimisation, F6 tiered KYC)

## Context
Retailers (and later agents) must be verified against BVN and/or NIN. Constraints:
- **Store only status + provider reference + hash** (ADR-0002). Never raw BVN/NIN, never biometrics.
- NDPA s.24(1)(c) "limited to the minimum necessary". We need a yes/no/partial **match** of the details the
  customer gave us. We don't need the government record. A provider that returns the full record (names,
  DOB, phone, **photo**) makes us process sensitive biometric data (s.65) we have no use for.
- Partners (licensed institutions) carry the CBN tiered-KYC obligations. We mirror verification status and
  must not undermine theirs.

## What the current docs show (read 2026-10-21)
| | Dojah | Smile ID | Youverify |
|---|---|---|---|
| BVN match-only | ✅ `GET /api/v1/kyc/bvn` with `bvn`, optional `first_name`, `last_name`, `dob`. Returns per-field `status` booleans + `confidence_value`, BVN masked (`2*****89012`). Headers `Authorization` (secret, no Bearer) + `AppId`. Sandbox `https://sandbox.dojah.io`, live `https://api.dojah.io`, test BVN `22222222222` | ✅ Basic KYC `POST /v2/verify` (sync) or `/v2/verify_async` (callback). `id_type` `BVN` listed for NG. Result `ResultCode` 1020 Exact / 1021 Partial / 1022 No Match, `Actions` per field. Sandbox `https://testapi.smileidentity.com`, prod `https://api.smileidentity.com` | ❌ `POST /v2/api/identity/ng/bvn` (header `token`, body `id`, `isSubjectConsent: true`) **returns names and a base64 photo** |
| NIN match-only | ❌ only lookup `GET /api/v1/kyc/nin`, which **returns full record incl. photo**. No match endpoint found | ✅ same Basic KYC call, `id_type` `NIN_V2` (11 digits) | ❌ NIN endpoint exists (not read in detail). Same full-record pattern assumed, **unverified** |
| Unverified items | – | **request signature algorithm** (legacy docs say "every request must be signed" but the algorithm page wasn't read). V3 docs are "coming soon" and only the legacy (v2) REST docs exist | NIN response shape |

Sources:
- https://docs.dojah.io/docs/nigeria/validate-bvn.md (read)
- https://docs.dojah.io/docs/nigeria/lookup-nin.md (read)
- https://legacy-docs.usesmileid.com/products/for-individuals-kyc/basic-kyc (read)
- https://legacy-docs.usesmileid.com/supported-id-types/for-individuals-kyc/backed-by-id-authority (read)
- https://legacy-docs.usesmileid.com/integration-options/rest-api/signing-your-api-request (read; algorithm on a linked page, **not read**)
- https://docs.usesmileid.com/products/onboarding-without-biometrics/basic-kyc.md (read; V3 placeholder)
- https://doc.youverify.co/api-reference/quickcheck/kyc--nigeria/verify-bank-verification-number-bvn.md (read)

## Decision
1. **Interface is match-only.** `KycProvider.verifyIdentity({ idType: 'BVN' | 'NIN', idNumber, firstName,
   lastName, dateOfBirth? })` returns `{ outcome: 'exact_match' | 'partial_match' | 'no_match' |
   'not_found', providerRef, fieldResults }`. Errors are thrown as typed `KycProviderError` (retryable or
   not). The interface never exposes a returned name, DOB, phone or image, so an adapter physically can't
   leak them to callers.
2. **Preferred real provider: Smile ID Basic KYC.** It's the only one with match-only verification for
   **both** BVN and NIN in the docs read. Before an adapter is written: read the signature-generation page
   and the then-current (V3) docs. Until then the adapter is **unverified** and not built.
3. **Fallback: Dojah BVN validate** (fully verified shape, match-only) for BVN-only operation. Dojah NIN
   is rejected because it returns a photo.
4. **Youverify rejected** for this use: the BVN endpoint returns names + photo by default.
5. **What we store** (`kyc_checks`): id type, outcome, provider, provider reference, and an
   `HMAC-SHA256(pepper, idType || ':' || idNumber)` hex digest. The digest is computed **in the server-side
   adapter**, so the raw number never reaches the database. It lets us detect one BVN registering many shops
   without storing the number. The pepper is a server secret (`KYC_ID_PEPPER`), rotated by re-verification.
6. **Tiered KYC limits are not encoded.** Vendor sources (youverify.co blogs, businessday.ng) give
   conflicting figures and the CBN circular wasn't read. We derive a coarse `kyc_level` instead:
   `0` none, `1` one of BVN/NIN matched, `2` both matched. Business rules (credit eligibility in Phase 5b)
   reference the level through configuration, not hard-coded naira limits.
7. **Geolocation** (SPEC §1 "KYC … and geolocation"): the shop's location is captured at registration with
   GPS accuracy. A distributor approver confirms it on approval. No continuous tracking.

8. **Where the adapter runs:** in the Next.js server runtime (a server action) with the service_role
   key, which is granted EXECUTE on `app.record_kyc_result` and nothing else. It could equally be an
   Edge Function. It holds no business rules, and the subject is always the signed-in user, re-checked
   against their memberships before any provider call.

## Consequences
- The mock (`MockKycProvider`) implements deterministic outcomes from the ID number so tests and demos are
  reproducible. A contract test suite runs against any implementation, so the real adapter must pass the
  same tests in sandbox mode.
- A partial match is stored as `partial_match` and counts as **not verified** until a manager reviews it.
  That's a conservative default.
