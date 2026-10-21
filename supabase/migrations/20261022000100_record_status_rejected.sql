-- 'rejected' for registrations a distributor declines (kept separate from 'suspended', which is used
-- for previously active records). Own migration: a new enum value can't be used in the transaction
-- that adds it.
alter type public.record_status add value if not exists 'rejected';
