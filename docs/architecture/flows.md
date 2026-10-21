# Flows

Every box labelled `app.*` is one Postgres function call = one transaction. Ledger effects use the names in
[domain-model.md](domain-model.md). Realtime arrows are notifications only, and clients refetch on them.

## (a) Pull order: order → route → reserve → fulfil → deliver → pay

```mermaid
sequenceDiagram
  autonumber
  actor R as Retailer (web/app)
  participant DB as Postgres (app.*)
  actor WS as Warehouse staff
  actor BM as Branch manager
  actor DR as Driver (app)
  participant SMS as SmsProvider

  R->>DB: app.place_order(lines in ctn/pcs, idempotency_key)
  Note over DB: UoM to pieces at input<br/>route_order picks nearest warehouse able to cover all lines
  alt nearest full-cover within split threshold
    DB->>DB: lock stock_balances FOR UPDATE (fixed order)<br/>insert reserve movements
    DB-->>R: order reserved + routing_decision, routing_reason
  else split beats threshold
    DB-->>BM: order awaiting_split_decision (Realtime)
    BM->>DB: app.decide_split(order, accept or single)
    DB->>DB: reserve per chosen warehouse(s)
  else no warehouse can cover
    DB-->>R: rejected (nothing reserved)
  end
  WS->>DB: app.create_batch(orders) then app.mark_packed(batch)
  BM->>DB: app.assign_delivery(batch, driver or agent)
  Note over DB: creates delivery shipment (one open per carrier)
  WS->>DB: app.start_handover(shipment)
  DB->>SMS: send OTP to driver phone (hash stored, 5 min, 5 attempts)
  DR-->>WS: reads OTP aloud
  WS->>DB: app.verify_otp(challenge, code)
  Note over DB: one movement group per order line<br/>release q + handover -q warehouse + handover +q driver
  loop each stop
    DR->>DB: app.record_delivery(order, delivered, refused, missing, damaged, photo_ref, lat, lng)
    Note over DB: sale -delivered at driver<br/>damage -damaged at driver<br/>refused stays on driver and returns later<br/>missing recorded as a claim on the shipment
    DB->>DB: journal delivery_invoiced (delivered qty x price)
    R->>DB: app.confirm_delivery(order) or app.open_dispute(order, reason)
  end
  alt pay from wallet and/or credit
    R->>DB: app.settle_order(order, wallet_kobo, credit_kobo, otp if credit)
    Note over DB: see flow (c)
  else cash to driver
    DR->>DB: app.record_cash(order, amount_kobo)
    Note over DB: journal cash_collected
  end
  DR->>DB: return refused/undelivered stock (flow (d)), then the shipment closes
```

## (b) Push: request → approve → OTP handover → geofenced sales

```mermaid
sequenceDiagram
  autonumber
  actor A as Agent (app)
  participant DB as Postgres (app.*)
  actor BM as Branch manager
  actor WS as Warehouse staff
  participant SMS as SmsProvider
  actor R as Retailer

  A->>DB: app.request_stock(lines, warehouse)
  DB-->>BM: stock request pending (Realtime)
  BM->>DB: app.approve_stock_request(request, approved qty per line)
  Note over DB: guard: no other open shipment for this agent<br/>creates push shipment (approved)
  A->>WS: arrives at warehouse
  WS->>DB: app.start_handover(shipment, counted lines)
  Note over DB: OTP challenge bound to shipment,<br/>initiator = WS, recipient = A
  DB->>SMS: OTP to agent verified phone
  A-->>WS: reads OTP aloud
  WS->>DB: app.verify_otp(challenge, code)
  Note over DB: movement group: handover -q warehouse, +q agent<br/>shipment open, picked_up fixed
  loop each visit (may be offline)
    A->>A: geofence check on device (advisory)
    A->>A: append sale event to outbox (client UUID)
    A->>DB: sync when online (flow (e))
    Note over DB: server re-checks geofence: distance(event lat/lng, retailer geog) <= radius<br/>then validates carried stock and inserts sale movements
  end
  R-->>A: pays cash or transfer
  Note over DB: cash: journal cash_collected (push)<br/>credit sale: online only, flow (c)
```

## (c) Credit purchase: split wallet + trade credit, credit OTP

```mermaid
sequenceDiagram
  autonumber
  actor R as Retailer
  actor A as Agent (optional initiator)
  participant DB as Postgres (app.*)
  participant SMS as SmsProvider

  alt retailer self-checkout
    R->>DB: app.start_credit_payment(order, wallet_kobo, credit_kobo, idempotency_key)
  else agent initiates for retailer
    A->>DB: app.start_credit_payment(order, wallet_kobo, credit_kobo, idempotency_key)
  end
  Note over DB: validate wallet_kobo + credit_kobo = amount due<br/>KYC status allows credit<br/>pre-check limit (advisory)
  DB->>SMS: credit OTP to retailer phone (bound to order, amount, both parties)
  R->>DB: app.verify_otp(challenge, code)
  Note over DB: inside one transaction:<br/>1. lock customer_relationships row FOR UPDATE<br/>2. re-check trade_credit balance + credit_kobo <= limit<br/>3. re-check wallet[R] balance >= wallet_kobo<br/>4. post ONE split_payment journal
  alt checks pass
    DB->>DB: P: Dr wallet[R] / Cr wallet[D]<br/>D: Dr partner_funds / Cr receivables[R] (wallet part)<br/>D: Dr trade_credit[R] / Cr receivables[R] (credit part)
    DB-->>R: settled, statement updated (Realtime)
  else limit or balance exceeded
    DB-->>R: rejected, nothing posted, OTP consumed
  end
  Note over DB: BNPL scoring (third-party) is stubbed behind CreditScoringProvider<br/>only distributor trade credit is live in MVP
```

