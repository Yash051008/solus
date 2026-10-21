# ADR-0003: Inventory and money ledger design
- Status: Accepted
- Date: 2026-10-21
- Reference: [domain-model.md](../architecture/domain-model.md)

## Context
Push and pull flows share stock and money. Hard rules 1–4 require immutable ledgers, derived balances, DB-level
impossibility of negative stock, atomic reservation, and offline events that can be reconciled with reality.
Several details aren't settled by the rules alone. This ADR records them.

## Decisions

### D1. Location kinds are `warehouse | agent | driver` (extends the rule's `warehouse | agent`)
**Conflict flagged:** hard rule 1 says locations are `warehouse | agent`. Goods on a delivery vehicle are in
the custody of a driver who isn't an agent. Without a `driver` kind they'd have to either stay "reserved" at
the warehouse (custody wrong: the warehouse is blamed for goods it no longer holds) or be assigned to a fake
agent (roles and RLS wrong). Adding a third value to the same polymorphic column keeps one ledger and one
reconciliation identity for push and delivery runs. **Alternative if rejected:** model drivers as agents
with a `field_role` attribute. That's workable but muddier for permissions.

### D2. Two-legged custody changes in one transaction
`handover` and `return` always write a −q leg and a +q leg in one `movement_group_id`, in one transaction,
after OTP verification. `transfer_out`/`transfer_in` between warehouses are separate transactions linked by
`transfer_id`, with in-transit derived and closure blocked until it is zero. *Why:* a custody change between
two present people is atomic. A truck between warehouses is genuinely in transit.

### D3. Pull dispatch consumes the reservation explicitly
Dispatch writes `release q` + `handover` legs together. The reservation is never consumed implicitly, so
`reserved` stays explainable from the ledger alone.

### D4. One open shipment per carrier (MVP)
A partial unique index enforces it. *Why:* the carrier's `stock_balances` row then equals the shipment
balance, making `picked_up = sold + returned + damaged + variance` an exact, cheap check. Lifting this later
means adding `shipment_id` to the balance key. It's an additive change.

### D5. Money ledger = per-book double entry; funds and claims only, no stock valuation
- Books: a platform **mirror** book (partner-held funds) and one book per distributor. Journals sum to zero
  **per book**, which is stronger than a global zero-sum and catches cross-party mistakes.
- *Why per book:* one undifferentiated ledger mixes perspectives (the retailer's wallet is a liability of the
  partner but an asset of the retailer). Paying a distributor from a wallet can't be balanced without
  contradictions. Splitting books makes each journal provably balanced in a consistent perspective.
- No inventory/COGS accounts. Stock value lives in the ERP (stub). Consequence: a variance write-off has no
  P&L line in our ledger. Its value is reported from `variance_cases` × price.

### D6. "Pending variance" without mutable ledger rows
The example requires "a variance ledger entry in pending state", while hard rule 2 requires immutability.
- On detection: insert `variance_cases(status='pending')` **and** post an immutable journal
  `variance_raised` (Dr `variance[A]` / Cr `variance_offset`). The non-zero `variance[A]` balance *is* the
  pending state, visible in every statement.
- On resolution: post `variance_charged` or `variance_written_off`, which clears `variance[A]`, and update
  the case status (case rows are workflow state, not ledger).
- Stock side: un-reconciled units stay on the carrier until resolution posts an `adjustment`. That's why
  close is blocked naturally (carrier on_hand ≠ 0) and explicitly (pending case).

### D7. Accept-into-variance never breaks the stock CHECKs
Example: carried 50, sold 60 offline. The manager's decision runs in one transaction:
`adjustment +10` at the agent (`reason='unrecorded_stock'`, ref the new variance case) → `sale −60` →
case `pending`. Resolution options:
- `linked_to_handover`: the missing warehouse handover is found. Post it (warehouse −10, agent +10), then
  `adjustment −10` at the agent to reverse the placeholder. The warehouse balance now tells the truth.
- `written_off`: after investigation, approve. The +10 stays as an explained adjustment with an audit trail.
- `charged_to_agent`: only if the sale itself was improper.
*Why:* the sale really happened. Rejecting it leaves the ledger wrong, and inserting it without the
adjustment would make on_hand negative, which the CHECK forbids by design.

### D8. Offline credit sales are disallowed in the MVP
Credit draws need the limit row lock and a retailer OTP, both server-side. Offline sales are cash or
"transfer later" (a receivable). *Alternative for later:* a pre-authorised per-agent credit float with its
own ledger account, drawn down offline and reconciled on sync.

### D9. Idempotency everywhere money or stock moves
`journals.idempotency_key UNIQUE NOT NULL`. `stock_movements.idempotency_key UNIQUE` for client-originated
commands. `sync_events.event_id` PK. `provider_events (provider, provider_ref)` UNIQUE. A replay returns the
original outcome.

### D10. Prices per UoM, quantities per piece
Carton prices are stored exactly as carton prices. Partial-carton credits use `app.round_div(..., 'half_even')`.
This keeps the "no fractional kobo" rule without forcing awkward per-piece prices.

## Consequences
- Every flow is explainable from two ledgers plus workflow tables. Rebuild tests can prove the projections.
- A `driver` location kind needs RLS policies like the agent kind (Phase 2).
- Reporting on stock value needs prices joined at report time (no valuation in the ledger).

## Alternatives rejected
- **Mutable `quantity` columns with optimistic locking:** not auditable, and violates rule 1.
- **Pending journal status column:** mutates ledger rows, violates rule 2.
- **Event-sourcing balances in the app tier:** violates portability (logic outside Postgres) and makes the
  oversell guarantee depend on app code.
