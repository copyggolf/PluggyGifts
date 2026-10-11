-- Run once in the Supabase SQL editor. No user data is publicly readable.
begin;
create table if not exists public.pluggy_admins (user_id uuid primary key references auth.users(id) on delete cascade);
create table if not exists public.pluggy_visits (
 id uuid primary key, secret uuid not null, visitor_id uuid not null,
 nickname text not null default '', device text not null check(device in ('mobile','desktop')),
 first_seen timestamptz not null default now(), last_seen timestamptz not null default now(),
 game text check(game in ('catch','buster','shuffle')), playing boolean not null default false, ever_played boolean not null default false, visible boolean not null default true
);
create table if not exists public.pluggy_results (
 id uuid primary key, visit_id uuid not null references public.pluggy_visits(id),
 nickname text not null, game text not null check(game in ('catch','buster','shuffle')),
 score integer not null, rounds jsonb not null, created_at timestamptz not null default now()
);
create index if not exists pluggy_visit_online on public.pluggy_visits(last_seen);
create index if not exists pluggy_visit_visitor on public.pluggy_visits(visitor_id);
create index if not exists pluggy_result_date on public.pluggy_results(created_at desc);
alter table public.pluggy_admins enable row level security;
alter table public.pluggy_visits enable row level security;
alter table public.pluggy_results enable row level security;
revoke all on public.pluggy_admins,public.pluggy_visits,public.pluggy_results from anon,authenticated;

create or replace function public.pluggy_touch(p_visit uuid,p_secret uuid,p_visitor uuid,p_name text,p_game text,p_playing boolean,p_visible boolean,p_device text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if p_visit is null or p_secret is null or p_visitor is null or length(p_name)>30 or p_name is null or p_device not in ('mobile','desktop') or (p_game is not null and p_game not in ('catch','buster','shuffle')) then raise exception 'Invalid visit'; end if;
 insert into public.pluggy_visits(id,secret,visitor_id,nickname,device,game,playing,ever_played,visible)
 values(p_visit,p_secret,p_visitor,p_name,p_device,p_game,p_playing,p_game is not null,p_visible)
 on conflict(id) do update set nickname=excluded.nickname,game=excluded.game,playing=excluded.playing,ever_played=pluggy_visits.ever_played or excluded.ever_played,visible=excluded.visible,last_seen=now()
 where pluggy_visits.secret=p_secret and pluggy_visits.visitor_id=p_visitor;
end;$$;
create or replace function public.pluggy_result(p_run uuid,p_visit uuid,p_secret uuid,p_name text,p_game text,p_score integer,p_rounds jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare expected integer; sum_score integer;
begin
 if not exists(select 1 from public.pluggy_visits where id=p_visit and secret=p_secret) then raise exception 'Invalid visit'; end if;
 if p_run is null or p_name is null or length(trim(p_name)) not between 1 and 30 or p_game not in ('catch','buster','shuffle') or p_score not between -100000 and 100000 or jsonb_typeof(p_rounds) is distinct from 'array' then raise exception 'Invalid result'; end if;
 expected=case when p_game='shuffle' then 5 else 3 end;
 if jsonb_array_length(p_rounds)<>expected then raise exception 'Incomplete game'; end if;
 select sum(value::integer) into sum_score from jsonb_array_elements_text(p_rounds);
 if sum_score<>p_score then raise exception 'Score mismatch'; end if;
 insert into public.pluggy_results(id,visit_id,nickname,game,score,rounds) values(p_run,p_visit,p_name,p_game,p_score,p_rounds) on conflict(id) do nothing;
end;$$;
create or replace function public.pluggy_dashboard(p_page integer default 0,p_game text default null,p_name text default '',p_from timestamptz default null,p_to timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare report jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.pluggy_admins where user_id=auth.uid()) then raise exception 'Owner access required' using errcode='42501'; end if;
 if p_page<0 or p_page>100000 then raise exception 'Invalid page'; end if;
 with filtered as (select * from public.pluggy_results where (p_game is null or game=p_game) and nickname ilike '%'||left(p_name,30)||'%' and (p_from is null or created_at>=p_from) and (p_to is null or created_at<p_to)),
 page as (select * from filtered order by created_at desc,id desc limit 50 offset p_page*50)
 select jsonb_build_object(
 'online',(select count(distinct visitor_id) from public.pluggy_visits where last_seen>now()-interval '75 seconds' and visible),
 'playing',(select count(distinct visitor_id) from public.pluggy_visits where last_seen>now()-interval '75 seconds' and visible and playing),
 'visitors',(select count(distinct visitor_id) from public.pluggy_visits),
 'players',(select count(distinct v.visitor_id) from public.pluggy_visits v where v.ever_played),
 'visits',(select count(*) from public.pluggy_visits),
 'completed',(select count(*) from public.pluggy_results),
 'filtered', (select count(*) from filtered),
 'results',coalesce((select jsonb_agg(to_jsonb(page)-'visit_id') from page),'[]'::jsonb),
 'active',coalesce((select jsonb_agg(a) from (select nickname,game,playing,device,last_seen from public.pluggy_visits where last_seen>now()-interval '75 seconds' and visible order by last_seen desc limit 100) a),'[]'::jsonb),
 'byGame',coalesce((select jsonb_agg(b) from (select game,count(*) as games,round(avg(score),1) as average,max(score) as best from public.pluggy_results group by game) b),'[]'::jsonb),
 'updatedAt',now()) into report;
 return report;
end;$$;
revoke all on function public.pluggy_touch(uuid,uuid,uuid,text,text,boolean,boolean,text) from public;
revoke all on function public.pluggy_result(uuid,uuid,uuid,text,text,integer,jsonb) from public;
revoke all on function public.pluggy_dashboard(integer,text,text,timestamptz,timestamptz) from public;
grant execute on function public.pluggy_touch(uuid,uuid,uuid,text,text,boolean,boolean,text) to anon;
grant execute on function public.pluggy_result(uuid,uuid,uuid,text,text,integer,jsonb) to anon;
grant execute on function public.pluggy_dashboard(integer,text,text,timestamptz,timestamptz) to authenticated;
commit;
-- After creating your owner user in Authentication > Users, run separately:
-- insert into public.pluggy_admins(user_id) values ('OWNER_USER_UUID');
