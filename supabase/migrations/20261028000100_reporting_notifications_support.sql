-- Phase 6a: reporting views (security_invoker: every figure is computed only from rows the viewer may see),
-- manufacturer aggregates without retailer data, per-user notifications from domain triggers, and support
-- tickets (delivery disputes open one automatically).

-- Reporting -------------------------------------------------------------------------------------------
create view public.v_sales_daily with (security_invoker = true) as
select o.distributor_org_id as org_id, (d.recorded_at at time zone 'Africa/Lagos')::date as day, 'pull'::text as channel,
       sum(d.invoiced_kobo)::bigint as revenue_kobo, count(*)::integer as transactions
from public.deliveries d join public.orders o on o.id = d.order_id
group by 1, 2
union all
select s.org_id, (p.created_at at time zone 'Africa/Lagos')::date, 'push', sum(p.total_kobo)::bigint, count(*)::integer
from public.push_sales p join public.shipments s on s.id = p.shipment_id
group by 1, 2;

create view public.v_sku_performance with (security_invoker = true) as
select org_id, sku_id, sum(qty)::bigint as qty_pieces, sum(revenue)::bigint as revenue_kobo from (
  select o.distributor_org_id as org_id, a.sku_id, dl.delivered as qty,
         app.round_div(l.line_amount_kobo * dl.delivered, l.qty_pieces, 'half_even') as revenue
  from public.delivery_lines dl
  join public.order_allocations a on a.id = dl.allocation_id
  join public.order_lines l on l.id = a.order_line_id
  join public.orders o on o.id = a.order_id
  union all
  select s.org_id, pl.sku_id, pl.qty_pieces, pl.amount_kobo
  from public.push_sale_lines pl join public.push_sales p on p.id = pl.sale_id join public.shipments s on s.id = p.shipment_id
) x group by 1, 2;

create view public.v_agent_leaderboard with (security_invoker = true) as
select m.org_id, m.user_id as agent_user_id, pr.full_name,
       coalesce((select sum(p.total_kobo) from public.push_sales p where p.agent_user_id = m.user_id), 0)::bigint as sales_kobo,
       coalesce((select count(*) from public.push_sales p where p.agent_user_id = m.user_id), 0)::integer as sales_count,
       coalesce((select count(*) from public.agent_visits v where v.agent_user_id = m.user_id), 0)::integer as visits,
       coalesce((select count(*) from public.agent_visits v where v.agent_user_id = m.user_id and v.geofence_ok), 0)::integer as visits_in_geofence,
       coalesce((select count(*) from public.variance_cases c where c.carrier_user_id = m.user_id and c.status = 'pending'), 0)::integer as pending_variance
from public.memberships m join public.profiles pr on pr.user_id = m.user_id
where m.role = 'agent' and m.status = 'active';

-- Valued at the viewer-visible current price (piece price, else carton price / pieces): RLS on prices applies.
create view public.v_inventory_value with (security_invoker = true) as
select b.org_id, b.location_id, b.location_kind, b.sku_id, b.on_hand, b.reserved,
       (b.on_hand::bigint * coalesce(
          (select p.price_kobo from public.v_current_prices p where p.distributor_org_id = b.org_id and p.sku_id = b.sku_id and p.uom_code = 'piece'),
          (select app.round_div(p.price_kobo, u.pieces_per_uom, 'half_even') from public.v_current_prices p
             join public.sku_uom u on u.sku_id = p.sku_id and u.uom_code = p.uom_code
            where p.distributor_org_id = b.org_id and p.sku_id = b.sku_id and p.uom_code = 'carton'),
          0))::bigint as value_kobo
from public.stock_balances b;

