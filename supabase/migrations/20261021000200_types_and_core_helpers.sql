-- Enumerated types, the single auth seam, error codes and the one rounding function.

create type public.org_kind as enum ('platform', 'manufacturer', 'distributor', 'retailer');

create type public.member_role as enum (
  'platform_admin', 'manufacturer_admin', 'distributor_admin', 'branch_manager',
  'warehouse_staff', 'driver', 'agent', 'retailer'
);

create type public.record_status as enum ('pending', 'active', 'suspended');

-- ADR-0003 D1: 'driver' extends the rule's warehouse|agent so in-vehicle stock has explicit custody.
create type public.location_kind as enum ('warehouse', 'agent', 'driver');

create type public.movement_type as enum (
  'receipt', 'reserve', 'release', 'transfer_out', 'transfer_in',
  'handover', 'sale', 'return', 'damage', 'adjustment'
);

create type public.account_type as enum (
  'provider_clearing', 'wallet', 'partner_funds', 'receivables', 'trade_credit',
  'cash_in_transit', 'variance', 'variance_offset', 'sales_revenue'
);

create type public.order_kind as enum ('pull', 'primary');

create type public.order_status as enum (
  'placed', 'awaiting_split_decision', 'reserved', 'rejected', 'batched', 'packed',
  'dispatched', 'delivered', 'partially_delivered', 'failed_delivery', 'settled', 'cancelled'
);

-- Application error codes (SQLSTATE class 'SO'):
--   SOL01 insufficient_stock     SOL02 idempotency_conflict   SOL03 forbidden
--   SOL04 invalid_state          SOL05 validation_failed      SOL06 ledger_invariant_violated

-- THE auth seam (ADR-0004). The only object in the database allowed to reference auth.uid().
-- Policies must call it as (select app.current_user_id()).
create function app.current_user_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid()
$$;

-- The one rounding function (CLAUDE.md numeric rules). Integer in, integer out, explicit mode.
--   half_even: ties to even (default)   half_up: ties away from zero
--   floor: toward -infinity             ceil: toward +infinity
-- Errors (never silent): null argument, denominator <= 0, unknown mode, bigint overflow.
create function app.round_div(p_num bigint, p_den bigint, p_mode text default 'half_even')
returns bigint
language plpgsql
immutable
set search_path = ''
as $$
declare
  q bigint;
  r bigint;
  away bigint;
  twice_r numeric;
begin
  if p_num is null or p_den is null or p_mode is null then
    raise exception using errcode = 'SOL05', message = 'round_div: null argument';
  end if;
  if p_den <= 0 then
    raise exception using errcode = 'SOL05', message = 'round_div: denominator must be positive';
  end if;
  if p_mode not in ('half_even', 'half_up', 'floor', 'ceil') then
    raise exception using errcode = 'SOL05', message = format('round_div: unknown mode %s', p_mode);
  end if;

  q := p_num / p_den;            -- truncates toward zero
  r := p_num % p_den;            -- remainder carries the numerator's sign
  if r = 0 then
    return q;
  end if;

  away := case when p_num < 0 then -1 else 1 end;  -- one step away from zero
  twice_r := abs(r)::numeric * 2;

  case p_mode
    when 'floor' then
      return case when p_num < 0 then q - 1 else q end;
    when 'ceil' then
      return case when p_num > 0 then q + 1 else q end;
    when 'half_up' then
      return case when twice_r >= p_den then q + away else q end;
    else -- half_even
      if twice_r > p_den then
        return q + away;
      elsif twice_r < p_den then
        return q;
      else
        return case when q % 2 = 0 then q else q + away end;
      end if;
  end case;
end;
$$;

-- Basis-point helper: amount * bps / 10000 with explicit rounding. bigint multiply overflow raises.
create function app.apply_bps(p_amount_kobo bigint, p_bps integer, p_mode text default 'half_even')
returns bigint
language sql
immutable
set search_path = ''
as $$
  select app.round_div(p_amount_kobo * p_bps, 10000, p_mode)
$$;

-- Shared guard for append-only tables (ledgers, audit).
create function app.tg_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = 'SOL06',
    message = format('%s.%s is append-only: %s is not allowed', tg_table_schema, tg_table_name, tg_op);
end;
$$;

-- Shared guard for projections: only writable from inside another trigger (the ledger trigger).
create function app.tg_projection_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'TRUNCATE' or pg_trigger_depth() < 2 then
    raise exception using
      errcode = 'SOL06',
      message = format('%s.%s is a projection maintained by ledger triggers: direct %s is not allowed',
                       tg_table_schema, tg_table_name, tg_op);
  end if;
  return coalesce(new, old);
end;
$$;

create function app.tg_set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
