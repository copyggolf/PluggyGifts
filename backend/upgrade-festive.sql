-- Festive quick-play; additive migration preserves older games and offline queues.
begin;
alter table public.pluggy_runs add column if not exists rules_version integer not null default 1;
create or replace function public.pluggy_start_v4(p_run uuid,p_visit uuid,p_secret uuid,p_game text)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform public.pluggy_start_v2(p_run,p_visit,p_secret,p_game);
 update public.pluggy_runs set rules_version=3 where id=p_run and visit_id=p_visit and completed_at is null;
end;$$;
create or replace function public.pluggy_result_v4(p_run uuid,p_visit uuid,p_secret uuid,p_name text,p_game text,p_score integer,p_rounds jsonb,p_public boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.pluggy_runs; n integer; total integer=0; rounds_count integer; seconds_min integer;
begin
 if not exists(select 1 from public.pluggy_visits where id=p_visit and secret=p_secret) then raise exception 'Invalid visit';end if;
 if exists(select 1 from public.pluggy_results where id=p_run and visit_id=p_visit) then return jsonb_build_object('ranked',false,'points',p_score);end if;
 select * into r from public.pluggy_runs where id=p_run and visit_id=p_visit and game=p_game and rules_version=3;
 if p_game in ('catch','buster') then rounds_count=1;seconds_min=24;elsif p_game='shuffle' then rounds_count=2;seconds_min=12;else raise exception 'Invalid result';end if;
 if r.id is null or not exists(select 1 from public.pluggy_games where id=p_game and enabled) or p_name is null or length(trim(p_name)) not between 1 and 30 or jsonb_typeof(p_rounds) is distinct from 'array' or jsonb_array_length(p_rounds)<>rounds_count or p_score is null or p_score not between 0 and 1000 then raise exception 'Invalid result';end if;
 for i in 0..rounds_count-1 loop
  if jsonb_typeof(p_rounds->i) is distinct from 'number' or (p_rounds->>i)!~'^-?[0-9]+$' then raise exception 'Invalid round';end if;
  n=(p_rounds->>i)::integer;
  if p_game='shuffle' then
   if n<>least(1000,total+500)-total and n<>greatest(0,total-200)-total then raise exception 'Invalid round score';end if;
  elsif n<0 or n>1000 or n%(case when p_game='catch' then 10 else 100 end)<>0 then raise exception 'Score outside game limits';end if;
  total=total+n;if total not between 0 and 1000 then raise exception 'Score outside game limits';end if;
 end loop;
 if total<>p_score then raise exception 'Score mismatch';end if;
 -- Quick-play has no public leaderboard. Too-short submissions remain private history.
 insert into public.pluggy_results(id,visit_id,nickname,game,score,rounds,rank_public,normalized,rank_version)
 values(p_run,p_visit,trim(p_name),p_game,p_score,p_rounds,false,p_score,3);
 update public.pluggy_runs set completed_at=now() where id=p_run;
 return jsonb_build_object('ranked',false,'points',p_score,'verified_time',now()>=r.started_at+make_interval(secs=>seconds_min));
end;$$;
-- Keep legacy 2000-point consumers coherent when they encounter a newer result.
create or replace function public.pluggy_score_2000(p_game text,p_score integer,p_version integer)
returns integer language sql stable set search_path='' as $$
 select case when p_version>=3 then 2*greatest(0,least(1000,p_score)) when p_version=2 then greatest(0,least(2000,p_score)) else round(2000.0*greatest(0,least(p_score,score_target))/score_target)::integer end from public.pluggy_games where id=p_game
$$;
create or replace function public.pluggy_dashboard_festive(p_page integer default 0,p_game text default null,p_name text default '',p_from timestamptz default null,p_to timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare b jsonb; rows jsonb='[]'; r jsonb; rounds jsonb; cumulative integer; prior integer; v integer; points integer;
begin
 b=public.pluggy_dashboard_v2(p_page,p_game,p_name,p_from,p_to);
 for r in select value from jsonb_array_elements(b->'results') loop
  cumulative=0;prior=0;rounds='[]';
  for v in select value::integer from jsonb_array_elements_text(r->'rounds') loop
   cumulative=cumulative+v;points=round(public.pluggy_score_2000(r->>'game',cumulative,(r->>'rank_version')::integer)/2.0)::integer;
   rounds=rounds||jsonb_build_array(points-prior);prior=points;
  end loop;
  rows=rows||jsonb_build_array((r-'normalized')||jsonb_build_object('score',round(public.pluggy_score_2000(r->>'game',(r->>'score')::integer,(r->>'rank_version')::integer)/2.0)::integer,'rounds',rounds,'score_max',1000));
 end loop;
 return b||jsonb_build_object('results',rows,'byGame',coalesce((select jsonb_agg(x) from (select game,count(*) as games,round(avg(round(public.pluggy_score_2000(game,score,rank_version)/2.0)),1) as average,max(round(public.pluggy_score_2000(game,score,rank_version)/2.0)) as best from public.pluggy_results group by game) x),'[]'::jsonb));
end;$$;
create table if not exists public.pluggy_coupon (
 id integer primary key check(id=1),enabled boolean not null default false,title text not null default 'ของขวัญพิเศษจาก Power Buy',code text not null default '',image text not null default '',terms text not null default '',shop_url text not null default 'https://www.powerbuy.co.th/',starts_at timestamptz,ends_at timestamptz,updated_at timestamptz not null default now()
);
alter table public.pluggy_coupon enable row level security;
revoke all on public.pluggy_coupon from anon,authenticated;
insert into public.pluggy_coupon(id) values(1) on conflict(id) do nothing;
create or replace function public.pluggy_coupon_owner()
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.pluggy_admins where user_id=auth.uid()) then raise exception 'Owner access required' using errcode='42501';end if;
 return (select to_jsonb(c) from public.pluggy_coupon c where id=1);
end;$$;
create or replace function public.pluggy_coupon_save(p_enabled boolean,p_title text,p_code text,p_image text,p_terms text,p_shop_url text,p_starts_at timestamptz default null,p_ends_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.pluggy_admins where user_id=auth.uid()) then raise exception 'Owner access required' using errcode='42501';end if;
 if p_enabled is null or p_title is null or length(trim(p_title)) not between 1 and 120 or p_code is null or length(p_code)>80 or p_terms is null or length(p_terms)>2000 or p_image is null or length(p_image)>900000 or p_shop_url is null or p_shop_url !~ '^https://([a-zA-Z0-9-]+\.)*powerbuy\.co\.th(/|$)' or length(p_shop_url)>1000 or (p_starts_at is not null and p_ends_at is not null and p_ends_at<=p_starts_at) then raise exception 'Invalid coupon';end if;
 if p_image<>'' and p_image !~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$' then raise exception 'Invalid coupon image';end if;
 if p_enabled and trim(p_code)='' and p_image='' then raise exception 'Coupon needs code or image';end if;
 update public.pluggy_coupon set enabled=p_enabled,title=trim(p_title),code=trim(p_code),image=p_image,terms=p_terms,shop_url=p_shop_url,starts_at=p_starts_at,ends_at=p_ends_at,updated_at=now() where id=1;
 return public.pluggy_coupon_owner();
end;$$;
create or replace function public.pluggy_coupon_public()
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('title',title,'code',code,'image',image,'terms',terms,'shop_url',shop_url,'ends_at',ends_at)
 from public.pluggy_coupon where id=1 and enabled and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now())
$$;
revoke all on function public.pluggy_start_v4(uuid,uuid,uuid,text) from public;
revoke all on function public.pluggy_result_v4(uuid,uuid,uuid,text,text,integer,jsonb,boolean) from public;
revoke all on function public.pluggy_dashboard_festive(integer,text,text,timestamptz,timestamptz) from public;
revoke all on function public.pluggy_coupon_owner() from public;
revoke all on function public.pluggy_coupon_save(boolean,text,text,text,text,text,timestamptz,timestamptz) from public;
revoke all on function public.pluggy_coupon_public() from public;
grant execute on function public.pluggy_start_v4(uuid,uuid,uuid,text),public.pluggy_result_v4(uuid,uuid,uuid,text,text,integer,jsonb,boolean),public.pluggy_coupon_public() to anon;
grant execute on function public.pluggy_dashboard_festive(integer,text,text,timestamptz,timestamptz),public.pluggy_coupon_owner(),public.pluggy_coupon_save(boolean,text,text,text,text,text,timestamptz,timestamptz) to authenticated;
commit;
