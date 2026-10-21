-- Distributor-book suspense for money received into the distributor's virtual account before it is matched
-- to an agent's cash or a shop's debt (ADR-0008). Own migration: new enum values can't be used in the
-- transaction that adds them.
alter type public.account_type add value if not exists 'unallocated_receipts';
