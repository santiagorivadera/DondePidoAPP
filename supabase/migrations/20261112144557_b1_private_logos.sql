insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('dondepido-business-logos', 'dondepido-business-logos', false, 262144,
  array['image/png', 'image/jpeg', 'image/webp']);

create policy dondepido_logos_insert_own on storage.objects for insert to authenticated
with check (
  bucket_id = 'dondepido-business-logos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and array_length(storage.foldername(name), 1) = 1
  and storage.filename(name) ~ '^[0-9a-f-]{36}\.(png|jpg|webp)$'
);

create policy dondepido_logos_read_own on storage.objects for select to authenticated
using (
  bucket_id = 'dondepido-business-logos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
