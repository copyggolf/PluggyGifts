-- Competition v6: native points, mode-bound runs, privacy-limited leaderboard, reset by new season.
begin;
alter table public.pluggy_runs add column if not exists mode text not null default 'normal';
alter table public.pluggy_results add column if not exists mode text not null default 'normal';
create table if not exists public.pluggy_seasons(id uuid primary key, title text not null check(length(title) between 1 and 100), started_at timestamptz not null default now(), ended_at timestamptz);
create unique index if not exists pluggy_one_active_season on public.pluggy_seasons ((true)) where ended_at is null;
alter table public.pluggy_seasons enable row level security;
revoke all on public.pluggy_seasons from public,anon,authenticated;
alter table public.pluggy_runs add column if not exists season_id uuid references public.pluggy_seasons(id);
alter table public.pluggy_results add column if not exists season_id uuid references public.pluggy_seasons(id);
insert into public.pluggy_seasons(id,title) select gen_random_uuid(),'Power of Gifts · รอบเปิดการแข่งขัน' where not exists(select 1 from public.pluggy_seasons where ended_at is null);
create index if not exists pluggy_performance_season on public.pluggy_results(season_id,score desc,created_at,id) where rank_public and rank_version=5;

create or replace function public.pluggy_start_v6(p_run uuid,p_visit uuid,p_secret uuid,p_game text,p_mode text default 'normal') returns void language plpgsql security definer set search_path='' as $$
declare s uuid;
begin
 if p_mode is null or (p_game='catch' and p_mode not in ('easy','normal','hard')) or (p_game<>'catch' and p_mode<>'normal') then raise exception 'Invalid mode';end if;
 perform public.pluggy_start_v2(p_run,p_visit,p_secret,p_game);
 select id into s from public.pluggy_seasons where ended_at is null for share;
 -- Retries must never restart the clock, change mode or move an existing run into a new season.
 update public.pluggy_runs set rules_version=5,mode=p_mode,season_id=s where id=p_run and visit_id=p_visit and game=p_game and rules_version=1 and completed_at is null;
 if not exists(select 1 from public.pluggy_runs where id=p_run and visit_id=p_visit and game=p_game and mode=p_mode and rules_version=5) then raise exception 'Invalid run';end if;
end;$$;

create or replace function public.pluggy_result_v6(p_run uuid,p_visit uuid,p_secret uuid,p_name text,p_game text,p_score integer,p_rounds jsonb,p_public boolean default true) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.pluggy_runs; n integer; total integer=0; count_rounds integer; possible integer; step integer; seconds_min integer; eligible boolean;
begin
 if not exists(select 1 from public.pluggy_visits where id=p_visit and secret=p_secret) then raise exception 'Invalid visit';end if;
 if exists(select 1 from public.pluggy_results where id=p_run and visit_id=p_visit) then return (select jsonb_build_object('ranked',rank_public,'points',score,'run',id) from public.pluggy_results where id=p_run and visit_id=p_visit);end if;
 select * into r from public.pluggy_runs where id=p_run and visit_id=p_visit and game=p_game and rules_version=5 for update;
 if exists(select 1 from public.pluggy_results where id=p_run and visit_id=p_visit) then return (select jsonb_build_object('ranked',rank_public,'points',score,'run',id) from public.pluggy_results where id=p_run and visit_id=p_visit);end if;
 if p_game='catch' then count_rounds=1;seconds_min=24;step=5;possible=case r.mode when 'easy' then 820 when 'hard' then 4460 else 1900 end;
 elsif p_game='buster' then count_rounds=1;seconds_min=24;step=100;possible=4600;
 elsif p_game='shuffle' then count_rounds=2;seconds_min=12;step=100;possible=1000;
 else raise exception 'Invalid result';end if;
 if r.id is null or not exists(select 1 from public.pluggy_games where id=p_game and enabled) or p_name is null or length(trim(p_name)) not between 1 and 30 or jsonb_typeof(p_rounds) is distinct from 'array' or jsonb_array_length(p_rounds)<>count_rounds or p_score is null or p_score<0 or p_score>possible then raise exception 'Invalid result';end if;
 for i in 0..count_rounds-1 loop
  if jsonb_typeof(p_rounds->i) is distinct from 'number' or (p_rounds->>i)!~'^-?[0-9]+$' then raise exception 'Invalid round';end if;n=(p_rounds->>i)::integer;
  if p_game='shuffle' then if n<>500 and n<>greatest(0,total-200)-total then raise exception 'Invalid round score';end if;
  elsif n<0 or n>possible or n%step<>0 then raise exception 'Score outside game limits';end if;
  total=total+n;if total<0 then raise exception 'Score outside game limits';end if;
 end loop;
 if total<>p_score then raise exception 'Score mismatch';end if;
 eligible=coalesce(p_public,false) and now()>=r.started_at+make_interval(secs=>seconds_min) and exists(select 1 from public.pluggy_seasons where id=r.season_id and ended_at is null);
 insert into public.pluggy_results(id,visit_id,nickname,game,score,rounds,rank_public,normalized,rank_version,mode,season_id) values(p_run,p_visit,trim(p_name),p_game,p_score,p_rounds,eligible,p_score,5,r.mode,r.season_id);
 update public.pluggy_runs set completed_at=now() where id=p_run;
 return jsonb_build_object('ranked',eligible,'points',p_score,'run',p_run);
