# Architecture Decision Records

| ADR | Title | Status | Date |
|---|---|---|---|
| [0001](0001-hosting-and-data-residency.md) | Hosting and data residency | Accepted | 2026-10-21 |
| [0002](0002-regulatory-findings-2026-10.md) | Regulatory findings (verification status, Oct 2026) | Accepted (living) | 2026-10-21 |
| [0003](0003-ledger-design.md) | Inventory and money ledger design | Accepted | 2026-10-21 |
| [0004](0004-auth-abstraction-and-portability.md) | Auth abstraction and portability seams | Accepted | 2026-10-21 |
| [0005](0005-kyc-provider.md) | KYC provider and the KycProvider interface | Accepted (mock built, real adapter unverified) | 2026-10-21 |

## Planned (written in the phase that builds each interface, after reading current provider docs)
| ADR | Topic | Phase |
|---|---|---|
| 0006 | SMS / OTP delivery provider (also phone verification) | 5a |
| 0007 | Maps / geocoding provider (only if routing UI needs it; distances are PostGIS) | 4 |
| 0008 | Payments / virtual accounts provider (Paystack DVA / Monnify reserved accounts / Flutterwave VA) | 5b |
| 0009 | Expo offline storage + outbox pattern | 5b |

Provider ADRs must cite current docs by URL, compare the options, and mark anything unreachable as
**unverified**. API shapes are never written from memory.

## Template
```markdown
# ADR-NNNN: Title
- Status: Proposed | Accepted | Superseded by ADR-XXXX
- Date: YYYY-MM-DD
## Context
## Options considered
## Decision
## Consequences
## Sources (URL, date read, read in full or summary only)
```
