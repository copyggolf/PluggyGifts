create or replace function public.pluggy_leaderboard_current(p_period text default 'day',p_game text default null,p_visit uuid default null,p_secret uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d date=(now() at time zone 'Asia/Bangkok')::date; lo timestamptz; hi timestamptz; cutoff timestamptz; me uuid; result jsonb; required integer;
begin
 if p_period not in ('day','week') or p_period is null then raise exception 'Invalid period';end if;
 if p_period='week' then d=date_trunc('week',d::timestamp)::date;end if;
 lo=d::timestamp at time zone 'Asia/Bangkok';hi=lo+case when p_period='week' then interval '7 days' else interval '1 day' end;cutoff=least(hi,now());
 select visitor_id into me from public.pluggy_visits where id=p_visit and secret=p_secret;
 select count(*) into required from public.pluggy_games where rank_from<cutoff and (rank_to is null or rank_to>=cutoff);
 with best as (
 select distinct on(v.visitor_id,r.game) v.visitor_id,r.game,r.nickname,r.score,r.normalized,r.created_at
 from public.pluggy_results r join public.pluggy_visits v on v.id=r.visit_id join public.pluggy_games g on g.id=r.game
 where r.created_at>=lo and r.created_at<hi and r.rank_public and r.normalized is not null and g.rank_from<cutoff and (g.rank_to is null or g.rank_to>=cutoff)
 order by v.visitor_id,r.game,r.score desc,r.created_at asc,r.id
 ), best_all as (
 select distinct on(v.visitor_id,r.game) v.visitor_id,r.game,r.nickname,r.score,r.normalized,r.created_at
 from public.pluggy_results r join public.pluggy_visits v on v.id=r.visit_id join public.pluggy_games g on g.id=r.game
 where r.rank_public and r.normalized is not null and g.rank_from<cutoff and (g.rank_to is null or g.rank_to>=cutoff)
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
 select jsonb_build_object('day',d,'period',p_period,'startsAt',lo,'endsAt',hi,'game',p_game,'requiredGames',required,'participants',(select count(*) from eligible),
 'top',coalesce((select jsonb_agg(t) from (select position,nickname,points,raw_score,games_done,breakdown from eligible order by position,achieved_at,visitor_id limit 10) t),'[]'::jsonb),
 'mine',(select jsonb_build_object('position',e.position,'nickname',c.nickname,'points',c.points,'raw_score',c.raw_score,'games_done',c.games_done,'breakdown',c.breakdown) from candidates c left join eligible e using(visitor_id) where c.visitor_id=me),
 'games',(select jsonb_agg(jsonb_build_object('id',id,'name',name,'rounds',rounds,'target',score_target,'enabled',enabled) order by rank_from,id) from public.pluggy_games where rank_from<cutoff and (rank_to is null or rank_to>=cutoff)),
 'records',coalesce((select jsonb_agg(x) from (select distinct on(game) game,nickname,score,normalized as points from best_all order by game,score desc,created_at asc) x),'[]'::jsonb),
 'overallRecord',(select jsonb_build_object('nickname',nickname,'points',points,'games_done',games_done) from all_totals order by points desc,achieved_at asc,visitor_id limit 1),
 'updatedAt',now()) into result;
 return result;
end;$$;

revoke all on function public.pluggy_leaderboard_current(text,text,uuid,uuid) from public;
grant execute on function public.pluggy_leaderboard_current(text,text,uuid,uuid) to anon;
