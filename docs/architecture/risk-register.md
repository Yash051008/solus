# Risk register

L = likelihood, I = impact (H/M/L). "Phase" is where the mitigation is built and tested.

| # | Risk | L | I | Mitigation | Proof / test | Phase |
|---|---|---|---|---|---|---|
| R1 | **Oversell** under concurrent orders | H | H | single `app.reserve_order` with `FOR UPDATE` in fixed lock order; `reserved <= on_hand` CHECK as backstop | 50-vs-10 parallel `pg` Pool test | 2 |
| R2 | **Projection drift** (`stock_balances`/`account_balances` ≠ ledger) | M | H | trigger-only writes, no client grants, CHECKs | rebuild-from-ledger equality tests | 2 |
| R3 | **Unbalanced journal** | L | H | deferred constraint trigger: zero-sum per book per journal | pgTAP: insert unbalanced journal → commit fails | 2 |
| R4 | **Duplicate webhook / replay** double-credits a wallet | H | H | unique `(provider, provider_ref)`; journal idempotency key; signature verify; 200 on duplicate | duplicate-webhook test (one credit, second logged) | 5b |
| R5 | **Webhook lost** (adapter or DB down, partner gives up) | M | H | adapter returns 5xx on DB error so the partner retries; daily statement reconciliation turns gaps into review items | reconciliation test with a missing event | 5b |
| R6 | **Offline divergence**: physical sales the ledger can't accept | H | H | event sourcing from devices, review queue, accept-into-variance, close blocking | airplane-mode scenario + 60-vs-50 test | 5b |
| R7 | **Silent drop** of rejected events | M | H | rejected events persisted with reason + review item in the same txn; app shows them | test: every rejected event has an open review item | 5b |
| R8 | **Cross-tenant data leak** | M | H | RLS on every table via helper functions, no direct table writes, security-definer functions with `search_path=''` | pgTAP: distributor A agent sees 0 rows of B across all tables | 2 |
| R9 | **OTP brute force / reuse** | M | H | bcrypt hash, 5-min expiry, 5 attempts then `locked`, bound to subject + both parties, codes never returned to clients | pgTAP OTP suite (expiry, lockout, wrong party, replay) | 2 / 5a |
| R10 | **Collusion** (staff + agent fake a handover/return) | M | M | separation-of-duties checks, audit log, variance trends per agent/staff pair on dashboard | pgTAP SoD tests; dashboard in 6 | 2 / 6 |
| R11 | **GPS spoofing** defeats geofence | M | M | server-side distance check, accuracy threshold, mock-location flag from device, visit-pattern anomaly report | geofence unit tests; anomaly report later | 3 / 6 |
| R12 | **Device clock skew** misorders events or periods | H | M | ordering by `seq` + `recorded_at`; `client_ts` informational only | sync tests with skewed clocks | 5b |
| R13 | **Float/precision creep** in TS or JSON | M | H | bigint kobo; money as strings in JSON; lint rule bans `parseFloat`/`Number()` on money types; `round_div` only | type tests + SQL/TS round_div contract test | 2 / 5b |
| R14 | **Data-residency deadline** (CBN, 1 Jan 2027) reached with real payment data offshore | M | H | ADR-0001 hard gate: no real payment data offshore; portability rules; Nigeria-hosted Postgres before go-live | go-live checklist in ADR-0001 | ongoing |
| R15 | **Regulatory misread** (circular scope, KYC coverage) | M | H | ADR-0002 separates confirmed from secondary; human obtains primary PDF; legal review before go-live | ADR-0002 status table | ongoing |
| R16 | **Partner outage / lock-in** (payments, KYC, SMS) | M | M | TS interfaces + mocks + contract tests; provider ref stored, not provider shape | contract tests per provider | 3 / 5b |
| R17 | **Credit over-limit** via concurrent draws | M | H | `customer_relationships` row lock + re-check inside the OTP-verified txn | parallel credit-draw test | 5b |
| R18 | **PII over-collection** (BVN/NIN, faces in photos) | M | H | store KYC status + ref + hash only; no biometrics; photo guidance + retention schedule | schema review + pgTAP column checks | 3 / 4 |
| R19 | **Audit tampering** | L | H | append-only audit table; trigger rejects UPDATE/DELETE; no grants | pgTAP: UPDATE/DELETE on audit_log fail for every client role and for the function-owner role (trigger) | 2 |
| R20 | **Supabase-specific lock-in** blocks migration to NG hosting | M | M | `app.current_user_id()` seam, plain SQL migrations, repo layer, thin Edge adapters; Realtime optional | migration rehearsal on plain Postgres before go-live | 2 / 6 |
