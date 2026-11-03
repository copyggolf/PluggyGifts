-- Five private, versioned coupon slots; a completed round receives one stable assignment.
begin;
create table if not exists public.pluggy_coupon_settings(id boolean primary key default true check(id),enabled boolean not null default false,distribution text not null default 'random' check(distribution in ('random','round_robin','fixed')),fixed_slot integer not null default 1 check(fixed_slot between 1 and 5),cursor integer not null default 0,revision bigint not null default 0);
create table if not exists public.pluggy_coupon_assets(id text primary key,image text not null);
create table if not exists public.pluggy_coupon_versions(id uuid primary key default gen_random_uuid(),slot integer not null check(slot between 1 and 5),body jsonb not null,image_id text references public.pluggy_coupon_assets(id),created_at timestamptz not null default now());
create table if not exists public.pluggy_coupon_slots(slot integer primary key check(slot between 1 and 5),version_id uuid not null references public.pluggy_coupon_versions(id));
create table if not exists public.pluggy_coupon_claims(run_id uuid primary key references public.pluggy_results(id),visit_id uuid not null references public.pluggy_visits(id),version_id uuid not null references public.pluggy_coupon_versions(id),created_at timestamptz not null default now());
create index if not exists pluggy_coupon_claim_visit on public.pluggy_coupon_claims(visit_id,created_at desc);
alter table public.pluggy_coupon_settings enable row level security;alter table public.pluggy_coupon_assets enable row level security;alter table public.pluggy_coupon_versions enable row level security;alter table public.pluggy_coupon_slots enable row level security;alter table public.pluggy_coupon_claims enable row level security;
revoke all on public.pluggy_coupon_settings,public.pluggy_coupon_assets,public.pluggy_coupon_versions,public.pluggy_coupon_slots,public.pluggy_coupon_claims from public,anon,authenticated;
-- Preserve the owner's current coupon in slot 1. Run once, never reset saved pool settings.
do $$declare old public.pluggy_coupon; k text; v uuid;
begin
 if not exists(select 1 from public.pluggy_coupon_settings) then
  select * into old from public.pluggy_coupon where id=1;
  insert into public.pluggy_coupon_settings(id,enabled) values(true,coalesce(old.enabled,false));
  for n in 1..5 loop
   k=null;if n=1 and old.image<>'' then k=md5(old.image);insert into public.pluggy_coupon_assets(id,image) values(k,old.image) on conflict do nothing;end if;
   insert into public.pluggy_coupon_versions(slot,body,image_id) values(n,case when n=1 then jsonb_build_object('enabled',old.enabled,'title',old.title,'code',old.code,'terms',old.terms,'shop_url',old.shop_url,'starts_at',old.starts_at,'ends_at',old.ends_at) else jsonb_build_object('enabled',false,'title','คูปอง '||n,'code','','terms','','shop_url','https://www.powerbuy.co.th/','starts_at',null,'ends_at',null) end,k) returning id into v;
   insert into public.pluggy_coupon_slots(slot,version_id) values(n,v);
  end loop;
 end if;
end;$$;
create or replace function public.pluggy_coupon_pool_owner() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.pluggy_admins where user_id=auth.uid()) then raise exception 'Owner access required';end if;
 return (select to_jsonb(s)||jsonb_build_object('coupons',(select jsonb_agg(v.body||jsonb_build_object('slot',c.slot,'image',coalesce(a.image,'')) order by c.slot) from public.pluggy_coupon_slots c join public.pluggy_coupon_versions v on v.id=c.version_id left join public.pluggy_coupon_assets a on a.id=v.image_id)) from public.pluggy_coupon_settings s where id);