## (d) Return + reconciliation (push shipments and delivery runs)

```mermaid
sequenceDiagram
  autonumber
  actor A as Agent or driver
  participant DB as Postgres (app.*)
  actor WS as Warehouse staff
  actor BM as Branch manager
  participant SMS as SmsProvider

  A->>DB: app.submit_return(shipment, declared lines, damaged lines)
  Note over DB: requires all outbox events synced<br/>(server compares device seq high-water mark)
  WS->>DB: app.count_return(shipment, counted lines)
  DB->>SMS: reconciliation OTP to carrier (bound to shipment + counted lines hash)
  A-->>WS: reads OTP aloud (agrees with count)
  WS->>DB: app.verify_otp(challenge, code)
  Note over DB: return -q carrier, +q warehouse<br/>damage -q carrier (damaged lines)<br/>remaining = carrier on_hand per SKU
  alt remaining = 0 for all SKUs and no pending cases
    DB->>DB: shipment reconciling then closed
    DB-->>BM: shipment closed
  else remaining > 0 (e.g. 100 - 70 - 25 - 3 = 2)
    DB->>DB: variance_case(2 pcs, pending), journal variance_raised<br/>flag agent + shipment, status blocked
    DB-->>BM: variance pending approval (Realtime)
    alt manager approves write-off (manager != carrier)
      BM->>DB: app.resolve_variance(case, write_off, note)
      Note over DB: adjustment -2 at carrier<br/>journal variance_written_off
    else agent is charged
      BM->>DB: app.resolve_variance(case, charge_agent)
      Note over DB: adjustment -2 at carrier<br/>journal variance_charged (receivables[A])
    end
    BM->>DB: app.close_shipment(shipment)
    Note over DB: succeeds only when on_hand = 0 and no pending cases
  end
```

## (e) Offline sync, rejection → review queue → accept-into-variance

```mermaid
sequenceDiagram
  autonumber
  participant APP as Agent app (SQLite outbox)
  participant DB as Postgres (app.*)
  actor BM as Branch manager

  Note over APP: airplane mode: sales appended as events<br/>event_id = client UUID, seq = device counter
  APP->>DB: app.sync_events(batch of events)
  loop per event, in seq order
    alt event_id already in sync_events
      DB-->>APP: duplicate (original result returned, nothing re-applied)
    else valid: geofence OK, carried stock covers qty, not past shipment close
      DB->>DB: insert sync_events(accepted) + sale movements + journals (one transaction)
      DB-->>APP: accepted
    else invalid, e.g. sale 60 but carried 50
      DB->>DB: insert sync_events(rejected, reason) + review_items(open)
      DB-->>APP: rejected (shown to agent, never dropped)
      DB-->>BM: review item (Realtime)
    end
  end
  alt manager: accept into variance
    BM->>DB: app.review_accept_into_variance(item, note)
    Note over DB: one transaction:<br/>adjustment +10 at agent (reason unrecorded_stock, ref variance_case)<br/>sale -60 at agent + revenue/cash journals<br/>variance_case(10 pcs, pending), shipment blocked
    Note over DB: resolution later: linked_to_handover (post missing warehouse handover,<br/>reverse the +10) or written_off after investigation
  else manager: dismiss (agent error, sale did not happen)
    BM->>DB: app.review_dismiss(item, reason)
  end
  APP->>DB: pull carried stock + results, update local cache
```

## (f) Payment webhook (virtual-account inflow), duplicate-safe

```mermaid
sequenceDiagram
  autonumber
  participant P as Payment partner
  participant EF as Edge Function (adapter)
  participant DB as Postgres (app.*)

  P->>EF: POST transfer.received (signature header)
  EF->>EF: verify signature with partner secret (constant-time compare)
  alt signature invalid
    EF-->>P: 401, logged, nothing written
  else valid
    EF->>DB: app.record_provider_event(provider, provider_ref, raw payload, payload hash)
    alt (provider, provider_ref) unseen
      DB->>DB: insert provider_events + journal va_inflow<br/>(idempotency_key = provider:ref), one transaction
      DB-->>EF: posted
    else already recorded
      DB->>DB: log duplicate (payload hash compared, mismatch raises an alert)
      DB-->>EF: duplicate
    end
    EF-->>P: 200 (both cases, so the partner stops retrying)
  end
  Note over DB: daily: settlement statement import (stub) reconciles<br/>provider_clearing vs partner statement, mismatches become review items
```
