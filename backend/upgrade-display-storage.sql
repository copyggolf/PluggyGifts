-- Website artwork is public. Only the existing owner allowlist can upload new files.
begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('pluggy-display','pluggy-display',true,1500000,array['image/webp','image/png','image/jpeg']) on conflict(id) do nothing;
create or replace function public.pluggy_is_owner() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.pluggy_admins where user_id=auth.uid())$$;
revoke all on function public.pluggy_is_owner() from public;grant execute on function public.pluggy_is_owner() to authenticated;
drop policy if exists pluggy_display_owner_insert on storage.objects;
create policy pluggy_display_owner_insert on storage.objects for insert to authenticated with check(bucket_id='pluggy-display' and public.pluggy_is_owner());
drop policy if exists pluggy_display_owner_select on storage.objects;
create policy pluggy_display_owner_select on storage.objects for select to authenticated using(bucket_id='pluggy-display' and public.pluggy_is_owner());
commit;
