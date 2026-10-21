-- e-POD photo evidence (private bucket). Layout: epod/<shipment_id>/<order_id>/<file>.
-- Only the carrier of an OPEN shipment may upload into it; anyone who can see the order may read.
-- No update/delete policies: evidence is append-only. NDPA: photograph goods, not faces.
-- Portability: this is the one Supabase-Storage-specific object besides app.record_delivery's existence check.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('epod', 'epod', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy epod_insert_by_carrier on storage.objects for insert to authenticated with check (
  bucket_id = 'epod'
  and (storage.foldername(name))[1] in (
    select s.id::text from public.shipments s
    join public.stock_locations sl on sl.id = s.carrier_location_id
    where sl.user_id = (select app.current_user_id()) and s.status = 'open'
  )
  and (storage.foldername(name))[2] in (
    select a.order_id::text from public.order_allocations a
    join public.shipments s on s.batch_id = a.batch_id
    where s.id::text = (storage.foldername(name))[1]
  )
);

create policy epod_read_if_order_visible on storage.objects for select to authenticated using (
  bucket_id = 'epod'
  and (storage.foldername(name))[2] in (select o.id::text from public.orders o)
);
