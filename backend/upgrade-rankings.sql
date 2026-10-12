-- Additive upgrade: keep existing visits, results and owner accounts.
begin;
create table if not exists public.pluggy_games (
 id text primary key, name text not null, rounds integer not null check(rounds between 1 and 20),
 score_target integer not null check(score_target>0), round_min jsonb not null, round_max jsonb not null,
 min_seconds integer not null default 0, enabled boolean not null default true,
 rank_from timestamptz not null default now(), rank_to timestamptz, round_values jsonb
);
insert into public.pluggy_games(id,name,rounds,score_target,round_min,round_max,min_seconds)
values ('catch','Pluggy Catch',3,1240,'[-420,-440,-460]','[340,480,420]',85),
('buster','Pluggy Buster',3,7250,'[-880,-960,-1060]','[2200,2400,2650]',85),
('shuffle','Pluggy Mystery Shuffle',5,250,'[-20,-20,-20,-20,-20]','[50,50,50,50,50]',30)
on conflict(id) do nothing;
update public.pluggy_games set round_values='[-20,50]' where id='shuffle';
alter table public.pluggy_games enable row level security;
revoke all on public.pluggy_games from anon,authenticated;
alter table public.pluggy_visits drop constraint if exists pluggy_visits_game_check;
alter table public.pluggy_results drop constraint if exists pluggy_results_game_check;
alter table public.pluggy_visits drop constraint if exists pluggy_visits_device_check;
alter table public.pluggy_visits add constraint pluggy_visits_device_check check(device in ('mobile','tablet','desktop'));
alter table public.pluggy_visits add column if not exists meta jsonb not null default '{}';
alter table public.pluggy_visits add column if not exists active_seconds integer not null default 0;
alter table public.pluggy_visits add column if not exists play_seconds integer not null default 0;
alter table public.pluggy_results add column if not exists rank_public boolean not null default false;
alter table public.pluggy_results add column if not exists normalized integer;
alter table public.pluggy_results add column if not exists rank_version integer not null default 1;
create table if not exists public.pluggy_runs (
 id uuid primary key, visit_id uuid not null references public.pluggy_visits(id), game text not null references public.pluggy_games(id),
 started_at timestamptz not null default now(), completed_at timestamptz
);
create table if not exists public.pluggy_events (
 id uuid primary key, visit_id uuid not null references public.pluggy_visits(id),
 kind text not null check(kind in ('score_preview','score_download','score_share','shop_click')),
 created_at timestamptz not null default now()
);
alter table public.pluggy_runs enable row level security;
alter table public.pluggy_events enable row level security;
revoke all on public.pluggy_runs,public.pluggy_events from anon,authenticated;
create index if not exists pluggy_run_visit on public.pluggy_runs(visit_id);
create index if not exists pluggy_run_date on public.pluggy_runs(started_at);
create index if not exists pluggy_event_visit on public.pluggy_events(visit_id);
create index if not exists pluggy_rank_date on public.pluggy_results(created_at,game) where rank_public;

create or replace function public.pluggy_touch_v2(p_visit uuid,p_secret uuid,p_visitor uuid,p_name text,p_game text,p_playing boolean,p_visible boolean,p_device text,p_meta jsonb,p_active integer,p_play integer)
returns void language plpgsql security definer set search_path='' as $$
declare cleaned jsonb;
begin
 if p_visit is null or p_secret is null or p_visitor is null or p_name is null or length(p_name)>30 or p_device not in ('mobile','tablet','desktop') or p_active not between 0 and 86400 or p_play not between 0 and p_active or jsonb_typeof(p_meta) is distinct from 'object' or (p_game is not null and not exists(select 1 from public.pluggy_games where id=p_game and enabled)) then raise exception 'Invalid visit';end if;
 select coalesce(jsonb_object_agg(key,left(value,100)),'{}') into cleaned from jsonb_each_text(p_meta) where key in ('os','browser','language','timezone','viewport','source','medium','campaign','referrer','province');
 insert into public.pluggy_visits(id,secret,visitor_id,nickname,device,game,playing,visible,ever_played,meta,active_seconds,play_seconds)
 values(p_visit,p_secret,p_visitor,p_name,p_device,p_game,p_playing,p_visible,p_game is not null,cleaned,p_active,p_play)
 on conflict(id) do update set nickname=excluded.nickname,device=excluded.device,game=excluded.game,playing=excluded.playing,visible=excluded.visible,last_seen=now(),ever_played=pluggy_visits.ever_played or excluded.ever_played,meta=excluded.meta,
 active_seconds=greatest(pluggy_visits.active_seconds,least(excluded.active_seconds,pluggy_visits.active_seconds+greatest(0,extract(epoch from now()-pluggy_visits.last_seen)::integer)+5)),
 play_seconds=greatest(pluggy_visits.play_seconds,least(excluded.play_seconds,pluggy_visits.play_seconds+greatest(0,extract(epoch from now()-pluggy_visits.last_seen)::integer)+5))
 where pluggy_visits.secret=p_secret and pluggy_visits.visitor_id=p_visitor;
