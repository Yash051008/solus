-- Internal ledger primitives (never granted to clients; called by app.* command functions)
-- and the atomic stock reservation (hard rule 3).

-- Find-or-create an account. Idempotent and race-safe via the NULLS NOT DISTINCT unique key.
create function app.ensure_account(
  p_book_org_id          uuid,
  p_account_type         public.account_type,
  p_holder_org_id        uuid default null,
  p_counterparty_org_id  uuid default null,
  p_counterparty_user_id uuid default null,
  p_provider             text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id   uuid;
  v_kind public.org_kind;
begin
  select kind into strict v_kind from public.organisations where id = p_book_org_id;

  insert into public.accounts
    (book_org_id, book_kind, account_type, holder_org_id, counterparty_org_id, counterparty_user_id, provider)
  values
    (p_book_org_id, v_kind, p_account_type, p_holder_org_id, p_counterparty_org_id, p_counterparty_user_id, p_provider)
  on conflict (book_org_id, account_type, holder_org_id, counterparty_org_id, counterparty_user_id, provider)
  do nothing
  returning id into v_id;

  if v_id is null then
    select id into strict v_id from public.accounts
    where book_org_id = p_book_org_id
      and account_type = p_account_type
      and holder_org_id is not distinct from p_holder_org_id
      and counterparty_org_id is not distinct from p_counterparty_org_id
      and counterparty_user_id is not distinct from p_counterparty_user_id
      and provider is not distinct from p_provider;
  end if;
  return v_id;
end;
$$;

-- Post one journal. p_entries: [{"account_id": uuid, "amount_kobo": "<signed integer>"}, ...]
-- (debit positive, credit negative). Idempotent: replaying a key returns the original journal id;
-- replaying a key with a different payload raises SOL02. Zero-sum per book is checked here
-- (friendly error) and again by the deferred constraint trigger at commit (guarantee).
create function app.post_journal(
  p_journal_type        text,
  p_idempotency_key     text,
  p_entries             jsonb,
  p_ref_kind            text default null,
  p_ref_id              uuid default null,
  p_memo                text default null,
  p_reverses_journal_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id            uuid;
  v_hash          text;
  v_existing_hash text;
  v_canonical     text;
  v_bad           record;
begin
  if p_entries is null or jsonb_typeof(p_entries) <> 'array' or jsonb_array_length(p_entries) < 2 then
    raise exception using errcode = 'SOL05', message = 'a journal needs at least 2 entries';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_entries) e
    where e->>'account_id' is null or e->>'amount_kobo' is null or (e->>'amount_kobo')::bigint = 0
  ) then
    raise exception using errcode = 'SOL05', message = 'every entry needs account_id and a non-zero integer amount_kobo';
  end if;

  select string_agg(format('%s:%s', e->>'account_id', (e->>'amount_kobo')::bigint), ','
                    order by e->>'account_id', (e->>'amount_kobo')::bigint)
  into v_canonical
  from jsonb_array_elements(p_entries) e;

  v_hash := encode(sha256(convert_to(concat_ws('|', p_journal_type, p_ref_kind, p_ref_id::text,
                                                p_reverses_journal_id::text, v_canonical), 'UTF8')), 'hex');

  insert into public.journals
    (journal_type, idempotency_key, request_hash, ref_kind, ref_id, reverses_journal_id, memo, posted_by)
  values
    (p_journal_type, p_idempotency_key, v_hash, p_ref_kind, p_ref_id, p_reverses_journal_id, p_memo,
     app.current_user_id())
  on conflict (idempotency_key) do nothing
  returning id into v_id;

  if v_id is null then
    select id, request_hash into strict v_id, v_existing_hash
    from public.journals where idempotency_key = p_idempotency_key;
    if v_existing_hash <> v_hash then
      raise exception using errcode = 'SOL02',
        message = format('idempotency key %s was already used with a different payload', p_idempotency_key);
    end if;
    return v_id;   -- replay: nothing new is posted
  end if;

  insert into public.ledger_entries (journal_id, account_id, book_org_id, amount_kobo)
  select v_id, (e->>'account_id')::uuid, null, (e->>'amount_kobo')::bigint   -- book set by trigger
  from jsonb_array_elements(p_entries) e;

  select book_org_id, sum(amount_kobo) as net into v_bad
  from public.ledger_entries where journal_id = v_id
  group by book_org_id having sum(amount_kobo) <> 0
  limit 1;
  if found then
    raise exception using errcode = 'SOL06',
      message = format('journal does not balance in book %s (net %s kobo)', v_bad.book_org_id, v_bad.net);
  end if;

  return v_id;
end;
$$;

