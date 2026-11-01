-- No gameplay score ceiling; validate only physically possible results for each timed mission.
begin;
create or replace function public.pluggy_start_v5(p_run uuid,p_visit uuid,p_secret uuid,p_game text)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform public.pluggy_start_v2(p_run,p_visit,p_secret,p_game);
 update public.pluggy_runs set rules_version=4 where id=p_run and visit_id=p_visit and completed_at is null;
end;$$;
create or replace function public.pluggy_result_v5(p_run uuid,p_visit uuid,p_secret uuid,p_name text,p_game text,p_score integer,p_rounds jsonb,p_public boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.pluggy_runs; n integer; total integer=0; rounds_count integer; possible integer;
begin
 if not exists(select 1 from public.pluggy_visits where id=p_visit and secret=p_secret) then raise exception 'Invalid visit';end if;
 if exists(select 1 from public.pluggy_results where id=p_run and visit_id=p_visit) then return (select jsonb_build_object('ranked',false,'points',score) from public.pluggy_results where id=p_run and visit_id=p_visit);end if;
 select * into r from public.pluggy_runs where id=p_run and visit_id=p_visit and game=p_game and rules_version=4;
 if p_game='catch' then rounds_count=1;possible=1440;elsif p_game='buster' then rounds_count=1;possible=4600;elsif p_game='shuffle' then rounds_count=2;possible=1000;else raise exception 'Invalid result';end if;
 if r.id is null or not exists(select 1 from public.pluggy_games where id=p_game and enabled) or p_name is null or length(trim(p_name)) not between 1 and 30 or jsonb_typeof(p_rounds) is distinct from 'array' or jsonb_array_length(p_rounds)<>rounds_count or p_score is null or p_score<0 or p_score>possible then raise exception 'Invalid result';end if;
 for i in 0..rounds_count-1 loop
  if jsonb_typeof(p_rounds->i) is distinct from 'number' or (p_rounds->>i)!~'^-?[0-9]+$' then raise exception 'Invalid round';end if;
  n=(p_rounds->>i)::integer;
  if p_game='shuffle' then
   if n<>500 and n<>greatest(0,total-200)-total then raise exception 'Invalid round score';end if;
  elsif n<0 or n>possible or n%(case when p_game='catch' then 10 else 100 end)<>0 then raise exception 'Score outside game limits';end if;
  total=total+n;if total<0 then raise exception 'Score outside game limits';end if;
 end loop;
 if total<>p_score then raise exception 'Score mismatch';end if;
 insert into public.pluggy_results(id,visit_id,nickname,game,score,rounds,rank_public,normalized,rank_version)
 values(p_run,p_visit,trim(p_name),p_game,p_score,p_rounds,false,p_score,4);
 update public.pluggy_runs set completed_at=now() where id=p_run;
 return jsonb_build_object('ranked',false,'points',p_score);
end;$$;
create or replace function public.pluggy_dashboard_actual(p_page integer default 0,p_game text default null,p_name text default '',p_from timestamptz default null,p_to timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare b jsonb;
begin
 -- Existing RPC checks owner identity and filters before returning private data.
 b=public.pluggy_dashboard_v2(p_page,p_game,p_name,p_from,p_to);
 return b||jsonb_build_object('results',coalesce((select jsonb_agg(value-'normalized') from jsonb_array_elements(b->'results')),'[]'::jsonb));
end;$$;
revoke all on function public.pluggy_start_v5(uuid,uuid,uuid,text) from public;
revoke all on function public.pluggy_result_v5(uuid,uuid,uuid,text,text,integer,jsonb,boolean) from public;
revoke all on function public.pluggy_dashboard_actual(integer,text,text,timestamptz,timestamptz) from public;
grant execute on function public.pluggy_start_v5(uuid,uuid,uuid,text),public.pluggy_result_v5(uuid,uuid,uuid,text,text,integer,jsonb,boolean) to anon;
grant execute on function public.pluggy_dashboard_actual(integer,text,text,timestamptz,timestamptz) to authenticated;
commit;
