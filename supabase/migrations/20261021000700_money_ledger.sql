-- Money: per-book double-entry ledger (hard rule 2, ADR-0003 D5).
-- amount_kobo is signed: debit = positive, credit = negative. Every journal sums to zero PER BOOK.

create function app.account_normal_side(p_type public.account_type)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_type in ('wallet', 'variance_offset', 'sales_revenue') then 'credit' else 'debit' end
$$;

create table public.accounts (
  id                   uuid primary key default gen_random_uuid(),
  book_org_id          uuid not null,
  book_kind            public.org_kind not null,
  account_type         public.account_type not null,
  holder_org_id        uuid references public.organisations (id),
  counterparty_org_id  uuid references public.organisations (id),
  counterparty_user_id uuid references public.profiles (user_id),
  provider             text check (provider ~ '^[a-z][a-z0-9_]{1,30}$'),
  created_at           timestamptz not null default now(),
  foreign key (book_org_id, book_kind) references public.organisations (id, kind),
  unique nulls not distinct
    (book_org_id, account_type, holder_org_id, counterparty_org_id, counterparty_user_id, provider),
  constraint accounts_book_matches_type check (
    case when account_type in ('provider_clearing', 'wallet')
         then book_kind = 'platform'
         else book_kind = 'distributor' end
  ),
  constraint accounts_shape check (
    case account_type
      when 'provider_clearing' then provider is not null and holder_org_id is null
                                    and counterparty_org_id is null and counterparty_user_id is null
      when 'wallet'            then holder_org_id is not null and provider is null
                                    and counterparty_org_id is null and counterparty_user_id is null
      when 'receivables'       then holder_org_id is null and provider is null
                                    and (counterparty_org_id is null) <> (counterparty_user_id is null)
      when 'trade_credit'      then counterparty_org_id is not null and counterparty_user_id is null
                                    and holder_org_id is null and provider is null
      when 'cash_in_transit'   then counterparty_user_id is not null and counterparty_org_id is null
                                    and holder_org_id is null and provider is null
      when 'variance'          then counterparty_user_id is not null and counterparty_org_id is null
                                    and holder_org_id is null and provider is null
      else holder_org_id is null and counterparty_org_id is null
           and counterparty_user_id is null and provider is null
    end
  )
);
create index accounts_book_idx on public.accounts (book_org_id);
create index accounts_holder_idx on public.accounts (holder_org_id);
create index accounts_cp_org_idx on public.accounts (counterparty_org_id);
create index accounts_cp_user_idx on public.accounts (counterparty_user_id);

create table public.journals (
  id                  uuid primary key default gen_random_uuid(),
  journal_type        text not null check (journal_type ~ '^[a-z][a-z_]{2,40}$'),
  idempotency_key     text not null unique check (length(idempotency_key) between 8 and 200),
  request_hash        text not null,
  ref_kind            text check (ref_kind ~ '^[a-z][a-z_]{1,40}$'),
  ref_id              uuid,
  reverses_journal_id uuid references public.journals (id),
  memo                text,
  posted_by           uuid,
  posted_at           timestamptz not null default now(),
  constraint journals_ref_pair check ((ref_kind is null) = (ref_id is null))
);
create index journals_ref_idx on public.journals (ref_kind, ref_id);

create table public.ledger_entries (
  id          uuid primary key default gen_random_uuid(),
  journal_id  uuid not null references public.journals (id),
  account_id  uuid not null references public.accounts (id),
  book_org_id uuid not null,
  amount_kobo bigint not null check (amount_kobo <> 0),
  created_at  timestamptz not null default now()
);
create index ledger_entries_journal_idx on public.ledger_entries (journal_id);
create index ledger_entries_account_idx on public.ledger_entries (account_id);
create index ledger_entries_book_idx on public.ledger_entries (book_org_id);

