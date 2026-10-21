# ADR-0006: OTP design and SMS delivery provider
- Status: Accepted (interface + mock built in Phase 5a; real adapter not built)
- Date: 2026-10-22

## Decision
1. **We generate and verify OTPs ourselves, in Postgres.** Provider-managed OTP products are not used:
   hard rule 5 needs the code hashed at rest, bound to one handover/return/credit record and both
   parties, expiring, and attempt-limited. Only our own table can prove that.
   - `private.otp_challenges`: bcrypt hash via `extensions.crypt`, 5-minute expiry, 5 attempts, at most
     3 issues per challenge, statuses `pending → verified | expired | locked | superseded`.
   - The plaintext code exists only in the return value of `app.issue_otp_code`, which is **service_role
     only**. The server adapter receives it, hands it to `SmsProvider.send`, and never returns or logs it.
   - Verification (`app.verify_otp`) is called by the **initiator** (warehouse staff) with the code the
     **recipient** (agent) reads out from their phone. A wrong code increments attempts and *returns*
     failure, because Postgres has no autonomous transactions. On success the bound action runs in the
     same transaction.
2. **SMS goes through the `SmsProvider` interface**: `send({ to, body, purpose, reference })` returns
   `{ provider, providerMessageId }`. There's a deterministic mock and a contract suite.
3. **Preferred provider: Termii.** Its docs were read: `POST {BASE_URL}/api/sms/send` with `api_key`,
   `to`, `from`, `sms`, `type`, `channel`. The **`dnd` channel is required for OTPs**: the generic route
   isn't delivered to DND numbers, nor to MTN numbers between 8PM and 8AM WAT, and the `dnd` route must
   be activated by Termii support. Unverified: the concrete `BASE_URL` (the page shows a placeholder) and
   the error-response shape.
   - Africa's Talking: docs page returned HTTP 403, so it is **unverified** and wasn't compared.

## Sources (read 2026-10-22)
- https://developers.termii.com/messaging-api (read)
- https://developers.africastalking.com/docs/sms/sending/bulk (HTTP 403, not read)