end;$$;

create or replace function public.pluggy_performance(p_visit uuid default null,p_secret uuid default null,p_run uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.pluggy_seasons; me uuid; answer jsonb;
begin
 select * into s from public.pluggy_seasons where ended_at is null;
 select visitor_id into me from public.pluggy_visits where id=p_visit and secret=p_secret;
 with best as (
 select distinct on(v.visitor_id) v.visitor_id,r.id,r.nickname,r.score,r.game,r.mode,r.created_at from public.pluggy_results r join public.pluggy_visits v on v.id=r.visit_id where r.season_id=s.id and r.rank_public and r.rank_version=5 order by v.visitor_id,r.score desc,r.created_at,r.id
 ), ranked as (select *,row_number() over(order by score desc,created_at,id) as position from best),
 gamebest as (select distinct on(v.visitor_id,r.game) v.visitor_id,r.game,r.score,r.created_at,r.id from public.pluggy_results r join public.pluggy_visits v on v.id=r.visit_id where r.season_id=s.id and r.rank_public and r.rank_version=5 order by v.visitor_id,r.game,r.score desc,r.created_at,r.id),
 gamerank as (select *,row_number() over(partition by game order by score desc,created_at,id) as position from gamebest),
 ownrun as (select r.* from public.pluggy_results r join public.pluggy_visits v on v.id=r.visit_id where r.id=p_run and v.visitor_id=me and r.season_id=s.id and r.rank_public and r.rank_version=5)
 select jsonb_build_object('season',jsonb_build_object('title',s.title,'startedAt',s.started_at),'participants',(select count(*) from best),
 'top',coalesce((select jsonb_agg(to_jsonb(t)) from(select position,nickname,score,game,mode,(visitor_id=me) as mine from ranked order by position limit 10)t),'[]'::jsonb),
 'mine',(select jsonb_build_object('position',position,'nickname',nickname,'score',score,'game',game,'mode',mode) from ranked where visitor_id=me),
 'run',(select jsonb_build_object('score',r.score,'position',1+(select count(*) from best b where b.visitor_id<>me and (b.score>r.score or (b.score=r.score and (b.created_at,b.id)<(r.created_at,r.id)))),'gamePosition',(select position from gamerank where visitor_id=me and game=r.game)) from ownrun r),'updatedAt',now()) into answer;
 return answer;
end;$$;

create or replace function public.pluggy_competition_owner(p_action text default 'read',p_id uuid default null,p_title text default '',p_expected uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare currentseason public.pluggy_seasons;
begin
 if not exists(select 1 from public.pluggy_admins where user_id=auth.uid()) then raise exception 'Owner access required';end if;
 if p_action not in ('read','reset') then raise exception 'Invalid action';end if;
 if p_action='reset' then
  if p_id is null or length(trim(p_title)) not between 1 and 100 then raise exception 'Invalid season';end if;
  if not exists(select 1 from public.pluggy_seasons where id=p_id) then
   select * into currentseason from public.pluggy_seasons where ended_at is null for update;
   if p_expected is distinct from currentseason.id then raise exception 'Season changed; refresh first';end if;
   update public.pluggy_seasons set ended_at=now() where id=currentseason.id;
   insert into public.pluggy_seasons(id,title) values(p_id,trim(p_title));
  end if;
 end if;
 return jsonb_build_object('current',(select to_jsonb(t) from public.pluggy_seasons t where ended_at is null),'history',coalesce((select jsonb_agg(t) from (select s.*,count(r.id) as results,count(distinct v.visitor_id) as players from public.pluggy_seasons s left join public.pluggy_results r on r.season_id=s.id and r.rank_public left join public.pluggy_visits v on v.id=r.visit_id group by s.id order by s.started_at desc limit 50)t),'[]'::jsonb));
end;$$;

-- One consistent set of filters for all historical dashboard sections; live counts are explicitly separate.
create or replace function public.pluggy_dashboard_v3(p_page integer default 0,p_game text default null,p_name text default '',p_from timestamptz default null,p_to timestamptz default null,p_device text default null,p_mode text default null,p_visit_page integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare answer jsonb;
begin
 if not exists(select 1 from public.pluggy_admins where user_id=auth.uid()) then raise exception 'Owner access required';end if;
 if p_page not between 0 and 100000 or p_visit_page not between 0 and 100000 or length(coalesce(p_name,''))>30 or (p_device is not null and p_device not in ('mobile','tablet','desktop')) or (p_mode is not null and p_mode not in ('easy','normal','hard')) or (p_from is not null and p_to is not null and p_from>=p_to) then raise exception 'Invalid filters';end if;
 with cohort as (
 select v.* from public.pluggy_visits v where (p_device is null or v.device=p_device) and (coalesce(p_name,'')='' or v.nickname ilike '%'||p_name||'%') and ((p_game is null and p_mode is null) or exists(select 1 from public.pluggy_runs r where r.visit_id=v.id and (p_game is null or r.game=p_game) and (p_mode is null or r.mode=p_mode) and (p_from is null or r.started_at>=p_from) and (p_to is null or r.started_at<p_to)))
 ), visits as (select * from cohort where (p_from is null or first_seen>=p_from) and (p_to is null or first_seen<p_to)),
 runs as (select r.* from public.pluggy_runs r join cohort v on v.id=r.visit_id where (p_game is null or r.game=p_game) and (p_mode is null or r.mode=p_mode) and (p_from is null or r.started_at>=p_from) and (p_to is null or r.started_at<p_to)),
 results as (select r.*,v.device from public.pluggy_results r join public.pluggy_visits v on v.id=r.visit_id where (p_game is null or r.game=p_game) and (p_mode is null or r.mode=p_mode) and (p_device is null or v.device=p_device) and (coalesce(p_name,'')='' or r.nickname ilike '%'||p_name||'%') and (p_from is null or r.created_at>=p_from) and (p_to is null or r.created_at<p_to)),
 events as (select e.* from public.pluggy_events e join cohort v on v.id=e.visit_id where (p_from is null or e.created_at>=p_from) and (p_to is null or e.created_at<p_to)),
 segments as (select 'device' as kind,device as label from visits union all select 'os',coalesce(nullif(meta->>'os',''),'ไม่ทราบ') from visits union all select 'browser',coalesce(nullif(meta->>'browser',''),'ไม่ทราบ') from visits union all select 'source',coalesce(nullif(meta->>'source',''),'direct') from visits union all select 'campaign',coalesce(nullif(meta->>'campaign',''),'ไม่ระบุ') from visits), grouped as(select kind,label,count(*) as visits from segments group by kind,label)
 select jsonb_build_object(
 'updatedAt',now(),'online',(select count(*) from public.pluggy_visits where visible and last_seen>now()-interval '75 seconds'),'playing',(select count(*) from public.pluggy_visits where visible and playing and last_seen>now()-interval '75 seconds'),
 'visitors',(select count(distinct visitor_id) from visits),'players',(select count(distinct v.visitor_id) from runs r join public.pluggy_visits v on v.id=r.visit_id),'visits',(select count(*) from visits),'completed',(select count(*) from results),'filtered',(select count(*) from results),'visitCount',(select count(*) from visits),
 'results',coalesce((select jsonb_agg(t) from (select id,nickname,game,score,rounds,created_at,rank_public,rank_version,mode,device from results order by created_at desc,id limit 50 offset p_page*50)t),'[]'::jsonb),
 'active',coalesce((select jsonb_agg(t) from(select nickname,device,game,playing,last_seen from public.pluggy_visits where visible and last_seen>now()-interval '75 seconds' order by last_seen desc limit 100)t),'[]'::jsonb),
 'byGame',coalesce((select jsonb_agg(t) from(select game,count(*) as games,round(avg(score),1) as average,max(score) as best from results group by game)t),'[]'::jsonb),
 'engagement',jsonb_build_object('activeMinutes',(select round(coalesce(sum(active_seconds),0)/60.0,1) from visits),'playMinutes',(select round(coalesce(sum(play_seconds),0)/60.0,1) from visits),'avgActiveMinutes',(select round(coalesce(avg(active_seconds) filter(where meta<>'{}'),0)/60,1) from visits),'starts',(select count(*) from runs),'finishes',(select count(*) from runs where completed_at is not null),'returning',(select count(distinct v.visitor_id) from visits v where exists(select 1 from public.pluggy_visits old where old.visitor_id=v.visitor_id and (old.first_seen at time zone 'Asia/Bangkok')::date<(v.first_seen at time zone 'Asia/Bangkok')::date))),
 'runGames',coalesce((select jsonb_agg(t) from(select game,count(*) as starts,count(completed_at) as finishes from runs group by game)t),'[]'::jsonb),
 'segments',coalesce((select jsonb_agg(t) from(select * from grouped order by kind,visits desc limit 150)t),'[]'::jsonb),
 'events',coalesce((select jsonb_agg(t) from(select kind,count(*) as count from events group by kind)t),'[]'::jsonb),
 'daily',coalesce((select jsonb_agg(t) from(select (first_seen at time zone 'Asia/Bangkok')::date as day,count(*) as visits,count(distinct visitor_id) as visitors from visits group by day order by day desc limit 30)t),'[]'::jsonb),
 'hours',coalesce((select jsonb_agg(t) from(select extract(hour from first_seen at time zone 'Asia/Bangkok')::integer as hour,count(*) as visits from visits group by hour order by hour)t),'[]'::jsonb),
 'visitDetails',coalesce((select jsonb_agg(t) from(select nickname,device,meta,first_seen,last_seen,active_seconds,play_seconds from visits order by first_seen desc,id limit 50 offset p_visit_page*50)t),'[]'::jsonb)
 ) into answer;return answer;
end;$$;
revoke all on function public.pluggy_start_v6(uuid,uuid,uuid,text,text),public.pluggy_result_v6(uuid,uuid,uuid,text,text,integer,jsonb,boolean),public.pluggy_performance(uuid,uuid,uuid),public.pluggy_competition_owner(text,uuid,text,uuid),public.pluggy_dashboard_v3(integer,text,text,timestamptz,timestamptz,text,text,integer) from public;
grant execute on function public.pluggy_start_v6(uuid,uuid,uuid,text,text),public.pluggy_result_v6(uuid,uuid,uuid,text,text,integer,jsonb,boolean),public.pluggy_performance(uuid,uuid,uuid) to anon;
grant execute on function public.pluggy_competition_owner(text,uuid,text,uuid),public.pluggy_dashboard_v3(integer,text,text,timestamptz,timestamptz,text,text,integer) to authenticated;
commit;
