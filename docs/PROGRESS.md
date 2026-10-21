# Progress

| Phase | Scope | Status | Date |
|---|---|---|---|
| 1 | CLAUDE.md, architecture, flows, events, risks, hosting + regulatory ADRs | Done | 2026-10-21 |
| 2 | Schema, migrations, ledgers + projections, RLS, seed, invariant/RLS/concurrency tests | Done | 2026-10-21 |
| 3 | Auth, per-role routing, registration + approval, KYC interface + mock, geofence, branch/territory/warehouse mgmt | Done | 2026-10-21 |
| 4 | Catalogue, inventory, transfers, pull flow + routing, batching/packing UI, delivery + e-POD + partial/missing | **Done** (4a DB `9278024`, 4b screens `4c4fcc9`..`6bd1df1`) | 2026-10-21 |
| 5a | Push: request → approve → OTP handover → return → reconciliation (variance approval, close blocking) | **Done** (`7520c72`, `f04d1de`, `b9911bc`) | 2026-10-22 |
| 5b | Wallet ledger, trade credit + credit OTP, payment webhooks + reconciliation, offline agent app + sync | Not started | |
| 6 | Dashboards, notifications, support tickets, hardening, E2E of both flows on the same stock | Not started | |

## ▶ Resume here
- **Next up: Phase 5b.** Wallet ledger + payment provider research (ADR-0008: Paystack DVA / Monnify /
  Flutterwave), signed idempotent webhooks (duplicate test), wallet/credit settlement with credit OTP
  (`otp_challenges` purpose `credit` is already reserved), cash remittance, and the Expo offline agent app
  with event sync and accept-into-variance (`app.apply_push_sale` is the core the sync path will call).
- Last verified: `npm run test:all` passes from clean at `b9911bc` (530 pgTAP, 30 Node tests,
  typecheck, web build).
- Run locally: `npm run db:start` → `npm run db:reset` → `npm run web:env` →
  `npm run dev --workspace @solus/web` → http://localhost:3100. Password `SolusDev-2026!` for
  `retailer01@`, `lp.wh.ikeja@`, `lp.driver1@`, `lp.agent2@`, `lp.bm.ikeja@`, `lp.admin@` (`@solus.test`).
  With the mock SMS provider, the agent's /field page shows the code "received by SMS".
- Working style: gated steps, short replies, typecheck + browser check + commit per step, stop for "next".

## Phase 5a: what exists
- ADR-0006: our own OTPs. bcrypt-hashed, 5-minute expiry, 5 attempts, max 3 issues, initiator-only,
  bound to the subject and (for returns) the exact count. Termii preferred (dnd route), Africa's Talking
  unverified.
- DB:
  - `private.otp_challenges`, `issue_otp_code` (service_role only), `verify_otp` (failures are returned, not raised)
  - stock requests and approval (separation of duties, one active shipment per agent)
  - OTP handover; geofenced online push sales (`apply_push_sale` core, `cash_collected` journal)
  - OTP-bound returns with damage
  - `variance_cases` with `variance_raised` journals for push and delivery runs
  - `resolve_variance` (write off / charge agent) and close blocking
  - seed runs the spec example (100 = 70 + 25 + 3 + 2) per distributor
- Tests: `010_push_flow` (39 assertions); SMS contract suite plus the OTP send adapter test.
- Web: distributor **Agent stock** page (approve, OTP handover/return, enter code, resolve variance) and
  agent panel on `/field` (request stock, dev SMS inbox, geofenced cash sale). Browser-checked
  2026-10-22: request → approve → wrong code rejected ("4 attempts left", form kept) → right code →
  handover; sale refused away from the shop, accepted at it (₦1,800); seeded variance written off.
- Known gaps: the agent return → OTP → variance path wasn't clicked through in the browser (covered by
  010 and the seed). Phone verification at registration is still not done. No real SMS adapter yet.

## Phase 4: what exists
- **4a (DB):**
  - catalogue/price commands
  - receipts and adjustments (separation of duties)
  - transfers with shortage resolution
  - `place_order` with nearest-warehouse routing (locks candidate stock rows first; split threshold; decision + reason stored)
  - allocation-based reservation, split decisions, cancellation
  - batch → pack → dispatch → driver accept (two-party)
  - `record_delivery`: e-POD photo required in the `epod` bucket; geofence result stored;
    delivered/refused/damaged/missing per line; cumulative invoicing via `round_div`
  - confirm/dispute; returns (two-party); a shipment stays `reconciling` while the carrier holds stock
  - `check_stock_conservation`; scoped order visibility for branch staff and carriers
  - seed runs a full pull flow per distributor
  - tests: `supabase/tests/009_pull_flow.test.sql` (39 assertions)
