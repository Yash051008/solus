# ADR-0001: Hosting and data residency
- Status: Accepted
- Date: 2026-10-21
- Related: [ADR-0002](0002-regulatory-findings-2026-10.md), [ADR-0004](0004-auth-abstraction-and-portability.md)

## Context
- The stack is Supabase (Postgres + PostGIS, Auth, RLS, Realtime, Storage, Edge Functions).
- **Supabase Cloud has no African region.** The official list has 17 regions across the Americas, Europe and
  Asia-Pacific ([regions](https://supabase.com/docs/guides/platform/regions), read 2026-10-21).
- A CBN circular (PSS/DIR/PUB/CIR/001/004, 15 June 2026) requires payment transaction data generated in
  Nigeria to be stored and managed in Nigeria from **1 January 2027**. It is addressed to licensed payment
  operators, and its definition of "payment transaction data" and its KYC coverage are unclear. Verification
  status is in ADR-0002. **The primary text has not been read.**
- We are not a licensed operator, and the platform never custodies funds. But our money ledger mirrors
  partner virtual-account transactions (payer, amount, reference, time), which plausibly *is* payment
  transaction data. Our licensed partners may also require residency from us contractually.
- NDPA 2023 s.41 allows cross-border transfer of personal data only with adequate protection or another
  lawful basis.

## Options considered
| | A. Supabase Cloud (EU region) | B. Self-hosted Supabase in a Nigerian DC | C. Plain Postgres + PostGIS in Nigeria, own auth |
|---|---|---|---|
| Residency | ❌ offshore | ✅ | ✅ |
| Effort now | lowest | medium | highest |
| Ops burden | managed backups/PITR, upgrades | **we own** backups, PITR, HA, upgrades, hardening. Docker Compose is the official method and it's "community-supported". No branching, Management API or managed PITR ([self-hosting](https://supabase.com/docs/guides/self-hosting), read 2026-10-21) | we own everything, plus auth, REST and realtime replacements |
| Keeps Auth/RLS/Realtime/Storage APIs | ✅ | ✅ | ❌ (swap via the seams in ADR-0004) |
| NG infra availability | n/a | AWS Local Zone Lagos exists since Jan 2023, managed-Postgres availability there **unconfirmed**. Local DC/cloud providers claim readiness. NITDA's National Sovereign Cloud Initiative certification register is pending (see ADR-0002) | same |

## Decision
1. **Development and CI:** local Supabase stack (CLI + Docker). Synthetic data only.
2. **Staging / demos:** Supabase Cloud (EU region chosen by measured latency from Lagos at Phase 2) is
   allowed **with synthetic data only**. No real payment transaction data and no real KYC references.
3. **Production with real money:** must run on Postgres hosted **in Nigeria** before go-live. This is a
   hard gate, independent of how the circular's scope is finally read. The default target is **B
   (self-hosted Supabase in a Nigerian DC)**. **C** is the fallback if B's ops burden or component maturity
   proves unacceptable. The specific provider is chosen before go-live, preferring one on NITDA's certified
   register once it's published.
4. The portability rules (business logic in SQL, repository layer, single auth seam, thin Edge adapters,
   Realtime as hint only) are **mandatory from Phase 2**, so B or C is a deployment change, not a rewrite.
5. Object storage for e-POD photos follows the same residency rule (photos are personal data and evidence).

## Consequences
- We carry the production ops burden: backups, PITR, HA failover, OS/Postgres upgrades, monitoring.
  This is budgeted before go-live.
- No Supabase-Cloud-only features may become load-bearing (branching, Management API, managed PITR,
  ETL/analytics buckets).
- Edge Functions must be portable to any Deno/Node runtime (they're thin adapters, so this is cheap).
- Realtime may be replaced by Postgres `LISTEN/NOTIFY` + SSE in C. Clients already treat it as a hint.

## Go-live exit checklist (owned by Phase 6 hardening)
- [ ] Primary text of the CBN circular obtained and reviewed by counsel. ADR-0002 updated.
- [ ] Nigerian hosting provider chosen (certified-register status recorded), contract covers backups in Nigeria.
- [ ] Full migration rehearsal: `supabase/migrations` applied to the target. pgTAP + concurrency suites pass there.
- [ ] `app.current_user_id()` points at the production auth source. RLS suite re-run.
- [ ] Backups + PITR restore drill done, RPO/RTO recorded.
- [ ] Storage (e-POD photos) in-country, retention policy applied.
- [ ] Partner contracts confirm their residency obligations and ours.

## Sources
- https://supabase.com/docs/guides/platform/regions (read in full, 2026-10-21)
- https://supabase.com/docs/guides/self-hosting (read in full, 2026-10-21)
- https://nairametrics.com/2023/01/26/aws-launches-new-aws-local-zones-location-in-lagos-nigeria/ (search summary only)
- https://technext.ng/2023/01/27/aws-launch-local-zones-location-lagos/ (search summary only)
- https://techeconomy.ng/nigeria-data-localisation-cloud-economy (search summary only)
- https://techeconomy.ng/clouds2africa-positions-for-cbn-data-localisation-deadline (search summary only)
- CBN circular sources: see ADR-0002.