-- Manufacturer view: totals per supplied distributor and SKU. No shop, person or order is exposed.
create function app.manufacturer_summary(p_manufacturer_id uuid)
returns table (distributor_org_id uuid, distributor_name text, sku_id uuid, qty_pieces bigint, revenue_kobo bigint, on_hand bigint)
language plpgsql stable security definer set search_path = ''
as $$
begin
  perform app.require_role(p_manufacturer_id, array['manufacturer_admin']::public.member_role[]);
  return query
  with supplied as (select s.distributor_org_id from public.supply_relationships s where s.manufacturer_org_id = p_manufacturer_id),
       own_skus as (select id from public.skus where manufacturer_org_id = p_manufacturer_id),
       sales as (
         select o.distributor_org_id as org_id, a.sku_id, sum(dl.delivered)::bigint as qty,
                sum(app.round_div(l.line_amount_kobo * dl.delivered, l.qty_pieces, 'half_even'))::bigint as rev
         from public.delivery_lines dl join public.order_allocations a on a.id = dl.allocation_id
         join public.order_lines l on l.id = a.order_line_id join public.orders o on o.id = a.order_id
         group by 1, 2
         union all
         select s.org_id, pl.sku_id, sum(pl.qty_pieces)::bigint, sum(pl.amount_kobo)::bigint
         from public.push_sale_lines pl join public.push_sales p on p.id = pl.sale_id join public.shipments s on s.id = p.shipment_id
         group by 1, 2
       ),
       stock as (select b.org_id, b.sku_id, sum(b.on_hand)::bigint as oh from public.stock_balances b group by 1, 2)
  select d.distributor_org_id, o.name, k.id,
         coalesce((select sum(x.qty) from sales x where x.org_id = d.distributor_org_id and x.sku_id = k.id), 0)::bigint,
         coalesce((select sum(x.rev) from sales x where x.org_id = d.distributor_org_id and x.sku_id = k.id), 0)::bigint,
         coalesce((select st.oh from stock st where st.org_id = d.distributor_org_id and st.sku_id = k.id), 0)::bigint
  from supplied d join public.organisations o on o.id = d.distributor_org_id cross join own_skus k;
end;
$$;

-- Notifications -----------------------------------------------------------------------------------------
create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (user_id),
  org_id     uuid references public.organisations (id),
  kind       text not null,
  title      text not null,
  body       text,
  link       text,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);

create function app.notify(p_user uuid, p_org uuid, p_kind text, p_title text, p_body text default null, p_link text default null)
returns void language sql security definer set search_path = ''
as $$
  insert into public.notifications (user_id, org_id, kind, title, body, link)
  select p_user, p_org, p_kind, p_title, p_body, p_link where p_user is not null
$$;

-- Users holding any of p_roles in p_org (optionally limited to one branch for branch roles).
create function app.org_users(p_org uuid, p_roles public.member_role[], p_branch uuid default null)
returns setof uuid language sql stable security definer set search_path = ''
as $$
  select distinct m.user_id from public.memberships m
  where m.org_id = p_org and m.status = 'active' and m.role = any(p_roles)
    and (p_branch is null or m.role = 'distributor_admin' or m.branch_id = p_branch)
$$;

create function app.tg_notify_order_status()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_title text := case new.status::text
    when 'reserved' then 'Order confirmed: stock reserved'
    when 'rejected' then 'Order could not be fulfilled'
    when 'dispatched' then 'Order on its way'
    when 'delivered' then 'Order delivered'
    when 'partially_delivered' then 'Order partly delivered'
    when 'settled' then 'Order paid in full'
    when 'cancelled' then 'Order cancelled'
    else null end;
  v_user uuid;
begin
  if v_title is null or new.status is not distinct from old.status then
    return null;
  end if;
  for v_user in select app.org_users(new.retailer_org_id, array['retailer']::public.member_role[]) loop
    perform app.notify(v_user, new.retailer_org_id, 'order', v_title, null, '/retailer/' || new.retailer_org_id || '/orders');
  end loop;
  return null;
end;
$$;
create trigger orders_notify after update of status on public.orders for each row execute function app.tg_notify_order_status();

