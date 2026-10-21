# Events

Two kinds, never confused:

1. **Domain events** (`public.domain_events`): written by `app.*` functions in the same transaction as the
   state change. They're a transactional outbox that drives notifications and Realtime fan-out. They are
   **facts after the fact**. Nothing derives balances from them.
2. **Agent sync events** (`public.sync_events`): **commands from devices** that may be accepted, rejected
   or duplicate. Accepted ones produce ledger rows plus domain events.

## Domain events

Envelope: `id uuid, type text, org_id uuid, subject_kind, subject_id, payload jsonb, occurred_at, actor_user_id`.
Payloads hold ids and small facts, never PII beyond what the recipient may already read (RLS applies to
`domain_events` too).

| Event | Producer (`app.*`) | Key payload | Ledger effects (same txn) | Notify |
|---|---|---|---|---|
| `org.registered` | `register_org` | org kind | – | platform admin |
| `member.approved` | `approve_registration` | user, role | – | user (SMS) |
| `kyc.status_changed` | `record_kyc_result` | status, provider_ref | – | retailer, distributor admin |
| `stock.received` | `record_receipt` | warehouse, lines | `receipt` | branch manager |
| `stock.adjustment_requested` / `approved` | `request_adjustment` / `approve_adjustment` | lines, reason | `adjustment` (on approve) | approver / requester |
| `transfer.dispatched` / `received` | `dispatch_transfer` / `receive_transfer` | transfer, lines | `transfer_out` / `transfer_in` | dest / source BM |
| `order.placed` | `place_order` | order, total_kobo | – | distributor ops |
| `order.reserved` | `place_order` / `decide_split` | warehouse(s), routing_reason | `reserve` | retailer |
| `order.awaiting_split_decision` | `place_order` | proposal | – | branch manager |
| `order.rejected` | `place_order` | reason | – | retailer |
| `order.cancelled` | `cancel_order` | reason | `release` | retailer, warehouse |
| `batch.created` / `batch.packed` | `create_batch` / `mark_packed` | orders | – | branch manager |
| `delivery.assigned` | `assign_delivery` | shipment, carrier | – | driver/agent |
| `handover.otp_issued` | `start_handover` | challenge id (never the code) | – | recipient (SMS carries the code) |
| `handover.completed` | `verify_otp` (handover) | shipment, lines | `release` + `handover` legs | both parties |
| `delivery.recorded` | `record_delivery` | delivered/refused/missing/damaged, photo_ref | `sale`, `damage`; journal `delivery_invoiced` | retailer |
| `delivery.disputed` | `open_dispute` | reason | – | branch manager |
| `stock_request.created` / `approved` / `rejected` | `request_stock` / `approve_stock_request` | lines | – | BM / agent |
| `sale.recorded` | `sync_events` (accepted) | shipment, retailer, lines | `sale`; journal `cash_collected` | – (dashboards) |
| `sync.event_rejected` | `sync_events` | event_id, reason | – | branch manager, agent |
| `review.resolved` | `review_*` | decision | per decision (see flow (e)) | agent |
| `return.submitted` / `return.counted` | `submit_return` / `verify_otp` (return) | lines | `return` legs, `damage` | BM |
| `variance.raised` | `verify_otp` (return) / `review_accept_into_variance` | case, qty, value_kobo | journal `variance_raised` | BM, distributor admin |
| `variance.resolved` | `resolve_variance` | decision | `adjustment`; journal `variance_written_off` / `variance_charged` | agent |
| `shipment.closed` | `close_shipment` | totals | – | BM |
| `payment.received` | `record_provider_event` | amount_kobo, provider_ref | journal `va_inflow` | retailer / distributor |
| `payment.duplicate_webhook` | `record_provider_event` | provider_ref, hash_match | – | ops (log only, alert if hash mismatch) |
| `payment.settled` | `settle_order` / `verify_otp` (credit) | wallet_kobo, credit_kobo | journal `split_payment` | retailer, distributor |
| `credit.limit_changed` | `set_credit_limit` | old, new | – | retailer |
| `cash.remitted` | `record_provider_event` (agent VA) | agent, amount | journal `cash_remitted` | BM |
| `ticket.opened` / `ticket.updated` | `open_ticket` / `update_ticket` | category | – | assignee / opener |

## Agent sync event envelope

```ts
// packages/core (Phase 5b). Shape is fixed now so the server contract is stable.
type SyncEvent = {
  event_id: string;      // uuid v4, generated on device at the moment of the action
  device_id: string;     // uuid, registered to the agent at login
  agent_id: string;      // must equal the authenticated user's agent identity (re-checked server-side)
  seq: number;           // per-device monotonic counter, gap detection + ordering
  type: SyncEventType;
  client_ts: string;     // ISO-8601 UTC from device clock (informational; server uses recorded_at for ordering)
  lat: number | null;    // WGS84
  lng: number | null;
  accuracy_m: number | null;
  payload: unknown;      // validated per type in SQL
};

type SyncEventType =
  | 'sale.recorded'          // { shipment_id, retailer_id, lines: [{ sku_id, qty_pieces, unit_price_kobo }], payment: 'cash' | 'transfer_later' }
  | 'visit.checked_in'       // { retailer_id }
  | 'visit.checked_out'      // { retailer_id, outcome }
  | 'cash.collected'         // { retailer_id, amount_kobo, order_id? }
  | 'damage.reported';       // { shipment_id, lines, note }
```

Server results: `accepted` (with ledger refs) · `duplicate` (original result echoed) ·
`rejected` (`reason` code: `insufficient_carried_stock`, `outside_geofence`, `shipment_closed`,
`unknown_retailer`, `price_mismatch`, `seq_gap`, `invalid_payload`, `not_owner`).

Rules:
- `event_id` is the primary key, so a re-sent event can never post twice.
- Events apply in `seq` order per device. A gap pauses that device's later events (`seq_gap`) until the
  missing one arrives, so a sale is never validated against stock that an earlier unsent event would have
  changed.
- Money in events is integer kobo serialised as a **string**. JSON numbers lose precision above 2^53.
- Credit sales are **not** a sync event type in the MVP (they need online OTP + limit lock).
- `client_ts` is never used for financial cut-offs. `recorded_at` is.