-- Insert one ledger row with deltas derived from the type (p_sign only for handover/return/adjustment).
create function app.post_stock_movement(
  p_group_id        uuid,
  p_type            public.movement_type,
  p_location_id     uuid,
  p_sku_id          uuid,
  p_qty             integer,
  p_sign            integer default null,
  p_ref_kind        text default null,
  p_ref_id          uuid default null,
  p_reason          text default null,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id       uuid;
  v_org      uuid;
  v_on_hand  integer;
  v_reserved integer := 0;
begin
  if p_qty is null or p_qty <= 0 then
    raise exception using errcode = 'SOL05', message = 'qty must be a positive integer number of pieces';
  end if;
  if (p_type in ('handover', 'return', 'adjustment')) <> (p_sign is not null) then
    raise exception using errcode = 'SOL05',
      message = 'p_sign is required for handover/return/adjustment and forbidden otherwise';
  end if;
  if p_sign is not null and p_sign not in (1, -1) then
    raise exception using errcode = 'SOL05', message = 'p_sign must be 1 or -1';
  end if;

  select org_id into strict v_org from public.stock_locations where id = p_location_id;

  v_on_hand := case p_type
    when 'receipt'      then p_qty
    when 'transfer_in'  then p_qty
    when 'transfer_out' then -p_qty
    when 'sale'         then -p_qty
    when 'damage'       then -p_qty
    when 'reserve'      then 0
    when 'release'      then 0
    else p_sign * p_qty
  end;
  v_reserved := case p_type when 'reserve' then p_qty when 'release' then -p_qty else 0 end;

  insert into public.stock_movements
    (movement_group_id, movement_type, location_id, org_id, sku_id, qty, on_hand_delta, reserved_delta,
     ref_kind, ref_id, reason, actor_user_id, idempotency_key)
  values
    (p_group_id, p_type, p_location_id, v_org, p_sku_id, p_qty, v_on_hand, v_reserved,
     p_ref_kind, p_ref_id, p_reason, app.current_user_id(), p_idempotency_key)
  returning id into v_id;
  return v_id;
end;
$$;

-- Hard rule 3: reserve every line of an order at one warehouse, atomically.
-- Balance rows are locked FOR UPDATE in sku order (deterministic => no deadlocks), availability is
-- re-checked under the lock, and either every line is reserved or nothing is (SOL01).
-- The stock_balances CHECK (reserved <= on_hand) is the backstop if this logic were ever wrong.
create function app.reserve_order(p_order_id uuid, p_warehouse_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order    public.orders;
  v_location uuid;
  v_group    uuid := gen_random_uuid();
  v_need     record;
  v_avail    integer;
  v_line     record;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception using errcode = 'SOL05', message = format('order %s not found', p_order_id);
  end if;
  if v_order.status not in ('placed', 'awaiting_split_decision') then
    raise exception using errcode = 'SOL04',
      message = format('order %s is %s; only placed orders can be reserved', p_order_id, v_order.status);
  end if;

  select sl.id into v_location
  from public.stock_locations sl
  join public.warehouses w on w.id = sl.warehouse_id
  where sl.warehouse_id = p_warehouse_id
    and sl.kind = 'warehouse'
    and sl.org_id = v_order.distributor_org_id
    and w.active;
  if v_location is null then
    raise exception using errcode = 'SOL05',
      message = format('warehouse %s is not an active warehouse of the order''s distributor', p_warehouse_id);
  end if;

  for v_need in
    select sku_id, sum(qty_pieces)::integer as qty
    from public.order_lines where order_id = p_order_id
    group by sku_id
    order by sku_id
  loop
    select available into v_avail
    from public.stock_balances
    where location_id = v_location and sku_id = v_need.sku_id
    for update;

    if coalesce(v_avail, 0) < v_need.qty then
      raise exception using errcode = 'SOL01',
        message = 'insufficient_stock',
        detail = format('sku %s: need %s, available %s', v_need.sku_id, v_need.qty, coalesce(v_avail, 0));
    end if;
  end loop;

  if not found then
    raise exception using errcode = 'SOL05', message = format('order %s has no lines', p_order_id);
  end if;

  for v_line in
    select id, sku_id, qty_pieces from public.order_lines where order_id = p_order_id order by sku_id, id
  loop
    perform app.post_stock_movement(v_group, 'reserve', v_location, v_line.sku_id, v_line.qty_pieces,
                                    null, 'order', p_order_id, null, null);
    update public.order_lines set warehouse_id = p_warehouse_id where id = v_line.id;
  end loop;

  update public.orders set status = 'reserved' where id = p_order_id;
end;
$$;

-- Rebuild checks (hard rules 1 and 2): recompute balances from the ledgers and return any row
-- where the projection disagrees. Empty result = projection proven equal to the ledger.
create function app.check_stock_projection()
returns table (location_id uuid, sku_id uuid, ledger_on_hand bigint, ledger_reserved bigint,
               projected_on_hand integer, projected_reserved integer)
language sql
stable
security definer
set search_path = ''
as $$
  with ledger as (
    select m.location_id, m.sku_id, sum(m.on_hand_delta) as on_hand, sum(m.reserved_delta) as reserved
    from public.stock_movements m
    group by m.location_id, m.sku_id
  )
  select coalesce(l.location_id, b.location_id), coalesce(l.sku_id, b.sku_id),
         l.on_hand, l.reserved, b.on_hand, b.reserved
  from ledger l
  full join public.stock_balances b on b.location_id = l.location_id and b.sku_id = l.sku_id
  where l.on_hand is distinct from b.on_hand::bigint
     or l.reserved is distinct from b.reserved::bigint
$$;

create function app.check_money_projection()
returns table (account_id uuid, ledger_balance numeric, projected_balance bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with ledger as (
    select e.account_id, sum(e.amount_kobo) as balance
    from public.ledger_entries e
    group by e.account_id
  )
  select coalesce(l.account_id, b.account_id), l.balance, b.balance_kobo
  from ledger l
  full join public.account_balances b on b.account_id = l.account_id
  where l.balance is distinct from b.balance_kobo::numeric
$$;

create function app.check_journals_balanced()
returns table (journal_id uuid, book_org_id uuid, net numeric, entry_count bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select j.id, e.book_org_id, coalesce(sum(e.amount_kobo), 0), count(e.id)
  from public.journals j
  left join public.ledger_entries e on e.journal_id = j.id
  group by j.id, e.book_org_id
  having coalesce(sum(e.amount_kobo), 0) <> 0 or count(e.id) < 1
$$;