create function app.tg_notify_provider_event()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid;
  v_kind public.org_kind;
begin
  if new.status <> 'posted' or new.org_id is null then return null; end if;
  select kind into v_kind from public.organisations where id = new.org_id;
  for v_user in select app.org_users(new.org_id, array['retailer', 'distributor_admin']::public.member_role[]) loop
    perform app.notify(v_user, new.org_id, 'payment', 'Transfer received',
      format('N%s.%s into your account', to_char(new.amount_kobo / 100, 'FM999,999,999,990'), lpad((new.amount_kobo % 100)::text, 2, '0')),
      case when v_kind = 'retailer' then '/retailer/' || new.org_id || '/wallet' else '/distributor/' || new.org_id || '/finance' end);
  end loop;
  return null;
end;
$$;
create trigger provider_events_notify after insert on public.provider_events for each row execute function app.tg_notify_provider_event();

create function app.tg_notify_ops()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid;
  v_org uuid;
  v_branch uuid;
  v_title text;
  v_link text;
begin
  if tg_table_name = 'stock_requests' then
    v_org := new.org_id; v_branch := (select branch_id from public.warehouses where id = new.warehouse_id);
    v_title := 'Agent stock request to approve'; v_link := '/distributor/' || v_org || '/push';
  elsif tg_table_name = 'review_items' then
    v_org := new.org_id; v_title := 'Offline sale needs review (' || replace(new.reason, '_', ' ') || ')'; v_link := '/distributor/' || v_org || '/push';
  elsif tg_table_name = 'variance_cases' then
    v_org := new.org_id; v_branch := (select w.branch_id from public.shipments s join public.warehouses w on w.id = s.warehouse_id where s.id = new.shipment_id);
    v_title := format('Variance: %s pieces need a decision', new.qty_pieces); v_link := '/distributor/' || v_org || '/push';
  elsif tg_table_name = 'join_requests' then
    v_org := new.org_id; v_title := 'New ' || replace(new.requested_role::text, '_', ' ') || ' request'; v_link := '/distributor/' || v_org || '/approvals';
  end if;
  for v_user in select app.org_users(v_org, array['distributor_admin', 'branch_manager']::public.member_role[], v_branch) loop
    perform app.notify(v_user, v_org, tg_table_name, v_title, null, v_link);
  end loop;
  return null;
end;
$$;
create trigger stock_requests_notify after insert on public.stock_requests for each row execute function app.tg_notify_ops();
create trigger review_items_notify after insert on public.review_items for each row execute function app.tg_notify_ops();
create trigger variance_cases_notify after insert on public.variance_cases for each row execute function app.tg_notify_ops();
create trigger join_requests_notify after insert on public.join_requests for each row execute function app.tg_notify_ops();

create function app.mark_notifications_read(p_ids uuid[] default null)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  v_n integer;
begin
  update public.notifications set read_at = now()
   where user_id = app.require_user() and read_at is null and (p_ids is null or id = any(p_ids));
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- Support tickets -----------------------------------------------------------------------------------------
create table public.tickets (
  id                 uuid primary key default gen_random_uuid(),
  opener_org_id      uuid not null references public.organisations (id),
  distributor_org_id uuid not null references public.organisations (id),
  opened_by          uuid not null references public.profiles (user_id),
  subject            text not null check (length(btrim(subject)) between 3 and 200),
  category           text not null check (category in ('delivery', 'payment', 'stock', 'account', 'other')),
  order_id           uuid references public.orders (id),
  dispute_id         uuid unique references public.order_disputes (id),
  status             text not null default 'open' check (status in ('open', 'resolved')),
  resolution         text,
  resolved_by        uuid references public.profiles (user_id),
  created_at         timestamptz not null default now(),
  resolved_at        timestamptz
);
create index tickets_distributor_status_idx on public.tickets (distributor_org_id, status);
create index tickets_opener_idx on public.tickets (opener_org_id);