- **4b (web):**
  - manufacturer catalogue
  - distributor Stock (receipts, adjustments) and Fulfilment (batch/pack/dispatch, split decisions, return counts)
  - retailer Order + My orders (cancel/confirm/dispute)
  - driver Deliveries (accept/decline, e-POD with photo + GPS, confirm return)
  - each screen browser-checked on 2026-10-21

## Phase 4: known gaps
- Push shipments, OTP handover and variance cases are Phase 5a. Missing pieces at delivery leave the
  shipment `reconciling`, which blocks that carrier's next dispatch until 5a can resolve it.
- Not verified in the browser: return count → driver confirm (covered by 009 + seed). No UI yet for
  transfers or price-list publishing (DB commands exist and are tested).
- The concurrency test still calls `reserve_order` as the owner. A variant through `place_order` as
  authenticated retailers is still to do.
- Disputes are recorded but there is no resolution workflow yet (support tickets, Phase 6).

## Phase 3: what exists
`npm run test:all` now runs: clean reset → 349 pgTAP assertions → typecheck (root + 4 workspaces) →
24 Node tests (unit, KYC contract, concurrency, commit-time invariants, **end-to-end flows through
Supabase Auth + PostgREST as real users**) → Next.js production build.

| Area | Where | Proven by |
|---|---|---|
| ADR-0005 KYC provider research + decision (match-only interface, Smile ID preferred/unverified, Dojah BVN fallback, Youverify rejected) | `docs/adr/0005-kyc-provider.md` | n/a |
| Authorisation helpers for commands (`require_role`, `require_branch_manager`, `make_point`) | `migrations/20261022000200_authz_helpers.sql` | 007 |
| Org structure: onboard org (platform), branches, territories (validated GeoJSON boundary), warehouses (+ stock location), deactivate guard, distributor settings | `…0300_org_structure_commands.sql` | 007 |
| Registration + approval: retailer self-registration with GPS accuracy and territory suggestion, extra distributor requests, customer approve/reject (with reason), staff/agent join requests, SoD (no self-approval, BMs can't appoint BMs, branch-scoped approvals) | `…0100_record_status_rejected.sql`, `…0400_registration.sql`, `…0800_applicant_visibility.sql` | 007, integration |
| KYC storage: append-only `kyc_checks` (outcome + provider ref + HMAC digest, column-level grants hide digest/ref), `kyc_level`, duplicate-identity surfacing, service_role-only recording | `…0500_kyc_geofence.sql`, `…0600_phase3_rls_grants.sql` | 001, 007, integration |
| Geofence: `app.evaluate_geofence` (spheroid distance, configurable radius/accuracy, fails closed), scoped `app.check_geofence` | `…0500_kyc_geofence.sql` | 008, integration |
| Location read views (lat/lng) | `…0700_location_views.sql` | used by UI + integration |
| `@solus/core`: kobo money (bigint, exact parse/format), UoM, advisory geofence, error codes, role routing | `packages/core` | `packages/core/test` |
| `@solus/integrations`: `KycProvider`, `MockKycProvider`, identity digest, `verifyAndRecordKyc`, reusable contract suite | `packages/integrations` | `packages/integrations/test` |
| `@solus/db`: repository layer (user-scoped) + adapter repository (service_role, KYC only), generated DB types | `packages/db` | integration |
| Web app (Next.js 15.5.27): login/signup, role routing, onboarding (shop registration with browser geolocation, join requests), distributor console (approvals, structure, settings + geofence tester), retailer console (distributors, KYC), platform onboarding, manufacturer + field placeholders | `apps/web` | production build; manual browser check below |

**Manual browser check (2026-10-21, local dev on :3100):** anonymous → redirected to /login. Lekki
branch manager → distributor console. Approvals list shows the applicant's name/phone. Trying to place
an agent in the Ikeja branch showed the database's `forbidden` error in the UI. retailer03 → shop console.
BVN check with the mock moved KYC level 0 → 1. Server logs: no errors, and the ID number appears nowhere.

**Bugs found by Phase 3 tests and fixed:**
- KYC "latest attempt" ordered by `checked_at`, which is identical inside one transaction. Now ordered by
  an identity `seq`.
- Approvers couldn't see applicants' names (no membership yet means no profile visibility). Applicants
  with a join request are now visible to that org's admins/BMs, and only to them (pgTAP + integration).

## Phase 3: known gaps
- **Real KYC adapter not built.** Smile ID's signature algorithm page and V3 docs are unread (ADR-0005).
  Only the mock is wired. The contract suite is ready for the real adapter.
- **Phone numbers are collected but not verified.** SMS/OTP arrives with the OTP work in Phase 5a (ADR-0006
  moved there).
- No admin "invite by email" flow: staff join via request + approval. Platform onboarding needs the new
  admin's user ID, pasted from their onboarding page.
- Territory boundaries can be created but not edited. There are no rename/delete commands for structure yet.
- CBN tier limits remain unverified (conflicting vendor figures). Nothing hard-codes them.
- UI is functional and unstyled beyond basics. No automated browser E2E (API path covered by integration tests).
- `service_role` has **no** table privileges (only granted functions), stricter than Supabase's default.
  Future adapters must be given explicit function grants.

## Phase 2: what exists
Run everything with `npm run test:all` (clean DB → 269 pgTAP assertions → typecheck → 5 Node tests).

| Area | Files | Proven by |
|---|---|---|
| Schemas, default privileges | `supabase/migrations/…0100_extensions_schemas.sql` | 001 (no client write grants, anon nothing) |
| Enums, auth seam `app.current_user_id()`, `app.round_div`, shared guards | `…0200_types_and_core_helpers.sql` | 001 (auth.uid only in the seam), 002 (34 rounding cases) |
| Tenancy: orgs, branches, territories, warehouses, profiles, memberships, customer/supply relationships | `…0300_tenancy.sql` | composite FKs make cross-tenant references impossible; 005 |
| Catalogue, immutable `sku_uom`, effective-dated price lists | `…0400_catalogue.sql` | 003 (factor immutability) |
| Inventory ledger + `stock_balances` projection (CHECKs, trigger-only, group balance for handover/return) | `…0500_inventory_ledger.sql` | 003, Node commit-time test |
| Orders + DB-side carton→piece conversion, immutable lines | `…0600_orders.sql` | 003 |
| Money ledger: accounts per book, journals, entries, zero-sum per book (deferred), sign-rule CHECKs | `…0700_money_ledger.sql` | 004, Node commit-time test |
| `app.ensure_account`, `app.post_journal` (idempotent), `app.post_stock_movement`, `app.reserve_order` (atomic, row-locked), rebuild checks | `…0800_ledger_functions.sql` | 003, 004, Node 50-vs-10 + duplicate-posting tests |
| RLS helpers + SELECT-only policies on every table | `…0900_rls_helpers.sql`, `…1000_rls_policies.sql` | 005 (163 assertions) |
| Append-only audit log on every business table | `…1100_audit.sql` | 006 |
| Explicit grants | `…1200_grants.sql` | 001 |
| Seed: 1 manufacturer, 2 distributors, 3 branches, 5 territories, 3 warehouses, 5 agents, 2 drivers, 20 retailers, 15 SKUs, opening stock + wallet top-ups through the ledgers | `supabase/seed.sql` | 003/004 assume it; rebuild checks pass after seeding |
| Node harness | `package.json`, `tsconfig.json`, `tests/support/db.ts`, `tests/concurrency/`, `tests/invariants/`, `scripts/test-all.sh` | |

**Mutation check (done once by hand, not automated):** with `FOR UPDATE` removed from `app.reserve_order`,
the 50-vs-10 test **failed**. Oversell still didn't happen, because the `reserved <= on_hand` CHECK held,
but the failures surfaced as raw `23514` instead of a clean `SOL01`. That shows both layers work and the
test is not vacuous.

**Bug found by the tests and fixed:** projection triggers originally used `INSERT … ON CONFLICT DO UPDATE`.
Postgres evaluates CHECKs on the proposed insert row first, so every decrement of an existing balance was
rejected. They now update first and insert only if the row is missing (see CLAUDE.md "SQL conventions").

## Phase 2: known gaps
- **No client-callable commands yet.** `reserve_order` and the ledger primitives are internal. So the
  concurrency test calls `reserve_order` as the owner role. Phase 4 adds `app.place_order` (routing +
  reservation) with an `EXECUTE` grant, and the concurrency test then also runs as authenticated retailers.
- Tables that arrive with their flows: `shipments`, `transfers`, `variance_cases` (4/5a), `otp_challenges`
  (5a), `sync_events`/`review_items`/`provider_events` (5b), `domain_events` (4). Each lands with RLS,
  audit trigger and isolation-test coverage. The isolation test fails if any public table is missing from it.
- RLS simplifications listed in [roles-permissions.md](architecture/roles-permissions.md#phase-2-simplifications-tightened-in-the-phase-noted).
- RLS performance (initPlan behaviour, index usage) not measured yet (Phase 6 hardening).
- Duplicate *webhook* test proper (signature + HTTP 200 on replay) is Phase 5b. Phase 2 proves the DB half:
  20 concurrent duplicate postings → exactly one journal.
- CBN circular primary text still unread (see Phase 1 gaps).

## Phase 1: what exists
- [CLAUDE.md](../CLAUDE.md): hard rules with reasons, numeric/portability/testing rules, commands, layout.
- [architecture/README.md](architecture/README.md): system context, layering, write-path rule, monorepo layout.
- [architecture/roles-permissions.md](architecture/roles-permissions.md): tenancy model and role × action matrix.
- [architecture/domain-model.md](architecture/domain-model.md): entities, stock movement semantics, chart of
  accounts, state machines, UoM, rounding.
- [architecture/flows.md](architecture/flows.md): sequence diagrams for pull, push, credit purchase,
  return + reconciliation, offline sync + accept-into-variance, and payment webhooks.
- [architecture/events.md](architecture/events.md): domain events and the agent sync envelope.
- [architecture/risk-register.md](architecture/risk-register.md)
- ADRs: [0001 hosting](adr/0001-hosting-and-data-residency.md), [0002 regulatory findings](adr/0002-regulatory-findings-2026-10.md),
  [0003 ledger design](adr/0003-ledger-design.md), [0004 auth abstraction](adr/0004-auth-abstraction-and-portability.md).

## Phase 1: known gaps
- **CBN circular PSS/DIR/PUB/CIR/001/004 primary text not read.** The cbn.gov.ng PDF sits behind a bot
  challenge. Its findings rest on several consistent secondary sources ([ADR-0002](adr/0002-regulatory-findings-2026-10.md)).
  Action: a human downloads the PDF into `docs/regulatory/` and we re-check scope (KYC data? backups abroad?).
- CBN three-tier KYC limits not re-verified for 2026. That happens in Phase 3 with KYC provider research.
- GAID retention specifics not confirmed. The retention schedule is still TBD (ADR-0002).
- Provider choices (payments/virtual accounts, KYC, SMS) not made yet. Each is researched in the phase that
  writes its interface.
- No runnable test suite in Phase 1 (docs only). Validation was Mermaid rendering + link checks.

## Environment prerequisites
- Docker Desktop running.
- Supabase CLI installed (`brew install supabase/tap/supabase`). Both confirmed working on 2026-10-21.

## Scope map (every SPEC.md bullet appears exactly once)
**B** = build in MVP · **S** = stub behind an interface · **D** = deferred (extension point kept)

| SPEC § | Bullet | Scope | Phase | Notes / extension point |
|---|---|---|---|---|
| 1 | Separate logins for manufacturers, distributors, agents and retailers | B | 3 | Supabase Auth via `app.current_user_id()` |
| 1 | Role based access and permissions | B | 2–3 | memberships + RLS |
| 1 | Customer and agent registration | B | 3 | distributor approval step |
| 1 | Customer KYC verification using BVN, NIN and geolocation | B (mock provider) | 3 | `KycProvider` interface; store status + ref + hash only |
| 1 | Multiple branch management | B | 3 | |
| 1 | Territory and warehouse mapping | B | 3 | PostGIS polygons/points |
| 2 | Product catalogue with brands, SKUs, prices and quantities | B | 4 | manufacturer master catalogue, distributor price lists |
| 2 | Carton to piece conversion | B | 2/4 | `sku_uom`, edges only |
| 2 | Real time stock tracking | B | 4 | Realtime notifies; ledger is the truth |
| 2 | Separate warehouse and agent inventory | B | 2 | polymorphic locations |
| 2 | Low stock alerts | D | – | `reorder_point` column on `sku_location_settings`; alert job later |
| 2 | Automatic restock suggestions | D | – | derived from ledger sales velocity; read-only view later |
| 2 | Stock transfers between warehouses and agents | B | 4 | transfer_out/transfer_in movement groups |
| 3 | Primary orders from distributors to manufacturers | D | – | `orders.order_kind` enum includes `primary`; receipts link `source_order_id` |
| 3 | Pull orders placed by customers or agents | B | 4 | |
| 3 | Push orders using agent carried stock | B | 5a | |
| 3 | Shopping cart and checkout | B | 4 | cart is client state until `app.place_order` |
| 3 | Order tracking and status updates | B | 4 | order state machine + events |
| 3 | Automatic order routing to the nearest available warehouse | B | 4 | routing decision + reason stored on order |
| 3 | Order batching, packing and delivery assignment | B | 4 | |
| 3 | Partial and missing delivery reporting | B | 4 | |
| 4 | Agent stock pickup requests | B | 5a | |
| 4 | Distributor approval of stock requests | B | 5a | |
| 4 | OTP verification during stock handover | B | 5a | two-party, bound OTP |
| 4 | Geofenced customer visits | B | 3/5b | server-side check; client check is advisory |
| 4 | Agent sales recording | B | 5b | offline events |
| 4 | Automatic inventory updates after sales | B | 5b | sale movements from accepted events |
| 4 | Agent performance tracking and leaderboards | B | 6 | read models over ledgers |
| 5 | Digital wallet and virtual accounts | B (mock provider) | 5b | wallet = mirror of partner VA; `VirtualAccountProvider` |
| 5 | Online and in app payments | B (transfers only) | 5b | inbound bank transfer to VA; no card acquiring (assumption) |
| 5 | Split payments using wallet balance and credit | B | 5b | single journal, multiple legs |
| 5 | Buy Now Pay Later (BNPL) | S | 5b | `CreditScoringProvider` mock; distributor trade credit is built |
| 5 | OTP verification for credit transactions | B | 5b | |
| 5 | Payment history and transaction ledger | B | 5b | |
| 5 | Automatic payment reconciliation with ERP | S | 5b | `ErpConnector` mock; provider reconciliation is built |
| 6 | Shipment tracking | B | 4 | status-based; GPS breadcrumbs deferred |
| 6 | Delivery assignment to agents | B | 4 | assignee may be a driver or an agent (assumption) |
| 6 | Vehicle tracking | S | 4 | `VehicleTrackingProvider` mock |
| 6 | Electronic proof of delivery | B | 4 | |
| 6 | Geotagged delivery photos | B | 4 | Storage object + lat/lng; minimise faces (NDPA) |
| 6 | Delivery confirmation | B | 4 | |
| 6 | Missing or damaged goods reporting | B | 4 | damage movements + disputes |
| 6 | Returnable packaging and empties tracking | D | – | `skus.item_class` (`sellable` \| `returnable_container`) reserved; same ledger |
| 7 | Stock return requests | B | 5a | |
| 7 | OTP verification during reconciliation | B | 5a | |
| 7 | Tracking of stock picked up, sold and returned | B | 5a | shipment view derived from movements |
| 7 | Open and closed shipment records | B | 5a | close blocked by open variance |
| 7 | Automatic stock reconciliation | B | 5a | |
| 7 | Financial reconciliation and audit trails | B | 5b | |
| 8 | Sales and revenue dashboards | B | 6 | |
| 8 | Inventory and order reports | B | 6 | |
| 8 | Distributor performance tracking | D | – | manufacturer-scope read model later; data already in ledgers |
| 8 | Agent visit and sales productivity tracking | B | 6 | |
| 8 | SKU performance analysis | B | 6 | |
| 8 | Financial reports | B | 6 | |
| 8 | Real time operational visibility | B | 6 | ops dashboard |
| 9 | Distributor loyalty and rebate programs | S | 6 | `LoyaltyEngine` mock |
| 9 | Retailer cashback and reward programs | D | – | would post via `ledger_entries` with a `rewards` account |
| 9 | Coupons and promotional offers | D | – | `order_lines.discount_kobo` + `app.round_div` already in place |
| 9 | In app advertisements and banners | S | 6 | `ContentProvider` mock |
| 9 | QR code based product enquiries and ordering | S | 6 | `QrResolver` mock; deep link → `app.place_order` |
| 9 | Customer surveys and feedback | S | 6 | `SurveyProvider` mock |
| 9 | Shelf photography and merchandising verification | S | 6 | `ShelfVerificationProvider` mock |
| 10 | Order status notifications | B | 6 | from domain events |
| 10 | Payment confirmations and reminders | B (confirmations) / D (reminders) | 6 | reminders are a scheduled job later |
| 10 | Stock and replenishment alerts | D | – | depends on low-stock alerts |
| 10 | Promotional notifications | S | 6 | `BulkNotifier` mock |
| 10 | Customer support tickets | B | 6 | |
| 10 | In app issue and dispute reporting | B | 4/6 | delivery disputes in Phase 4 |
| 11 | Centralized database connecting all users | B | 2 | |
| 11 | Real time synchronization of inventory, orders and payments | B | 4–6 | Realtime notifications + agent event sync |
| 11 | ERP and accounting system integration | S | 5b | `ErpConnector` mock |
| 11 | Automated ledger updates | B | 2 | triggers + command functions |
| 11 | Complete transaction history and audit logs | B | 2 | audit triggers |
| 11 | Secure authentication and access controls | B | 3 | |