end;$$;

create or replace function public.pluggy_start_v2(p_run uuid,p_visit uuid,p_secret uuid,p_game text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.pluggy_visits where id=p_visit and secret=p_secret) or not exists(select 1 from public.pluggy_games where id=p_game and enabled) then raise exception 'Invalid run';end if;
 if (select count(*) from public.pluggy_runs where visit_id=p_visit and started_at>now()-interval '1 minute')>=30 then raise exception 'Too many starts';end if;
 insert into public.pluggy_runs(id,visit_id,game) values(p_run,p_visit,p_game) on conflict(id) do nothing;
end;$$;
create or replace function public.pluggy_result_v2(p_run uuid,p_visit uuid,p_secret uuid,p_name text,p_game text,p_score integer,p_rounds jsonb,p_public boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare g public.pluggy_games; total integer; n integer; r public.pluggy_runs;
begin
 if not exists(select 1 from public.pluggy_visits where id=p_visit and secret=p_secret) then raise exception 'Invalid visit';end if;
 if exists(select 1 from public.pluggy_results where id=p_run and visit_id=p_visit) then return (select jsonb_build_object('ranked',rank_public,'points',normalized) from public.pluggy_results where id=p_run and visit_id=p_visit);end if;
 select * into g from public.pluggy_games where id=p_game and enabled;
 select * into r from public.pluggy_runs where id=p_run and visit_id=p_visit and game=p_game;
 if g.id is null or r.id is null or p_name is null or length(trim(p_name)) not between 1 and 30 or jsonb_typeof(p_rounds) is distinct from 'array' or jsonb_array_length(p_rounds)<>g.rounds or p_score is null then raise exception 'Invalid result';end if;
 total=0;
 for i in 0..g.rounds-1 loop
  if jsonb_typeof(p_rounds->i) is distinct from 'number' or (p_rounds->>i)!~'^-?[0-9]+$' then raise exception 'Invalid round';end if;
  n=(p_rounds->>i)::integer;
  if n<(g.round_min->>i)::integer or n>(g.round_max->>i)::integer then raise exception 'Score outside game limits';end if;
  if g.round_values is not null and not g.round_values @> jsonb_build_array(n) then raise exception 'Invalid round score';end if;
  total=total+n;
 end loop;
 if total<>p_score then raise exception 'Score mismatch';end if;
 if now()<r.started_at+make_interval(secs=>g.min_seconds) then p_public=false;end if;
 insert into public.pluggy_results(id,visit_id,nickname,game,score,rounds,rank_public,normalized)
 values(p_run,p_visit,trim(p_name),p_game,p_score,p_rounds,coalesce(p_public,false),round(1000.0*greatest(0,least(p_score,g.score_target))/g.score_target));
 update public.pluggy_runs set completed_at=now() where id=p_run;
 return jsonb_build_object('ranked',coalesce(p_public,false),'points',round(1000.0*greatest(0,least(p_score,g.score_target))/g.score_target));
end;$$;
create or replace function public.pluggy_event_v2(p_event uuid,p_visit uuid,p_secret uuid,p_kind text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.pluggy_visits where id=p_visit and secret=p_secret) or p_kind not in ('score_preview','score_download','score_share','shop_click') then raise exception 'Invalid event';end if;
 if (select count(*) from public.pluggy_events where visit_id=p_visit and created_at>now()-interval '1 minute')>=60 then raise exception 'Too many events';end if;
 insert into public.pluggy_events(id,visit_id,kind) values(p_event,p_visit,p_kind) on conflict(id) do nothing;
end;$$;

-- Only opt-in nicknames and scores are public. IDs, secrets and telemetry never leave this RPC.
create or replace function public.pluggy_leaderboard(p_day date default null,p_game text default null,p_visit uuid default null,p_secret uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d date=coalesce(p_day,(now() at time zone 'Asia/Bangkok')::date); lo timestamptz; hi timestamptz; me uuid; result jsonb; required integer;
begin
 if d<(now() at time zone 'Asia/Bangkok')::date-365 or d>(now() at time zone 'Asia/Bangkok')::date then raise exception 'Invalid day';end if;
 lo=d::timestamp at time zone 'Asia/Bangkok'; hi=lo+interval '1 day';
 select visitor_id into me from public.pluggy_visits where id=p_visit and secret=p_secret;
 select count(*) into required from public.pluggy_games where rank_from<hi and (rank_to is null or rank_to>=hi);
 with best as (
 select distinct on(v.visitor_id,r.game) v.visitor_id,r.game,r.nickname,r.score,r.normalized,r.created_at
 from public.pluggy_results r join public.pluggy_visits v on v.id=r.visit_id join public.pluggy_games g on g.id=r.game
 where r.created_at>=lo and r.created_at<hi and r.rank_public and r.normalized is not null and g.rank_from<hi and (g.rank_to is null or g.rank_to>=hi)
 order by v.visitor_id,r.game,r.score desc,r.created_at asc,r.id
 ), best_all as (
 select distinct on(v.visitor_id,r.game) v.visitor_id,r.game,r.nickname,r.score,r.normalized,r.created_at
 from public.pluggy_results r join public.pluggy_visits v on v.id=r.visit_id join public.pluggy_games g on g.id=r.game
 where r.rank_public and r.normalized is not null and g.rank_from<hi and (g.rank_to is null or g.rank_to>=hi)
 order by v.visitor_id,r.game,r.score desc,r.created_at asc,r.id
 ), all_totals as (
 select visitor_id,(array_agg(nickname order by created_at desc))[1] as nickname,round(avg(normalized))::integer as points,count(*) as games_done,max(created_at) as achieved_at from best_all group by visitor_id having count(*)=required and required>0
 ), candidates as (
 select visitor_id,(array_agg(nickname order by created_at desc))[1] as nickname,
 case when p_game is null then round(avg(normalized))::integer else max(normalized) end as points,
 case when p_game is null then null else max(score) end as raw_score,
 count(*) as games_done,max(created_at) as achieved_at,
 jsonb_agg(jsonb_build_object('game',game,'score',score,'points',normalized) order by game) as breakdown
 from best where p_game is null or game=p_game group by visitor_id
 ), eligible as (
 select *,dense_rank() over(order by points desc,case when p_game is not null then raw_score end desc) as position
 from candidates where p_game is not null or (games_done=required and required>0)
 )
 select jsonb_build_object('day',d,'game',p_game,'requiredGames',required,'participants',(select count(*) from eligible),
 'top',coalesce((select jsonb_agg(t) from (select position,nickname,points,raw_score,games_done,breakdown from eligible order by position,achieved_at,visitor_id limit 10) t),'[]'::jsonb),
 'mine',(select jsonb_build_object('position',e.position,'nickname',c.nickname,'points',c.points,'raw_score',c.raw_score,'games_done',c.games_done,'breakdown',c.breakdown) from candidates c left join eligible e using(visitor_id) where c.visitor_id=me),
 'games',(select jsonb_agg(jsonb_build_object('id',id,'name',name,'rounds',rounds,'target',score_target,'enabled',enabled) order by rank_from,id) from public.pluggy_games where rank_from<hi and (rank_to is null or rank_to>=hi)),
 'records',coalesce((select jsonb_agg(x) from (select distinct on(game) game,nickname,score,normalized as points from best_all order by game,score desc,created_at asc) x),'[]'::jsonb),
 'overallRecord',(select jsonb_build_object('nickname',nickname,'points',points,'games_done',games_done) from all_totals order by points desc,achieved_at asc,visitor_id limit 1),
 'updatedAt',now()) into result;
 return result;
end;$$;

create or replace function public.pluggy_dashboard_v2(p_page integer default 0,p_game text default null,p_name text default '',p_from timestamptz default null,p_to timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare base jsonb; extra jsonb;
begin
 base=public.pluggy_dashboard(p_page,p_game,p_name,p_from,p_to);
 with visits as (select * from public.pluggy_visits v where (p_from is null or first_seen>=p_from) and (p_to is null or first_seen<p_to)),
 runs as (select * from public.pluggy_runs where (p_from is null or started_at>=p_from) and (p_to is null or started_at<p_to) and (p_game is null or game=p_game)),
 events as (select * from public.pluggy_events where (p_from is null or created_at>=p_from) and (p_to is null or created_at<p_to)),
 segments as (select 'device' as kind,device as label from visits union all select 'os',coalesce(nullif(meta->>'os',''),'ไม่ทราบ') from visits union all select 'browser',coalesce(nullif(meta->>'browser',''),'ไม่ทราบ') from visits union all select 'source',coalesce(nullif(meta->>'source',''),'เข้าตรง / ไม่ทราบ') from visits union all select 'campaign',coalesce(nullif(meta->>'campaign',''),'ไม่ระบุ') from visits union all select 'province',coalesce(nullif(meta->>'province',''),'ไม่ระบุ') from visits),
 grouped as (select kind,label,count(*) as visits from segments group by kind,label)
 select jsonb_build_object(
 'engagement',jsonb_build_object('activeMinutes',round((select coalesce(sum(active_seconds),0) from visits)/60.0,1),'playMinutes',round((select coalesce(sum(play_seconds),0) from visits)/60.0,1),'avgActiveMinutes',round((select coalesce(avg(active_seconds) filter(where meta<>'{}'::jsonb),0) from visits)/60.0,1),'starts',(select count(*) from runs),'finishes',(select count(*) from runs where completed_at is not null),'returning',(select count(distinct v.visitor_id) from visits v where exists(select 1 from public.pluggy_visits old where old.visitor_id=v.visitor_id and old.first_seen<v.first_seen and (old.first_seen at time zone 'Asia/Bangkok')::date<(v.first_seen at time zone 'Asia/Bangkok')::date))),
 'segments',coalesce((select jsonb_agg(x) from (select * from grouped order by kind,visits desc limit 150) x),'[]'::jsonb),
 'events',coalesce((select jsonb_agg(x) from (select kind,count(*) as count from events group by kind) x),'[]'::jsonb),
 'daily',coalesce((select jsonb_agg(x) from (select (first_seen at time zone 'Asia/Bangkok')::date as day,count(*) as visits,count(distinct visitor_id) as visitors from visits group by day order by day desc limit 30) x),'[]'::jsonb),
 'hours',coalesce((select jsonb_agg(x) from (select extract(hour from first_seen at time zone 'Asia/Bangkok')::integer as hour,count(*) as visits from visits group by hour order by hour) x),'[]'::jsonb),
 'runGames',coalesce((select jsonb_agg(x) from (select game,count(*) as starts,count(completed_at) as finishes from runs group by game) x),'[]'::jsonb),
 'visitDetails',coalesce((select jsonb_agg(x) from (select nickname,device,meta,first_seen,last_seen,active_seconds,play_seconds from visits order by first_seen desc limit 50) x),'[]'::jsonb),
 'visitCount',(select count(*) from visits),
 'catalog',(select jsonb_agg(jsonb_build_object('id',id,'name',name,'rounds',rounds,'target',score_target,'enabled',enabled) order by rank_from,id) from public.pluggy_games)
 ) into extra;
 return base||extra;
end;$$;
revoke all on function public.pluggy_touch_v2(uuid,uuid,uuid,text,text,boolean,boolean,text,jsonb,integer,integer) from public;
revoke all on function public.pluggy_start_v2(uuid,uuid,uuid,text) from public;
revoke all on function public.pluggy_result_v2(uuid,uuid,uuid,text,text,integer,jsonb,boolean) from public;
revoke all on function public.pluggy_event_v2(uuid,uuid,uuid,text) from public;
revoke all on function public.pluggy_leaderboard(date,text,uuid,uuid) from public;
revoke all on function public.pluggy_dashboard_v2(integer,text,text,timestamptz,timestamptz) from public;
grant execute on function public.pluggy_touch_v2(uuid,uuid,uuid,text,text,boolean,boolean,text,jsonb,integer,integer),public.pluggy_start_v2(uuid,uuid,uuid,text),public.pluggy_result_v2(uuid,uuid,uuid,text,text,integer,jsonb,boolean),public.pluggy_event_v2(uuid,uuid,uuid,text),public.pluggy_leaderboard(date,text,uuid,uuid) to anon;
grant execute on function public.pluggy_dashboard_v2(integer,text,text,timestamptz,timestamptz) to authenticated;
commit;
