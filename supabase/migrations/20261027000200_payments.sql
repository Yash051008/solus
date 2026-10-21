-- Phase 5b-1: virtual accounts, provider events (webhooks), order settlement from wallet and/or trade credit
-- (credit needs the shop's OTP), cash collected at delivery, credit limits and repayment, receipt allocation,
-- and statement reconciliation. ADR-0008.

create or replace function app.account_normal_side(p_type public.account_type)
returns text
language sql immutable set search_path = ''
as $$
  select case when p_type in ('wallet', 'variance_offset', 'sales_revenue', 'unallocated_receipts') then 'credit' else 'debit' end
$$;

alter table public.account_balances drop constraint account_balances_sign_rules;
alter table public.account_balances add constraint account_balances_sign_rules check (
  case account_type
    when 'wallet'               then balance_kobo <= 0
    when 'variance_offset'      then balance_kobo <= 0
    when 'unallocated_receipts' then balance_kobo <= 0   -- cannot allocate more than was received
    when 'provider_clearing'    then balance_kobo >= 0
    when 'partner_funds'        then balance_kobo >= 0
    when 'trade_credit'         then balance_kobo >= 0
    when 'cash_in_transit'      then balance_kobo >= 0
    when 'variance'             then balance_kobo >= 0
    else true
  end
);

-- A shop may confirm its own credit purchase (initiator = recipient); handovers/returns stay two-party.
alter table private.otp_challenges drop constraint otp_two_distinct_parties;
alter table private.otp_challenges add constraint otp_two_distinct_parties
  check (purpose = 'credit' or initiator_user_id <> recipient_user_id);
alter table private.otp_challenges drop constraint otp_challenges_subject_kind_check;
alter table private.otp_challenges add constraint otp_challenges_subject_kind_check check (subject_kind in ('shipment', 'order', 'payment'));

create table public.virtual_accounts (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null unique references public.organisations (id),
  provider       text not null check (provider ~ '^[a-z][a-z0-9_]{1,30}$'),
  account_number text not null check (account_number ~ '^\d{10}$'),
  bank_name      text not null,
  provider_ref   text not null,
  created_at     timestamptz not null default now(),
  unique (provider, account_number)
);

create table public.provider_events (
  id                uuid primary key default gen_random_uuid(),
  provider          text not null,
  provider_event_id text not null,
  reference         text not null,
  account_number    text not null,
  amount_kobo       bigint not null check (amount_kobo > 0),
  payload_hash      text not null,
  org_id            uuid references public.organisations (id),
  status            text not null check (status in ('posted', 'unmatched')),
  journal_id        uuid references public.journals (id),
  duplicate_count   integer not null default 0,
  last_duplicate_at timestamptz,
  hash_conflict     boolean not null default false,
  paid_at           timestamptz,
  received_at       timestamptz not null default now(),
  unique (provider, provider_event_id)
);
create index provider_events_org_idx on public.provider_events (org_id, received_at desc);

create table public.receipt_allocations (
  id                uuid primary key default gen_random_uuid(),
  provider_event_id uuid not null references public.provider_events (id),
  org_id            uuid not null references public.organisations (id),
  target_kind       text not null check (target_kind in ('agent_cash', 'shop_debt')),
  target_user_id    uuid references public.profiles (user_id),
  target_org_id     uuid references public.organisations (id),
  amount_kobo       bigint not null check (amount_kobo > 0),
  journal_id        uuid not null references public.journals (id),
  allocated_by      uuid not null references public.profiles (user_id),
  created_at        timestamptz not null default now(),
  check ((target_kind = 'agent_cash') = (target_user_id is not null)),
  check ((target_kind = 'shop_debt') = (target_org_id is not null))
);

create table public.order_payments (
  id                 uuid primary key default gen_random_uuid(),
  order_id           uuid not null references public.orders (id),
  distributor_org_id uuid not null references public.organisations (id),
  retailer_org_id    uuid not null references public.organisations (id),
  wallet_kobo        bigint not null default 0 check (wallet_kobo >= 0),
  credit_kobo        bigint not null default 0 check (credit_kobo >= 0),
  cash_kobo          bigint not null default 0 check (cash_kobo >= 0),
  status             text not null check (status in ('pending_otp', 'settled', 'cancelled')),
  challenge_id       uuid,
  journal_id         uuid references public.journals (id),
  idempotency_key    text not null unique check (length(idempotency_key) >= 8),
  created_by         uuid not null references public.profiles (user_id),
  created_at         timestamptz not null default now(),
  settled_at         timestamptz,
  check (wallet_kobo + credit_kobo + cash_kobo > 0)
);
create index order_payments_order_idx on public.order_payments (order_id);

create function app.order_amount_due(p_order_id uuid)
returns bigint
language sql stable security definer set search_path = ''
as $$
  select coalesce((select sum(invoiced_kobo) from public.deliveries where order_id = p_order_id), 0)
       - coalesce((select sum(wallet_kobo + credit_kobo + cash_kobo) from public.order_payments
                   where order_id = p_order_id and status = 'settled'), 0)
$$;

-- service_role (payments adapter): record the VA it created at the provider.
create function app.provision_virtual_account(p_org_id uuid, p_provider text, p_account_number text, p_bank_name text, p_provider_ref text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
  v_kind public.org_kind;
begin
  select kind into strict v_kind from public.organisations where id = p_org_id;
  if v_kind not in ('retailer', 'distributor') then
    raise exception using errcode = 'SOL05', message = 'only shops and distributors get virtual accounts';
  end if;
  insert into public.virtual_accounts (org_id, provider, account_number, bank_name, provider_ref)
  values (p_org_id, p_provider, p_account_number, p_bank_name, p_provider_ref)
  on conflict (org_id) do nothing
  returning id into v_id;
  if v_id is null then
    select id into strict v_id from public.virtual_accounts where org_id = p_org_id;
  end if;
  perform app.ensure_account((select id from public.organisations where kind = 'platform'), 'wallet', p_holder_org_id => p_org_id);
  return v_id;
end;
$$;

-- service_role (webhook adapter, after signature verification). Idempotent on (provider, provider_event_id).
create function app.record_provider_event(
  p_provider text, p_provider_event_id text, p_reference text, p_account_number text,
  p_amount_kobo bigint, p_payload_hash text, p_paid_at timestamptz default null
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_existing public.provider_events;
  v_va       public.virtual_accounts;
  v_kind     public.org_kind;
  v_platform uuid := (select id from public.organisations where kind = 'platform');
  v_clearing uuid;
  v_entries  jsonb;
  v_id       uuid;
  v_jid      uuid;
begin
  select * into v_existing from public.provider_events where provider = p_provider and provider_event_id = p_provider_event_id for update;
  if found then
    update public.provider_events
       set duplicate_count = duplicate_count + 1, last_duplicate_at = now(),
           hash_conflict = hash_conflict or payload_hash <> p_payload_hash
     where id = v_existing.id;
    return jsonb_build_object('status', 'duplicate', 'event', v_existing.id, 'hash_match', v_existing.payload_hash = p_payload_hash);
  end if;
  if p_amount_kobo is null or p_amount_kobo <= 0 then
    raise exception using errcode = 'SOL05', message = 'amount must be a positive number of kobo';
  end if;

  select * into v_va from public.virtual_accounts where provider = p_provider and account_number = p_account_number;
  if not found then
    insert into public.provider_events (provider, provider_event_id, reference, account_number, amount_kobo, payload_hash, status, paid_at)
    values (p_provider, p_provider_event_id, p_reference, p_account_number, p_amount_kobo, p_payload_hash, 'unmatched', p_paid_at)
    returning id into v_id;
    return jsonb_build_object('status', 'unmatched', 'event', v_id);
  end if;

  select kind into strict v_kind from public.organisations where id = v_va.org_id;
  v_clearing := app.ensure_account(v_platform, 'provider_clearing', p_provider => p_provider);
  v_entries := jsonb_build_array(
    jsonb_build_object('account_id', v_clearing, 'amount_kobo', p_amount_kobo::text),
    jsonb_build_object('account_id', app.ensure_account(v_platform, 'wallet', p_holder_org_id => v_va.org_id), 'amount_kobo', (-p_amount_kobo)::text));
  if v_kind = 'distributor' then
    v_entries := v_entries || jsonb_build_array(
      jsonb_build_object('account_id', app.ensure_account(v_va.org_id, 'partner_funds'), 'amount_kobo', p_amount_kobo::text),
      jsonb_build_object('account_id', app.ensure_account(v_va.org_id, 'unallocated_receipts'), 'amount_kobo', (-p_amount_kobo)::text));
  end if;

  insert into public.provider_events (provider, provider_event_id, reference, account_number, amount_kobo, payload_hash, org_id, status, paid_at)
  values (p_provider, p_provider_event_id, p_reference, p_account_number, p_amount_kobo, p_payload_hash, v_va.org_id, 'posted', p_paid_at)
  returning id into v_id;
  v_jid := app.post_journal('va_inflow', p_provider || ':' || p_provider_event_id, v_entries, 'provider_event', v_id, 'transfer received');
  update public.provider_events set journal_id = v_jid where id = v_id;
  return jsonb_build_object('status', 'posted', 'event', v_id, 'org_id', v_va.org_id);
end;
$$;

-- Distributor admin allocates money that arrived in its VA (agent remittance or a shop paying directly).
create function app.allocate_receipt(p_event_id uuid, p_target_kind text, p_target_id uuid, p_amount_kobo bigint)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
  v_ev  public.provider_events;
  v_allocated bigint;
  v_credit uuid;
  v_jid uuid;
  v_id  uuid;
begin
  select * into v_ev from public.provider_events where id = p_event_id for update;
  if not found or v_ev.status <> 'posted' or v_ev.org_id is null
     or (select kind from public.organisations where id = v_ev.org_id) <> 'distributor' then
    raise exception using errcode = 'SOL05', message = 'not a receipt into a distributor account';
  end if;
  perform app.require_role(v_ev.org_id, array['distributor_admin']::public.member_role[]);
  select coalesce(sum(amount_kobo), 0) into v_allocated from public.receipt_allocations where provider_event_id = p_event_id;
  if p_amount_kobo <= 0 or v_allocated + p_amount_kobo > v_ev.amount_kobo then
    raise exception using errcode = 'SOL05', message = format('only %s kobo of this receipt is unallocated', v_ev.amount_kobo - v_allocated);
  end if;
  if p_target_kind = 'agent_cash' then
    v_credit := app.ensure_account(v_ev.org_id, 'cash_in_transit', p_counterparty_user_id => p_target_id);
  elsif p_target_kind = 'shop_debt' then
    v_credit := app.ensure_account(v_ev.org_id, 'receivables', p_counterparty_org_id => p_target_id);
  else
    raise exception using errcode = 'SOL05', message = 'target must be agent_cash or shop_debt';
  end if;
  v_id := gen_random_uuid();
  v_jid := app.post_journal('receipt_allocated', 'allocation:' || v_id, jsonb_build_array(
    jsonb_build_object('account_id', app.ensure_account(v_ev.org_id, 'unallocated_receipts'), 'amount_kobo', p_amount_kobo::text),
    jsonb_build_object('account_id', v_credit, 'amount_kobo', (-p_amount_kobo)::text)), 'provider_event', p_event_id, p_target_kind);
  insert into public.receipt_allocations (id, provider_event_id, org_id, target_kind, target_user_id, target_org_id, amount_kobo, journal_id, allocated_by)
  values (v_id, p_event_id, v_ev.org_id, p_target_kind,
          case when p_target_kind = 'agent_cash' then p_target_id end, case when p_target_kind = 'shop_debt' then p_target_id end,
          p_amount_kobo, v_jid, v_uid);
  return v_id;
end;
$$;

create function app.set_credit_limit(p_relationship_id uuid, p_limit_kobo bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_cr public.customer_relationships;
begin
  select * into v_cr from public.customer_relationships where id = p_relationship_id for update;
  if not found then
    raise exception using errcode = 'SOL05', message = 'customer not found';
  end if;
  perform app.require_role(v_cr.distributor_org_id, array['distributor_admin']::public.member_role[]);
  if p_limit_kobo is null or p_limit_kobo < 0 then
    raise exception using errcode = 'SOL05', message = 'limit must be zero or more';
  end if;
  update public.customer_relationships set credit_limit_kobo = p_limit_kobo where id = p_relationship_id;
end;
$$;

-- Internal: post a settled payment (wallet and/or credit legs) as ONE journal, under the credit-limit lock.
create function app.complete_order_payment(p_payment_id uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_p        public.order_payments;
  v_cr       public.customer_relationships;
  v_platform uuid := (select id from public.organisations where kind = 'platform');
  v_drawn    bigint;
  v_entries  jsonb := '[]'::jsonb;
  v_recv     uuid;
  v_jid      uuid;
begin
  select * into v_p from public.order_payments where id = p_payment_id for update;
  if v_p.status <> 'pending_otp' then
    raise exception using errcode = 'SOL04', message = 'payment is not pending';
  end if;
  if v_p.wallet_kobo + v_p.credit_kobo > app.order_amount_due(v_p.order_id) then
    raise exception using errcode = 'SOL04', message = 'payment exceeds the amount due';
  end if;
  v_recv := app.ensure_account(v_p.distributor_org_id, 'receivables', p_counterparty_org_id => v_p.retailer_org_id);

  if v_p.credit_kobo > 0 then
    select * into strict v_cr from public.customer_relationships
     where distributor_org_id = v_p.distributor_org_id and retailer_org_id = v_p.retailer_org_id for update;   -- serialises draws
    select coalesce(b.balance_kobo, 0) into v_drawn from public.accounts a
      left join public.account_balances b on b.account_id = a.id
     where a.book_org_id = v_p.distributor_org_id and a.account_type = 'trade_credit' and a.counterparty_org_id = v_p.retailer_org_id;
    if coalesce(v_drawn, 0) + v_p.credit_kobo > v_cr.credit_limit_kobo then
      raise exception using errcode = 'SOL04', message = 'credit_limit_exceeded',
        detail = format('limit %s, drawn %s, requested %s', v_cr.credit_limit_kobo, coalesce(v_drawn, 0), v_p.credit_kobo);
    end if;
    v_entries := v_entries || jsonb_build_array(
      jsonb_build_object('account_id', app.ensure_account(v_p.distributor_org_id, 'trade_credit', p_counterparty_org_id => v_p.retailer_org_id), 'amount_kobo', v_p.credit_kobo::text),
      jsonb_build_object('account_id', v_recv, 'amount_kobo', (-v_p.credit_kobo)::text));
  end if;
  if v_p.wallet_kobo > 0 then
    v_entries := v_entries || jsonb_build_array(
      jsonb_build_object('account_id', app.ensure_account(v_platform, 'wallet', p_holder_org_id => v_p.retailer_org_id), 'amount_kobo', v_p.wallet_kobo::text),
      jsonb_build_object('account_id', app.ensure_account(v_platform, 'wallet', p_holder_org_id => v_p.distributor_org_id), 'amount_kobo', (-v_p.wallet_kobo)::text),
      jsonb_build_object('account_id', app.ensure_account(v_p.distributor_org_id, 'partner_funds'), 'amount_kobo', v_p.wallet_kobo::text),
      jsonb_build_object('account_id', v_recv, 'amount_kobo', (-v_p.wallet_kobo)::text));
  end if;

  v_jid := app.post_journal(case when v_p.credit_kobo > 0 and v_p.wallet_kobo > 0 then 'split_payment'
                                 when v_p.credit_kobo > 0 then 'settle_credit' else 'settle_wallet' end,
                            'order_payment:' || p_payment_id, v_entries, 'order_payment', p_payment_id, 'order payment');
  update public.order_payments set status = 'settled', journal_id = v_jid, settled_at = now() where id = p_payment_id;
  if app.order_amount_due(v_p.order_id) = 0 then
    update public.orders set status = 'settled' where id = v_p.order_id and status in ('delivered', 'partially_delivered');
  end if;
  return 'settled';
end;
$$;

-- Shop (or the agent covering it) starts a payment. Wallet-only settles at once; any credit needs the shop's
-- OTP (sent to the shop owner's phone). Idempotent.
create function app.start_order_payment(p_order_id uuid, p_wallet_kobo bigint, p_credit_kobo bigint, p_idempotency_key text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := app.require_user();
  v_order public.orders;
  v_owner uuid;
  v_id    uuid;
  v_chal  uuid;
  v_existing public.order_payments;
begin
  select * into v_existing from public.order_payments where idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('payment_id', v_existing.id, 'status', v_existing.status, 'challenge_id', v_existing.challenge_id, 'replayed', true);
  end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception using errcode = 'SOL05', message = 'order not found';
  end if;
  if not (app.has_role(v_order.retailer_org_id, array['retailer']::public.member_role[])
          or (app.has_role(v_order.distributor_org_id, array['agent']::public.member_role[])
              and v_order.retailer_org_id = any(app.visible_retailer_ids()))) then
    raise exception using errcode = 'SOL03', message = 'only the shop (or its agent) can pay this order';
  end if;
  if coalesce(p_wallet_kobo, 0) < 0 or coalesce(p_credit_kobo, 0) < 0 or coalesce(p_wallet_kobo, 0) + coalesce(p_credit_kobo, 0) = 0 then
    raise exception using errcode = 'SOL05', message = 'enter a positive amount';
  end if;
  if p_wallet_kobo + p_credit_kobo > app.order_amount_due(p_order_id) then
    raise exception using errcode = 'SOL05', message = format('amount due is %s kobo', app.order_amount_due(p_order_id));
  end if;
  if exists (select 1 from public.order_payments where order_id = p_order_id and status = 'pending_otp') then
    update public.order_payments set status = 'cancelled' where order_id = p_order_id and status = 'pending_otp';
  end if;

  insert into public.order_payments (order_id, distributor_org_id, retailer_org_id, wallet_kobo, credit_kobo, status, idempotency_key, created_by)
  values (p_order_id, v_order.distributor_org_id, v_order.retailer_org_id, p_wallet_kobo, p_credit_kobo, 'pending_otp', p_idempotency_key, v_uid)
  returning id into v_id;

  if p_credit_kobo = 0 then
    perform app.complete_order_payment(v_id);
    return jsonb_build_object('payment_id', v_id, 'status', 'settled', 'replayed', false);
  end if;
  select m.user_id into v_owner from public.memberships m
   where m.org_id = v_order.retailer_org_id and m.role = 'retailer' and m.status = 'active' order by m.created_at limit 1;
  v_chal := app.open_otp_challenge('credit', 'payment', v_id, v_uid, v_owner);
  update public.order_payments set challenge_id = v_chal where id = v_id;
  return jsonb_build_object('payment_id', v_id, 'status', 'pending_otp', 'challenge_id', v_chal, 'replayed', false);
end;
$$;

-- Carrier records cash handed over by the shop at delivery (cash in transit until remitted).
create function app.record_delivery_cash(p_order_id uuid, p_amount_kobo bigint, p_idempotency_key text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := app.require_user();
  v_order public.orders;
  v_id    uuid;
  v_jid   uuid;
begin
  select id into v_id from public.order_payments where idempotency_key = p_idempotency_key;
  if found then return v_id; end if;
  select * into strict v_order from public.orders where id = p_order_id for update;
  if not exists (select 1 from public.deliveries d join public.shipments s on s.id = d.shipment_id
                 join public.stock_locations sl on sl.id = s.carrier_location_id
                 where d.order_id = p_order_id and sl.user_id = v_uid) then
    raise exception using errcode = 'SOL03', message = 'only the carrier who delivered this order can record cash for it';
  end if;
  if p_amount_kobo is null or p_amount_kobo <= 0 or p_amount_kobo > app.order_amount_due(p_order_id) then
    raise exception using errcode = 'SOL05', message = format('cash must be between 1 and %s kobo', app.order_amount_due(p_order_id));
  end if;
  v_id := gen_random_uuid();
  v_jid := app.post_journal('cash_collected', 'delivery_cash:' || v_id, jsonb_build_array(
    jsonb_build_object('account_id', app.ensure_account(v_order.distributor_org_id, 'cash_in_transit', p_counterparty_user_id => v_uid), 'amount_kobo', p_amount_kobo::text),
    jsonb_build_object('account_id', app.ensure_account(v_order.distributor_org_id, 'receivables', p_counterparty_org_id => v_order.retailer_org_id), 'amount_kobo', (-p_amount_kobo)::text)),
    'order', p_order_id, 'cash at delivery');
  insert into public.order_payments (id, order_id, distributor_org_id, retailer_org_id, cash_kobo, status, journal_id, idempotency_key, created_by, settled_at)
  values (v_id, p_order_id, v_order.distributor_org_id, v_order.retailer_org_id, p_amount_kobo, 'settled', v_jid, p_idempotency_key, v_uid, now());
  if app.order_amount_due(p_order_id) = 0 then
    update public.orders set status = 'settled' where id = p_order_id and status in ('delivered', 'partially_delivered');
  end if;
  return v_id;
end;
$$;

-- Shop repays trade credit from its wallet.
create function app.repay_credit(p_distributor_id uuid, p_retailer_org_id uuid, p_amount_kobo bigint, p_idempotency_key text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_platform uuid := (select id from public.organisations where kind = 'platform');
begin
  perform app.require_role(p_retailer_org_id, array['retailer']::public.member_role[]);
  if p_amount_kobo is null or p_amount_kobo <= 0 then
    raise exception using errcode = 'SOL05', message = 'enter a positive amount';
  end if;
  return app.post_journal('credit_repaid', p_idempotency_key, jsonb_build_array(
    jsonb_build_object('account_id', app.ensure_account(v_platform, 'wallet', p_holder_org_id => p_retailer_org_id), 'amount_kobo', p_amount_kobo::text),
    jsonb_build_object('account_id', app.ensure_account(v_platform, 'wallet', p_holder_org_id => p_distributor_id), 'amount_kobo', (-p_amount_kobo)::text),
    jsonb_build_object('account_id', app.ensure_account(p_distributor_id, 'partner_funds'), 'amount_kobo', p_amount_kobo::text),
    jsonb_build_object('account_id', app.ensure_account(p_distributor_id, 'trade_credit', p_counterparty_org_id => p_retailer_org_id), 'amount_kobo', (-p_amount_kobo)::text)),
    'credit_repayment', p_retailer_org_id, 'credit repaid from wallet');
end;
$$;

-- Read-only reconciliation of a provider statement against the ledger mirror.
-- p_lines: [{"provider_event_id","amount_kobo"}]. Platform admin or service_role.
create function app.reconcile_provider(p_provider text, p_lines jsonb)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if app.current_user_id() is not null and not app.is_platform_admin() then
    raise exception using errcode = 'SOL03', message = 'platform admin only';
  end if;
  with st as (
    select x->>'provider_event_id' as event_id, (x->>'amount_kobo')::bigint as amount from jsonb_array_elements(p_lines) x
  ), led as (
    select provider_event_id as event_id, amount_kobo as amount, status from public.provider_events where provider = p_provider
  )
  select jsonb_build_object(
    'missing_in_ledger', coalesce((select jsonb_agg(st.event_id) from st left join led using (event_id) where led.event_id is null), '[]'),
    'missing_in_statement', coalesce((select jsonb_agg(led.event_id) from led left join st using (event_id) where st.event_id is null), '[]'),
    'amount_mismatch', coalesce((select jsonb_agg(st.event_id) from st join led using (event_id) where st.amount <> led.amount), '[]'),
    'unmatched_accounts', coalesce((select jsonb_agg(event_id) from led where status = 'unmatched'), '[]'),
    'statement_total_kobo', (select coalesce(sum(amount), 0) from st)::text,
    'clearing_balance_kobo', coalesce((select b.balance_kobo from public.accounts a join public.account_balances b on b.account_id = a.id
                                       where a.account_type = 'provider_clearing' and a.provider = p_provider), 0)::text
  ) into v_result;
  return v_result;
end;
$$;

-- verify_otp gains the credit branch.
create or replace function app.verify_otp(p_challenge_id uuid, p_code text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
  v_c   private.otp_challenges;
  v_result text;
begin
  select * into v_c from private.otp_challenges where id = p_challenge_id for update;
  if not found then
    raise exception using errcode = 'SOL05', message = 'challenge not found';
  end if;
  if v_c.initiator_user_id <> v_uid then
    raise exception using errcode = 'SOL03', message = 'only the person who started this can enter the code';
  end if;
  if v_c.status <> 'pending' then
    return jsonb_build_object('ok', false, 'reason', v_c.status);
  end if;
  if v_c.code_hash is null then
    return jsonb_build_object('ok', false, 'reason', 'code_not_sent');
  end if;
  if v_c.expires_at < now() then
    update private.otp_challenges set status = 'expired' where id = p_challenge_id;
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;
  if p_code is null or extensions.crypt(p_code, v_c.code_hash) <> v_c.code_hash then
    update private.otp_challenges
       set attempts = attempts + 1,
           status = case when attempts + 1 >= max_attempts then 'locked' else status end
     where id = p_challenge_id;
    return jsonb_build_object('ok', false,
      'reason', case when v_c.attempts + 1 >= v_c.max_attempts then 'locked' else 'wrong_code' end,
      'attempts_left', greatest(v_c.max_attempts - v_c.attempts - 1, 0));
  end if;

  update private.otp_challenges set status = 'verified', verified_at = now() where id = p_challenge_id;
  if v_c.purpose = 'handover' then
    perform app.complete_push_handover(v_c.subject_id);
    v_result := 'open';
  elsif v_c.purpose = 'return' then
    v_result := app.complete_push_return(v_c.subject_id, v_c.payload_hash);
  elsif v_c.purpose = 'credit' then
    v_result := app.complete_order_payment(v_c.subject_id);
  end if;
  return jsonb_build_object('ok', true, 'purpose', v_c.purpose, 'result', v_result);
end;
$$;

-- Credit position per customer relationship (limit, drawn, available, owed on delivered goods).
create view public.v_credit_positions with (security_invoker = true) as
select cr.id as relationship_id, cr.distributor_org_id, cr.retailer_org_id, cr.credit_limit_kobo,
       coalesce((select b.balance_kobo from public.accounts a join public.account_balances b on b.account_id = a.id
                 where a.book_org_id = cr.distributor_org_id and a.account_type = 'trade_credit' and a.counterparty_org_id = cr.retailer_org_id), 0) as drawn_kobo,
       coalesce((select b.balance_kobo from public.accounts a join public.account_balances b on b.account_id = a.id
                 where a.book_org_id = cr.distributor_org_id and a.account_type = 'receivables' and a.counterparty_org_id = cr.retailer_org_id), 0) as receivable_kobo
from public.customer_relationships cr;

-- RLS, audit, grants
alter table public.virtual_accounts enable row level security;
alter table public.provider_events enable row level security;
alter table public.receipt_allocations enable row level security;
alter table public.order_payments enable row level security;

create policy virtual_accounts_select on public.virtual_accounts for select to authenticated using (
  (select app.is_platform_admin()) or org_id = any((select app.my_org_ids())::uuid[]));
create policy provider_events_select on public.provider_events for select to authenticated using (
  (select app.is_platform_admin())
  or org_id = any((select app.my_org_ids_with_role(array['distributor_admin', 'retailer']::public.member_role[]))::uuid[]));
create policy receipt_allocations_select on public.receipt_allocations for select to authenticated using (
  (select app.is_platform_admin()) or org_id = any((select app.my_org_ids_with_role(array['distributor_admin']::public.member_role[]))::uuid[])
  or target_user_id = (select app.current_user_id()));
create policy order_payments_select on public.order_payments for select to authenticated using (
  (select app.is_platform_admin()) or order_id = any((select app.visible_order_ids())::uuid[]));

select audit.attach(t::regclass) from unnest(array['public.virtual_accounts', 'public.provider_events',
  'public.receipt_allocations', 'public.order_payments']) t;

revoke all on public.virtual_accounts, public.provider_events, public.receipt_allocations, public.order_payments,
  public.v_credit_positions from anon, authenticated;
grant select on public.virtual_accounts, public.provider_events, public.receipt_allocations, public.order_payments,
  public.v_credit_positions to authenticated;
revoke insert, update, delete, truncate on public.provider_events, public.order_payments from service_role;

revoke all on function
  app.order_amount_due(uuid), app.provision_virtual_account(uuid, text, text, text, text),
  app.record_provider_event(text, text, text, text, bigint, text, timestamptz),
  app.allocate_receipt(uuid, text, uuid, bigint), app.set_credit_limit(uuid, bigint), app.complete_order_payment(uuid),
  app.start_order_payment(uuid, bigint, bigint, text), app.record_delivery_cash(uuid, bigint, text),
  app.repay_credit(uuid, uuid, bigint, text), app.reconcile_provider(text, jsonb), app.verify_otp(uuid, text),
  app.account_normal_side(public.account_type)
from public, anon, authenticated;
grant execute on function
  app.order_amount_due(uuid), app.allocate_receipt(uuid, text, uuid, bigint), app.set_credit_limit(uuid, bigint),
  app.start_order_payment(uuid, bigint, bigint, text), app.record_delivery_cash(uuid, bigint, text),
  app.repay_credit(uuid, uuid, bigint, text), app.reconcile_provider(text, jsonb), app.verify_otp(uuid, text),
  app.account_normal_side(public.account_type)
to authenticated;
grant execute on function
  app.provision_virtual_account(uuid, text, text, text, text), app.record_provider_event(text, text, text, text, bigint, text, timestamptz),
  app.reconcile_provider(text, jsonb)
to service_role;
