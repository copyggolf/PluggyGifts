-- One player-facing score, native 0..2000; original rows/legacy clients remain intact.
begin;
alter table public.pluggy_games add column if not exists score_max_v3 jsonb;
alter table public.pluggy_games add column if not exists score_step_v3 integer;
update public.pluggy_games set score_max_v3='[680,960,840]',score_step_v3=10 where id='catch';
update public.pluggy_games set score_max_v3='[2000,2000,2000]',score_step_v3=10 where id='buster';
update public.pluggy_games set score_max_v3='[400,400,400,400,400]',score_step_v3=80 where id='shuffle';
create or replace function public.pluggy_score_2000(p_game text,p_score integer,p_version integer)
returns integer language sql stable set search_path='' as $$
 select case when p_version>=2 then greatest(0,least(2000,p_score)) else round(2000.0*greatest(0,least(p_score,score_target))/score_target)::integer end from public.pluggy_games where id=p_game
$$;
revoke all on function public.pluggy_score_2000(text,integer,integer) from public;
create or replace function public.pluggy_result_v3(p_run uuid,p_visit uuid,p_secret uuid,p_name text,p_game text,p_score integer,p_rounds jsonb,p_public boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare g public.pluggy_games; total integer; n integer; r public.pluggy_runs;
begin
 if not exists(select 1 from public.pluggy_visits where id=p_visit and secret=p_secret) then raise exception 'Invalid visit';end if;
 if exists(select 1 from public.pluggy_results where id=p_run and visit_id=p_visit) then return (select jsonb_build_object('ranked',rank_public,'points',normalized) from public.pluggy_results where id=p_run and visit_id=p_visit);end if;
 select * into g from public.pluggy_games where id=p_game and enabled;
 select * into r from public.pluggy_runs where id=p_run and visit_id=p_visit and game=p_game;
 if g.id is null or r.id is null or p_name is null or length(trim(p_name)) not between 1 and 30 or jsonb_typeof(p_rounds) is distinct from 'array' or jsonb_array_length(p_rounds)<>g.rounds or p_score is null or p_score not between 0 and 2000 or g.score_max_v3 is null then raise exception 'Invalid result';end if;
 total=0;
 for i in 0..g.rounds-1 loop
  if jsonb_typeof(p_rounds->i) is distinct from 'number' or (p_rounds->>i)!~'^-?[0-9]+$' then raise exception 'Invalid round';end if;
  n=(p_rounds->>i)::integer;
  if n < -2000 or n > (g.score_max_v3->>i)::integer or n % g.score_step_v3 <> 0 then raise exception 'Score outside game limits';end if;
  if p_game='shuffle' and n <> least(2000,total+400)-total and n <> greatest(0,total-160)-total then raise exception 'Invalid round score';end if;
  total=total+n;
  if total not between 0 and 2000 then raise exception 'Score outside game limits';end if;
 end loop;
 if total<>p_score then raise exception 'Score mismatch';end if;
 if now()<r.started_at+make_interval(secs=>g.min_seconds) then p_public=false;end if;
 insert into public.pluggy_results(id,visit_id,nickname,game,score,rounds,rank_public,normalized,rank_version)
 values(p_run,p_visit,trim(p_name),p_game,p_score,p_rounds,coalesce(p_public,false),p_score,2);
 update public.pluggy_runs set completed_at=now() where id=p_run;
 return jsonb_build_object('ranked',coalesce(p_public,false),'points',p_score);
end;$$;
create or replace function public.pluggy_leaderboard_2000(p_period text default 'day',p_game text default null,p_visit uuid default null,p_secret uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d date=(now() at time zone 'Asia/Bangkok')::date; lo timestamptz; hi timestamptz; cutoff timestamptz; me uuid; result jsonb; required integer;
begin
 if p_period not in ('day','week') or p_period is null then raise exception 'Invalid period';end if;
 if p_period='week' then d=date_trunc('week',d::timestamp)::date;end if;
 lo=d::timestamp at time zone 'Asia/Bangkok';hi=lo+case when p_period='week' then interval '7 days' else interval '1 day' end;cutoff=least(hi,now());
 select visitor_id into me from public.pluggy_visits where id=p_visit and secret=p_secret;
 select count(*) into required from public.pluggy_games where rank_from<cutoff and (rank_to is null or rank_to>=cutoff);
 with best as (
 select distinct on(v.visitor_id,r.game) v.visitor_id,r.game,r.nickname,public.pluggy_score_2000(r.game,r.score,r.rank_version) as score,public.pluggy_score_2000(r.game,r.score,r.rank_version) as normalized,r.created_at
 from public.pluggy_results r join public.pluggy_visits v on v.id=r.visit_id join public.pluggy_games g on g.id=r.game
 where r.created_at>=lo and r.created_at<hi and r.rank_public and r.normalized is not null and g.rank_from<cutoff and (g.rank_to is null or g.rank_to>=cutoff)
 order by v.visitor_id,r.game,public.pluggy_score_2000(r.game,r.score,r.rank_version) desc,r.created_at asc,r.id
 ), best_all as (
 select distinct on(v.visitor_id,r.game) v.visitor_id,r.game,r.nickname,public.pluggy_score_2000(r.game,r.score,r.rank_version) as score,public.pluggy_score_2000(r.game,r.score,r.rank_version) as normalized,r.created_at
 from public.pluggy_results r join public.pluggy_visits v on v.id=r.visit_id join public.pluggy_games g on g.id=r.game
 where r.rank_public and r.normalized is not null and g.rank_from<cutoff and (g.rank_to is null or g.rank_to>=cutoff)
 order by v.visitor_id,r.game,public.pluggy_score_2000(r.game,r.score,r.rank_version) desc,r.created_at asc,r.id
 ), all_totals as (
 select visitor_id,(array_agg(nickname order by created_at desc))[1] as nickname,sum(normalized)::integer as points,count(*) as games_done,max(created_at) as achieved_at from best_all group by visitor_id having count(*)=required and required>0
 ), candidates as (
 select visitor_id,(array_agg(nickname order by created_at desc))[1] as nickname,
 case when p_game is null then sum(normalized)::integer else max(normalized) end as points,
 case when p_game is null then null else max(score) end as raw_score,
 count(*) as games_done,max(created_at) as achieved_at,
 jsonb_agg(jsonb_build_object('game',game,'score',score,'points',normalized) order by game) as breakdown
 from best where p_game is null or game=p_game group by visitor_id
 ), eligible as (
 select *,dense_rank() over(order by points desc,case when p_game is not null then raw_score end desc) as position
 from candidates where p_game is not null or (games_done=required and required>0)
 )
 select jsonb_build_object('day',d,'period',p_period,'startsAt',lo,'endsAt',hi,'game',p_game,'requiredGames',required,'participants',(select count(*) from eligible),
 'top',coalesce((select jsonb_agg(t) from (select position,nickname,points,raw_score,games_done,breakdown from eligible order by position,achieved_at,visitor_id limit 10) t),'[]'::jsonb),
 'mine',(select jsonb_build_object('position',e.position,'nickname',c.nickname,'points',c.points,'raw_score',c.raw_score,'games_done',c.games_done,'breakdown',c.breakdown) from candidates c left join eligible e using(visitor_id) where c.visitor_id=me),
 'games',(select jsonb_agg(jsonb_build_object('id',id,'name',name,'rounds',rounds,'target',2000,'enabled',enabled) order by rank_from,id) from public.pluggy_games where rank_from<cutoff and (rank_to is null or rank_to>=cutoff)),
 'records',coalesce((select jsonb_agg(x) from (select distinct on(game) game,nickname,score,normalized as points from best_all order by game,score desc,created_at asc) x),'[]'::jsonb),
 'overallRecord',(select jsonb_build_object('nickname',nickname,'points',points,'games_done',games_done) from all_totals order by points desc,achieved_at asc,visitor_id limit 1),
 'updatedAt',now()) into result;
 return result;
end;$$;

revoke all on function public.pluggy_leaderboard_2000(text,text,uuid,uuid) from public;
grant execute on function public.pluggy_leaderboard_2000(text,text,uuid,uuid) to anon;

create or replace function public.pluggy_dashboard_2000(p_page integer default 0,p_game text default null,p_name text default '',p_from timestamptz default null,p_to timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare b jsonb; rows jsonb='[]'; r jsonb; rounds jsonb; cumulative integer; prior integer; v integer;
begin
 -- The existing dashboard enforces the admin allowlist before any private data is read.
 b=public.pluggy_dashboard_v2(p_page,p_game,p_name,p_from,p_to);
 for r in select value from jsonb_array_elements(b->'results') loop
  cumulative=0;prior=0;rounds='[]';
  for v in select value::integer from jsonb_array_elements_text(r->'rounds') loop
   cumulative=cumulative+v;
   rounds=rounds||jsonb_build_array(public.pluggy_score_2000(r->>'game',cumulative,(r->>'rank_version')::integer)-prior);
   prior=public.pluggy_score_2000(r->>'game',cumulative,(r->>'rank_version')::integer);
  end loop;
  rows=rows||jsonb_build_array((r-'normalized')||jsonb_build_object('score',public.pluggy_score_2000(r->>'game',(r->>'score')::integer,(r->>'rank_version')::integer),'rounds',rounds));
 end loop;
 return b||jsonb_build_object('results',rows,'byGame',coalesce((select jsonb_agg(x) from (select game,count(*) as games,round(avg(public.pluggy_score_2000(game,score,rank_version)),1) as average,max(public.pluggy_score_2000(game,score,rank_version)) as best from public.pluggy_results group by game) x),'[]'::jsonb));
end;$$;
revoke all on function public.pluggy_dashboard_2000(integer,text,text,timestamptz,timestamptz) from public;
grant execute on function public.pluggy_dashboard_2000(integer,text,text,timestamptz,timestamptz) to authenticated;
revoke all on function public.pluggy_result_v3(uuid,uuid,uuid,text,text,integer,jsonb,boolean) from public;
grant execute on function public.pluggy_result_v3(uuid,uuid,uuid,text,text,integer,jsonb,boolean) to anon;
commit;
