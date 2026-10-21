-- Extensions, schemas and default privileges.
-- Clients (anon, authenticated) get nothing by default; every grant is explicit (see *_grants.sql).

create extension if not exists postgis with schema extensions;
create extension if not exists pgcrypto with schema extensions;

create schema if not exists app;      -- command functions, auth seam, helpers
create schema if not exists audit;    -- append-only audit log
create schema if not exists private;  -- secrets/hashes (OTP etc.), never exposed

revoke all on schema app, audit, private from public;
grant usage on schema app to authenticated, service_role;

-- Objects created by this role (postgres, the migration owner) are private unless granted.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
alter default privileges in schema app revoke execute on functions from public, anon, authenticated;
alter default privileges in schema audit revoke execute on functions from public, anon, authenticated;
alter default privileges in schema private revoke execute on functions from public, anon, authenticated;