end;$$;
create or replace function public.pluggy_coupon_pool_save(p_enabled boolean,p_distribution text,p_fixed_slot integer,p_coupons jsonb,p_expected bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.pluggy_coupon_settings;c jsonb;b jsonb;n integer;im text;k text;v uuid;st timestamptz;en timestamptz;
begin
 if not exists(select 1 from public.pluggy_admins where user_id=auth.uid()) then raise exception 'Owner access required';end if;
 select * into s from public.pluggy_coupon_settings where id for update;
 if p_expected is distinct from s.revision then raise exception 'Coupon settings changed; reload first';end if;
 if p_enabled is null or p_distribution is null or p_distribution not in ('random','round_robin','fixed') or p_fixed_slot is null or p_fixed_slot not between 1 and 5 or jsonb_typeof(p_coupons) is distinct from 'array' or jsonb_array_length(p_coupons)<>5 then raise exception 'Invalid coupon settings';end if;
 if (select count(distinct x->>'slot') from jsonb_array_elements(p_coupons)x)<>5 then raise exception 'Invalid coupon slots';end if;
 for c in select * from jsonb_array_elements(p_coupons) loop
  if jsonb_typeof(c->'slot') is distinct from 'number' or (c->>'slot')!~'^[1-5]$' or jsonb_typeof(c->'enabled') is distinct from 'boolean' then raise exception 'Invalid coupon slot';end if;n=(c->>'slot')::integer;
  for k in select unnest(array['title','code','image','terms','shop_url']) loop if jsonb_typeof(c->k) is distinct from 'string' then raise exception 'Invalid coupon field';end if;end loop;
  im=c->>'image';
  if length(trim(c->>'title')) not between 1 and 120 or length(c->>'code')>80 or length(c->>'terms')>2000 or length(im)>900000 or length(c->>'shop_url')>1000 or (c->>'shop_url')!~'^https://([a-zA-Z0-9-]+\.)*powerbuy\.co\.th(/[^[:space:]]*)?$' then raise exception 'Invalid coupon %',n;end if;
  if im<>'' and im!~'^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$' then raise exception 'Invalid coupon image';end if;
  st=nullif(c->>'starts_at','')::timestamptz;en=nullif(c->>'ends_at','')::timestamptz;
  if st is not null and en is not null and en<=st then raise exception 'Invalid coupon dates';end if;
  if (c->>'enabled')::boolean and trim(c->>'code')='' and im='' then raise exception 'Coupon % needs code or image',n;end if;
  k=null;if im<>'' then k=md5(im);insert into public.pluggy_coupon_assets(id,image) values(k,im) on conflict do nothing;end if;
  b=jsonb_build_object('enabled',(c->>'enabled')::boolean,'title',trim(c->>'title'),'code',trim(c->>'code'),'terms',c->>'terms','shop_url',c->>'shop_url','starts_at',st,'ends_at',en);
  select ver.id into v from public.pluggy_coupon_slots sl join public.pluggy_coupon_versions ver on ver.id=sl.version_id where sl.slot=n and ver.body=b and ver.image_id is not distinct from k;
  if v is null then insert into public.pluggy_coupon_versions(slot,body,image_id) values(n,b,k) returning id into v;update public.pluggy_coupon_slots set version_id=v where slot=n;end if;
 end loop;
 if p_enabled and not exists(select 1 from public.pluggy_coupon_slots sl join public.pluggy_coupon_versions v on v.id=sl.version_id where (v.body->>'enabled')::boolean) then raise exception 'Enable at least one coupon';end if;
 if p_enabled and p_distribution='fixed' and not exists(select 1 from public.pluggy_coupon_slots sl join public.pluggy_coupon_versions v on v.id=sl.version_id where sl.slot=p_fixed_slot and (v.body->>'enabled')::boolean) then raise exception 'Fixed coupon must be enabled';end if;
 update public.pluggy_coupon_settings set enabled=p_enabled,distribution=p_distribution,fixed_slot=p_fixed_slot,revision=revision+1 where id;
 return public.pluggy_coupon_pool_owner();
end;$$;
create or replace function public.pluggy_coupon_claim(p_run uuid,p_visit uuid,p_secret uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.pluggy_coupon_settings;v public.pluggy_coupon_versions;r public.pluggy_runs;me uuid;last_mine integer;last_global integer;choices integer[];selected integer;
begin
 select visitor_id into me from public.pluggy_visits where id=p_visit and secret=p_secret;if me is null then raise exception 'Invalid visit';end if;
 select * into r from public.pluggy_runs where id=p_run and visit_id=p_visit;
 if r.id is null then return jsonb_build_object('pending',true);end if;
 if not exists(select 1 from public.pluggy_results where id=p_run and visit_id=p_visit) then return jsonb_build_object('pending',true);end if;
 if r.completed_at is null or r.completed_at<r.started_at+make_interval(secs=>case when r.game='shuffle' then 12 else 24 end) then return null;end if;
 -- Lock settings serializes rotation and prevents double assignment during simultaneous retries.
 select * into s from public.pluggy_coupon_settings where id for update;if not s.enabled then return null;end if;
 select ver.* into v from public.pluggy_coupon_claims c join public.pluggy_coupon_versions ver on ver.id=c.version_id where c.run_id=p_run and c.visit_id=p_visit;
 if v.id is not null then
  if (v.body->>'ends_at') is not null and (v.body->>'ends_at')::timestamptz<=now() then return null;end if;
  return (v.body-'enabled'-'starts_at')||jsonb_build_object('slot',v.slot,'image',coalesce((select image from public.pluggy_coupon_assets where id=v.image_id),''));
 end if;
 if r.completed_at<now()-interval '24 hours' then return null;end if;
 select array_agg(sl.slot order by sl.slot) into choices from public.pluggy_coupon_slots sl join public.pluggy_coupon_versions ver on ver.id=sl.version_id where (ver.body->>'enabled')::boolean and ((ver.body->>'starts_at') is null or (ver.body->>'starts_at')::timestamptz<=now()) and ((ver.body->>'ends_at') is null or (ver.body->>'ends_at')::timestamptz>now());
 if choices is null then return null;end if;
 select ver.slot into last_mine from public.pluggy_coupon_claims c join public.pluggy_visits vi on vi.id=c.visit_id join public.pluggy_coupon_versions ver on ver.id=c.version_id where vi.visitor_id=me order by c.created_at desc,c.run_id desc limit 1;
 if s.distribution='fixed' then if not s.fixed_slot=any(choices) then return null;end if;selected=s.fixed_slot;
 else
  if array_length(choices,1)>1 and last_mine=any(choices) then choices=array_remove(choices,last_mine);end if;
  if s.distribution='round_robin' then select x into selected from unnest(choices)x where x>s.cursor order by x limit 1;if selected is null then selected=choices[1];end if;
  else
   if array_length(choices,1)>1 and s.cursor=any(choices) then choices=array_remove(choices,s.cursor);end if;
   selected=choices[1+floor(random()*array_length(choices,1))::integer];
  end if;
 end if;
 select ver.* into v from public.pluggy_coupon_slots sl join public.pluggy_coupon_versions ver on ver.id=sl.version_id where sl.slot=selected;
 insert into public.pluggy_coupon_claims(run_id,visit_id,version_id) values(p_run,p_visit,v.id);
 update public.pluggy_coupon_settings set cursor=selected where id;
 return (v.body-'enabled'-'starts_at')||jsonb_build_object('slot',v.slot,'image',coalesce((select image from public.pluggy_coupon_assets where id=v.image_id),''));
end;$$;
-- Retire anonymous coupon lookup. Only the round holder receives its assigned coupon.
create or replace function public.pluggy_coupon_public() returns jsonb language sql stable security definer set search_path='' as $$ select null::jsonb $$;
create or replace function public.pluggy_coupon_save(p_enabled boolean,p_title text,p_code text,p_image text,p_terms text,p_shop_url text,p_starts_at timestamptz default null,p_ends_at timestamptz default null) returns jsonb language plpgsql security definer set search_path='' as $$begin raise exception 'Please refresh coupon settings';end;$$;
revoke all on function public.pluggy_coupon_pool_owner(),public.pluggy_coupon_pool_save(boolean,text,integer,jsonb,bigint),public.pluggy_coupon_claim(uuid,uuid,uuid) from public;
grant execute on function public.pluggy_coupon_pool_owner(),public.pluggy_coupon_pool_save(boolean,text,integer,jsonb,bigint) to authenticated;
grant execute on function public.pluggy_coupon_claim(uuid,uuid,uuid) to anon;
commit;
