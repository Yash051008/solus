# ADR-0008: Payments, virtual accounts and webhooks
- Status: Accepted (interface + mock built in Phase 5b-1; no real adapter)
- Date: 2026-10-22
- Related: [ADR-0002](0002-regulatory-findings-2026-10.md) (no fund custody), [ADR-0003](0003-ledger-design.md)

## Decision
1. **The platform never holds money.** Every shop and distributor gets a virtual account (VA) at a licensed
   partner. Inbound transfers arrive as signed webhooks. Our ledger only *mirrors* partner-held funds
   (`provider_clearing` = Σ wallets) and is reconciled against the partner's statement.
2. **`VirtualAccountProvider` interface:** `createAccount`, `verifyWebhook(rawBody, headers)`,
   `parseWebhook(rawBody) → { eventId, reference, accountNumber, amountKobo (integer string), paidAt }`,
   `statement(from, to)`. Amounts are normalised to integer kobo inside the adapter. A provider sending
   naira decimals is converted with exact parsing, never floats.
3. **Webhook handling** (`handlePaymentWebhook`, server-side): verify the signature on the **raw** body,
   then normalise, then call `app.record_provider_event` (service_role only). Idempotent on
   `(provider, provider_event_id)`: a duplicate returns HTTP 200 and is logged with a payload-hash
   comparison. A DB failure returns 5xx so the provider retries. Unmatched account numbers are stored as
   `unmatched` for ops, and no money is posted.
4. **Preferred provider: Paystack Dedicated Virtual Accounts.** Official docs (via search; the page
   returned 403 to direct fetch): `POST https://api.paystack.co/dedicated_account` with customer code and
   preferred bank. Events include `charge.success`, `dedicatedaccount.assign.success/failed`. A DVA needs
   the customer's express consent and is limited to registered, live businesses in Nigeria and Ghana.
   - **Unverified:** the webhook signature header name (community SDKs say HMAC-SHA512 of the raw body with
     the secret key), and whether DVA transfers always arrive as `charge.success`.
   - **Monnify reserved accounts** (alternative): `monnify-signature` header. Its docs disagree on
     SHA-512(secret + body) versus HMAC, so it's unverified, and only a v1 sandbox path was seen.
   - **Flutterwave:** `POST /v3/virtual-account-numbers`, event `charge.completed` /
     `BANK_TRANSFER_TRANSACTION`. Verification method and amount units aren't on the page, so it's unverified.
5. **The mock** signs with HMAC-SHA512 of the raw body, hex, header `x-mock-signature`, secret
   `PAYMENTS_WEBHOOK_SECRET`. Same shape as Paystack's reported scheme, so the real adapter is a drop-in.

## Ledger postings (per-book double entry)
| Event | Platform book | Distributor book |
|---|---|---|
| Transfer into a **shop** VA | Dr provider_clearing / Cr wallet[shop] | – |
| Transfer into a **distributor** VA | Dr provider_clearing / Cr wallet[D] | Dr partner_funds / Cr **unallocated_receipts** |
| Allocate receipt to agent cash / shop debt | – | Dr unallocated_receipts / Cr cash_in_transit[A] or receivables[shop] |
| Pay order from wallet | Dr wallet[shop] / Cr wallet[D] | Dr partner_funds / Cr receivables[shop] |
| Pay order on trade credit (after credit OTP) | – | Dr trade_credit[shop] / Cr receivables[shop] |
| Cash to driver at delivery | – | Dr cash_in_transit[driver] / Cr receivables[shop] |
| Repay credit from wallet | Dr wallet[shop] / Cr wallet[D] | Dr partner_funds / Cr trade_credit[shop] |

## Sources (2026-10-22)
- https://paystack.com/docs/payments/dedicated-virtual-accounts/ (HTTP 403; content via search results)
- https://docs-v2.paystack.com/docs/payments/dedicated-virtual-accounts/ (search result)
- https://developers.monnify.com/docs/collections/reserved-accounts (HTTP 403)
- https://developers.monnify.com/docs/integration-tools/webhooks (search result)
- https://developer.flutterwave.com/docs/virtual-account (read)