-- Balances: signed (debit-positive) sum per account. CHECKs forbid impossible states such as an
-- overdrawn wallet or negative cash held by an agent.
create table public.account_balances (
  account_id   uuid primary key references public.accounts (id),
  book_org_id  uuid not null,
  account_type public.account_type not null,
  balance_kobo bigint not null default 0,
  updated_at   timestamptz not null default now(),
  constraint account_balances_sign_rules check (
    case account_type
      when 'wallet'            then balance_kobo <= 0
      when 'variance_offset'   then balance_kobo <= 0
      when 'provider_clearing' then balance_kobo >= 0
      when 'partner_funds'     then balance_kobo >= 0
      when 'trade_credit'      then balance_kobo >= 0
      when 'cash_in_transit'   then balance_kobo >= 0
      when 'variance'          then balance_kobo >= 0
      else true                -- receivables (overpayment), sales_revenue (reversals)
    end
  )
);
create index account_balances_book_idx on public.account_balances (book_org_id);

-- Display view: balance in the account's natural sign.
create view public.v_account_balances
with (security_invoker = true)
as
select b.account_id, b.book_org_id, b.account_type,
       app.account_normal_side(b.account_type) as normal_side,
       case when app.account_normal_side(b.account_type) = 'debit'
            then b.balance_kobo else -b.balance_kobo end as balance_kobo,
       b.updated_at
from public.account_balances b;

-- book_org_id on an entry is always the account's book (never caller-supplied).
create function app.tg_ledger_entry_set_book()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select book_org_id into strict new.book_org_id from public.accounts where id = new.account_id;
  return new;
end;
$$;
create trigger ledger_entries_set_book before insert on public.ledger_entries
  for each row execute function app.tg_ledger_entry_set_book();

create function app.tg_ledger_entry_apply()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Update first, insert only if missing (see app.tg_stock_movement_apply for why not ON CONFLICT).
  update public.account_balances
     set balance_kobo = balance_kobo + new.amount_kobo, updated_at = now()   -- bigint overflow raises
   where account_id = new.account_id;
  if not found then
    begin
      insert into public.account_balances (account_id, book_org_id, account_type, balance_kobo)
      select a.id, a.book_org_id, a.account_type, new.amount_kobo
      from public.accounts a where a.id = new.account_id;
    exception when unique_violation then
      update public.account_balances
         set balance_kobo = balance_kobo + new.amount_kobo, updated_at = now()
       where account_id = new.account_id;
    end;
  end if;
  return null;
end;
$$;
create trigger ledger_entries_apply after insert on public.ledger_entries
  for each row execute function app.tg_ledger_entry_apply();

-- Zero-sum per (journal, book) and at least two entries per journal, checked at commit.
create function app.tg_journal_balanced()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_journal uuid;
  v_bad record;
  v_count integer;
begin
  if tg_table_name = 'journals' then
    v_journal := new.id;
  else
    v_journal := new.journal_id;
  end if;
  select count(*) into v_count from public.ledger_entries where journal_id = v_journal;
  if v_count < 2 then
    raise exception using errcode = 'SOL06',
      message = format('journal %s has %s entries; at least 2 required', v_journal, v_count);
  end if;
  select book_org_id, sum(amount_kobo) as net into v_bad
  from public.ledger_entries
  where journal_id = v_journal
  group by book_org_id
  having sum(amount_kobo) <> 0
  limit 1;
  if found then
    raise exception using errcode = 'SOL06',
      message = format('journal %s does not balance in book %s (net %s kobo)', v_journal, v_bad.book_org_id, v_bad.net);
  end if;
  return null;
end;
$$;
create constraint trigger ledger_entries_balanced
  after insert on public.ledger_entries
  deferrable initially deferred
  for each row execute function app.tg_journal_balanced();
create constraint trigger journals_have_entries
  after insert on public.journals
  deferrable initially deferred
  for each row execute function app.tg_journal_balanced();

create trigger journals_append_only before update or delete on public.journals
  for each row execute function app.tg_append_only();
create trigger journals_no_truncate before truncate on public.journals
  for each statement execute function app.tg_append_only();
create trigger ledger_entries_append_only before update or delete on public.ledger_entries
  for each row execute function app.tg_append_only();
create trigger ledger_entries_no_truncate before truncate on public.ledger_entries
  for each statement execute function app.tg_append_only();
create trigger account_balances_guard before insert or update or delete on public.account_balances
  for each row execute function app.tg_projection_guard();
create trigger account_balances_no_truncate before truncate on public.account_balances
  for each statement execute function app.tg_projection_guard();