create table public.ticket_messages (
  id         uuid primary key default gen_random_uuid(),
  ticket_id  uuid not null references public.tickets (id),
  author_id  uuid not null references public.profiles (user_id),
  body       text not null check (length(btrim(body)) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index ticket_messages_ticket_idx on public.ticket_messages (ticket_id, created_at);

create function app.can_handle_ticket(p_ticket public.tickets)
returns boolean language sql stable security definer set search_path = ''
as $$
  select app.has_role(p_ticket.distributor_org_id, array['distributor_admin', 'branch_manager']::public.member_role[])
$$;

create function app.open_ticket(p_opener_org_id uuid, p_distributor_id uuid, p_subject text, p_category text, p_body text, p_order_id uuid default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
  v_id  uuid;
  v_user uuid;
begin
  if not (p_opener_org_id = any(app.my_org_ids())) then
    raise exception using errcode = 'SOL03', message = 'you can only open tickets for your own organisation';
  end if;
  if p_opener_org_id <> p_distributor_id and not exists (
      select 1 from public.customer_relationships where distributor_org_id = p_distributor_id and retailer_org_id = p_opener_org_id) then
    raise exception using errcode = 'SOL05', message = 'that distributor does not serve you';
  end if;
  if p_order_id is not null and not exists (select 1 from public.orders where id = p_order_id and retailer_org_id = p_opener_org_id
                                                                         and distributor_org_id = p_distributor_id) then
    raise exception using errcode = 'SOL05', message = 'order not found for this shop and distributor';
  end if;
  insert into public.tickets (opener_org_id, distributor_org_id, opened_by, subject, category, order_id)
  values (p_opener_org_id, p_distributor_id, v_uid, btrim(p_subject), p_category, p_order_id) returning id into v_id;
  insert into public.ticket_messages (ticket_id, author_id, body) values (v_id, v_uid, p_body);
  for v_user in select app.org_users(p_distributor_id, array['distributor_admin', 'branch_manager']::public.member_role[]) loop
    perform app.notify(v_user, p_distributor_id, 'ticket', 'New support ticket: ' || btrim(p_subject), null, '/distributor/' || p_distributor_id || '/support');
  end loop;
  return v_id;
end;
$$;

create function app.post_ticket_message(p_ticket_id uuid, p_body text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
  v_t   public.tickets;
  v_id  uuid;
  v_user uuid;
begin
  select * into v_t from public.tickets where id = p_ticket_id;
  if not found then raise exception using errcode = 'SOL05', message = 'ticket not found'; end if;
  if not (v_t.opener_org_id = any(app.my_org_ids()) or app.can_handle_ticket(v_t)) then
    raise exception using errcode = 'SOL03', message = 'not your ticket';
  end if;
  if v_t.status <> 'open' then raise exception using errcode = 'SOL04', message = 'ticket is resolved'; end if;
  insert into public.ticket_messages (ticket_id, author_id, body) values (p_ticket_id, v_uid, p_body) returning id into v_id;
  if app.can_handle_ticket(v_t) then
    for v_user in select app.org_users(v_t.opener_org_id, array['retailer', 'distributor_admin']::public.member_role[]) loop
      perform app.notify(v_user, v_t.opener_org_id, 'ticket', 'Reply on: ' || v_t.subject, null, '/support');
    end loop;
  end if;
  return v_id;
end;
$$;

create function app.resolve_ticket(p_ticket_id uuid, p_resolution text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
  v_t   public.tickets;
  v_user uuid;
begin
  select * into v_t from public.tickets where id = p_ticket_id for update;
  if not found or v_t.status <> 'open' then raise exception using errcode = 'SOL04', message = 'ticket is not open'; end if;
  if not app.can_handle_ticket(v_t) then raise exception using errcode = 'SOL03', message = 'only the distributor resolves tickets'; end if;
  if nullif(btrim(p_resolution), '') is null then raise exception using errcode = 'SOL05', message = 'a resolution is required'; end if;
  update public.tickets set status = 'resolved', resolution = p_resolution, resolved_by = v_uid, resolved_at = now() where id = p_ticket_id;
  if v_t.dispute_id is not null then
    update public.order_disputes set status = 'resolved' where id = v_t.dispute_id;
  end if;
  for v_user in select app.org_users(v_t.opener_org_id, array['retailer', 'distributor_admin']::public.member_role[]) loop
    perform app.notify(v_user, v_t.opener_org_id, 'ticket', 'Resolved: ' || v_t.subject, p_resolution, '/support');
  end loop;
end;
$$;

-- A delivery dispute opens a ticket (the conversation and resolution happen there).
create function app.tg_dispute_ticket()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_order public.orders;
  v_id uuid;
  v_user uuid;
begin
  select * into strict v_order from public.orders where id = new.order_id;
  insert into public.tickets (opener_org_id, distributor_org_id, opened_by, subject, category, order_id, dispute_id)
  values (v_order.retailer_org_id, v_order.distributor_org_id, new.raised_by, 'Delivery dispute', 'delivery', new.order_id, new.id)
  returning id into v_id;
  insert into public.ticket_messages (ticket_id, author_id, body) values (v_id, new.raised_by, new.reason);
  for v_user in select app.org_users(v_order.distributor_org_id, array['distributor_admin', 'branch_manager']::public.member_role[]) loop
    perform app.notify(v_user, v_order.distributor_org_id, 'ticket', 'Delivery dispute raised', new.reason, '/distributor/' || v_order.distributor_org_id || '/support');
  end loop;
  return null;
end;
$$;
create trigger order_disputes_ticket after insert on public.order_disputes for each row execute function app.tg_dispute_ticket();

-- RLS, audit, grants
alter table public.notifications enable row level security;
alter table public.tickets enable row level security;
alter table public.ticket_messages enable row level security;

create policy notifications_select on public.notifications for select to authenticated using (user_id = (select app.current_user_id()));
create policy tickets_select on public.tickets for select to authenticated using (
  (select app.is_platform_admin())
  or opener_org_id = any((select app.my_org_ids())::uuid[])
  or distributor_org_id = any((select app.my_org_ids_with_role(array['distributor_admin', 'branch_manager']::public.member_role[]))::uuid[]));
create policy ticket_messages_select on public.ticket_messages for select to authenticated using (
  ticket_id in (select t.id from public.tickets t));

select audit.attach(t::regclass) from unnest(array['public.tickets', 'public.ticket_messages']) t;   -- notifications are derived

revoke all on public.notifications, public.tickets, public.ticket_messages, public.v_sales_daily, public.v_sku_performance,
  public.v_agent_leaderboard, public.v_inventory_value from anon, authenticated;
grant select on public.notifications, public.tickets, public.ticket_messages, public.v_sales_daily, public.v_sku_performance,
  public.v_agent_leaderboard, public.v_inventory_value to authenticated;

revoke all on function app.manufacturer_summary(uuid), app.notify(uuid, uuid, text, text, text, text),
  app.org_users(uuid, public.member_role[], uuid), app.mark_notifications_read(uuid[]), app.can_handle_ticket(public.tickets),
  app.open_ticket(uuid, uuid, text, text, text, uuid), app.post_ticket_message(uuid, text), app.resolve_ticket(uuid, text)
from public, anon, authenticated;
grant execute on function app.manufacturer_summary(uuid), app.mark_notifications_read(uuid[]),
  app.open_ticket(uuid, uuid, text, text, text, uuid), app.post_ticket_message(uuid, text), app.resolve_ticket(uuid, text),
  app.round_div(bigint, bigint, text)   -- pure arithmetic, used by reporting views
to authenticated;

revoke all on function app.tg_notify_order_status(), app.tg_notify_provider_event(), app.tg_notify_ops(), app.tg_dispute_ticket()
from public, anon, authenticated;
