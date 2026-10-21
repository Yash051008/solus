-- Full audit log via triggers on all business tables (hard rule 8). Append-only: no grants to any
-- client role, and a trigger rejects UPDATE/DELETE/TRUNCATE even for the owner.
-- Projections (stock_balances, account_balances) are not audited: they are derived from audited ledgers.

create table audit.audit_log (
  id            bigint generated always as identity primary key,
  table_name    text not null,
  op            text not null check (op in ('INSERT', 'UPDATE', 'DELETE')),
  row_id        text,
  old_row       jsonb,
  new_row       jsonb,
  actor_user_id uuid,
  db_role       text not null default current_user,
  txid          bigint not null default txid_current(),
  at            timestamptz not null default now()
);
create index audit_log_table_row_idx on audit.audit_log (table_name, row_id);
create index audit_log_actor_idx on audit.audit_log (actor_user_id);
create index audit_log_at_idx on audit.audit_log (at);

create function audit.tg_log()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into audit.audit_log (table_name, op, row_id, old_row, new_row, actor_user_id)
  values (
    tg_table_schema || '.' || tg_table_name,
    tg_op,
    coalesce(to_jsonb(new) ->> 'id', to_jsonb(old) ->> 'id',
             to_jsonb(new) ->> 'user_id', to_jsonb(old) ->> 'user_id'),
    case when tg_op <> 'INSERT' then to_jsonb(old) end,
    case when tg_op <> 'DELETE' then to_jsonb(new) end,
    app.current_user_id()
  );
  return null;
end;
$$;

create trigger audit_log_append_only before update or delete on audit.audit_log
  for each row execute function app.tg_append_only();
create trigger audit_log_no_truncate before truncate on audit.audit_log
  for each statement execute function app.tg_append_only();

-- Attach to every business table in public except the two projections.
create function audit.attach(p_table regclass)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format(
    'create trigger audit_log after insert or update or delete on %s for each row execute function audit.tg_log()',
    p_table);
end;
$$;

do $$
declare
  t record;
begin
  for t in
    select tablename from pg_tables
    where schemaname = 'public' and tablename not in ('stock_balances', 'account_balances')
  loop
    perform audit.attach(format('public.%I', t.tablename)::regclass);
  end loop;
end;
$$;
