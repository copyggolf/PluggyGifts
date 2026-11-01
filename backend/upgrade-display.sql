begin;
create or replace function public.pluggy_start_v7(p_run uuid,p_visit uuid,p_secret uuid,p_game text,p_mode text default 'normal') returns void language plpgsql security definer set search_path='' as $$
declare s uuid;
begin
 if p_mode is null or p_mode not in ('easy','normal','hard') then raise exception 'Invalid mode';end if;
 perform public.pluggy_start_v2(p_run,p_visit,p_secret,p_game);
 select id into s from public.pluggy_seasons where ended_at is null for share;
 -- Retries must never restart the clock, change mode or move an existing run into a new season.
 update public.pluggy_runs set rules_version=6,mode=p_mode,season_id=s where id=p_run and visit_id=p_visit and game=p_game and rules_version=1 and completed_at is null;
 if not exists(select 1 from public.pluggy_runs where id=p_run and visit_id=p_visit and game=p_game and mode=p_mode and rules_version=6) then raise exception 'Invalid run';end if;
end;$$;

create or replace function public.pluggy_result_v7(p_run uuid,p_visit uuid,p_secret uuid,p_name text,p_game text,p_score integer,p_rounds jsonb,p_public boolean default true) returns jsonb language plpgsql security definer set search_path='' as $$
declare reward integer; penalty integer; r public.pluggy_runs; n integer; total integer=0; count_rounds integer; possible integer; step integer; seconds_min integer; eligible boolean;
begin
 if not exists(select 1 from public.pluggy_visits where id=p_visit and secret=p_secret) then raise exception 'Invalid visit';end if;
 if exists(select 1 from public.pluggy_results where id=p_run and visit_id=p_visit) then return (select jsonb_build_object('ranked',rank_public,'points',score,'run',id) from public.pluggy_results where id=p_run and visit_id=p_visit);end if;
 select * into r from public.pluggy_runs where id=p_run and visit_id=p_visit and game=p_game and rules_version=6 for update;
 if exists(select 1 from public.pluggy_results where id=p_run and visit_id=p_visit) then return (select jsonb_build_object('ranked',rank_public,'points',score,'run',id) from public.pluggy_results where id=p_run and visit_id=p_visit);end if;
 if p_game='catch' then count_rounds=1;seconds_min=24;step=case r.mode when 'easy' then 5 when 'hard' then 20 else 10 end;possible=case r.mode when 'easy' then 820 when 'hard' then 4460 else 1900 end;
 elsif p_game='buster' then count_rounds=1;seconds_min=24;step=50;possible=case r.mode when 'easy' then 1500 when 'hard' then 9900 else 4600 end;
 elsif p_game='shuffle' then count_rounds=2;seconds_min=12;step=100;possible=case r.mode when 'easy' then 600 when 'hard' then 1600 else 1000 end;
 else raise exception 'Invalid result';end if;
 if r.id is null or not exists(select 1 from public.pluggy_games where id=p_game and enabled) or p_name is null or length(trim(p_name)) not between 1 and 30 or jsonb_typeof(p_rounds) is distinct from 'array' or jsonb_array_length(p_rounds)<>count_rounds or p_score is null or p_score<0 or p_score>possible then raise exception 'Invalid result';end if;
 for i in 0..count_rounds-1 loop
  if jsonb_typeof(p_rounds->i) is distinct from 'number' or (p_rounds->>i)!~'^-?[0-9]+$' then raise exception 'Invalid round';end if;n=(p_rounds->>i)::integer;
  if p_game='shuffle' then reward=case r.mode when 'easy' then 300 when 'hard' then 800 else 500 end;penalty=case r.mode when 'easy' then 100 when 'hard' then 300 else 200 end; if n<>reward and n<>greatest(0,total-penalty)-total then raise exception 'Invalid round score';end if;
  elsif n<0 or n>possible or n%(case when p_game='buster' then case r.mode when 'easy' then 50 when 'hard' then 150 else 100 end else step end)<>0 then raise exception 'Score outside game limits';end if;
  total=total+n;if total<0 then raise exception 'Score outside game limits';end if;
 end loop;
 if total<>p_score then raise exception 'Score mismatch';end if;
 eligible=coalesce(p_public,false) and now()>=r.started_at+make_interval(secs=>seconds_min) and exists(select 1 from public.pluggy_seasons where id=r.season_id and ended_at is null);
 insert into public.pluggy_results(id,visit_id,nickname,game,score,rounds,rank_public,normalized,rank_version,mode,season_id) values(p_run,p_visit,trim(p_name),p_game,p_score,p_rounds,eligible,p_score,6,r.mode,r.season_id);
 update public.pluggy_runs set completed_at=now() where id=p_run;
 return jsonb_build_object('ranked',eligible,'points',p_score,'run',p_run);
end;$$;


create or replace function public.pluggy_validate_display(p_doc jsonb) returns void language plpgsql set search_path='' as $$
declare k text; v jsonb; txt text;
begin
 if jsonb_typeof(p_doc) is distinct from 'object' or octet_length(p_doc::text)>250000 then raise exception 'Invalid display document';end if;
 for k,v in select * from jsonb_each(p_doc) loop
  if k not in ('brand.name','brand.tagline','brand.icon','home.banner','home.eyebrow','home.intro','home.nameLabel','home.namePlaceholder','home.startButton','home.missionHeading','home.missionKicker','home.missionSubtitle','home.playButton','home.pill1','home.pill2','game.catch.name','game.catch.thai','game.catch.desc','game.catch.cover','game.catch.background','game.catch.steps','game.catch.rules','game.buster.name','game.buster.thai','game.buster.desc','game.buster.cover','game.buster.background','game.buster.steps','game.buster.rules','game.shuffle.name','game.shuffle.thai','game.shuffle.desc','game.shuffle.cover','game.shuffle.background','game.shuffle.steps','game.shuffle.rules','mascot.catcher','mascot.hammer','mascot.guide','mascot.celebrate','mascot.appLogo','campaign.title','campaign.tagline','campaign.dates','campaign.image','campaign.url','campaign.button','campaign.hint','result.heading','result.high','result.good','result.encourage','result.shop','result.again','result.save','result.home','theme.background','theme.accent','theme.panel','theme.coverFit','theme.coverPosition','theme.bgShade') or jsonb_typeof(v) is distinct from 'string' or length(v#>>'{}')>4000 then raise exception 'Invalid display field: %',k;end if;txt=v#>>'{}';
  if k in ('brand.icon','home.banner','mascot.catcher','mascot.hammer','mascot.guide','mascot.celebrate','mascot.appLogo','campaign.image') or k~'^game\.[a-z]+\.(cover|background)$' then
   if txt<>'' and not ((txt~'^assets/[a-zA-Z0-9_./ -]+(\?v=[a-zA-Z0-9_.-]+)?$' and strpos(txt,'..')=0) or txt~'^https://idevduwmcbphzsoomihn\.supabase\.co/storage/v1/object/public/pluggy-display/[a-zA-Z0-9_./-]+$' or txt~'^https://copyggolf\.github\.io/PluggyGifts/assets/[a-zA-Z0-9_./-]+$') then raise exception 'Invalid display image';end if;
  elsif k in ('theme.background','theme.panel','theme.accent') and txt!~'^#[0-9a-fA-F]{6}$' then raise exception 'Invalid display color';
  elsif k='theme.coverFit' and txt not in ('contain','cover') then raise exception 'Invalid display fit';
  elsif k='theme.coverPosition' and txt not in ('top','center','bottom') then raise exception 'Invalid display position';
  elsif k='theme.bgShade' then if txt!~'^[0-9]{1,2}$' or txt::integer>80 then raise exception 'Invalid display shade';end if;
  elsif k='campaign.url' and txt!~'^https://([a-zA-Z0-9-]+\.)*powerbuy\.co\.th(/[^[:space:]]*)?$' then raise exception 'Invalid campaign URL';end if;
 end loop;
end;$$;
create table if not exists public.pluggy_display(id boolean primary key default true check(id),draft jsonb not null default '{}',published jsonb not null default '{}',revision integer not null default 0,published_at timestamptz,updated_at timestamptz not null default now());
create table if not exists public.pluggy_display_history(revision integer primary key,document jsonb not null,published_at timestamptz not null default now(),owner_id uuid);
alter table public.pluggy_display enable row level security;alter table public.pluggy_display_history enable row level security;
revoke all on public.pluggy_display,public.pluggy_display_history from public,anon,authenticated;
insert into public.pluggy_display(id) values(true) on conflict do nothing;
create or replace function public.pluggy_display_public() returns jsonb language sql stable security definer set search_path='' as $$ select jsonb_build_object('document',published,'revision',revision,'publishedAt',published_at) from public.pluggy_display where id $$;
create or replace function public.pluggy_display_owner(p_action text default 'read',p_document jsonb default '{}',p_expected integer default null,p_restore integer default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.pluggy_display; doc jsonb;
begin
 if not exists(select 1 from public.pluggy_admins where user_id=auth.uid()) then raise exception 'Owner access required';end if;
 select * into r from public.pluggy_display where id for update;
 if p_action not in ('read','draft','publish','restore') then raise exception 'Invalid display action';end if;
 if p_action<>'read' then
  if p_expected is distinct from r.revision then raise exception 'Display changed; reload first';end if;
  doc=p_document;
  if p_action='restore' then select document into doc from public.pluggy_display_history where revision=p_restore;if doc is null then raise exception 'Unknown display revision';end if;end if;
  perform public.pluggy_validate_display(doc);
  if p_action='publish' then
   insert into public.pluggy_display_history(revision,document,owner_id) values(r.revision,r.published,auth.uid()) on conflict do nothing;
   update public.pluggy_display set draft=doc,published=doc,revision=revision+1,published_at=now(),updated_at=now() where id;
  else update public.pluggy_display set draft=doc,revision=revision+1,updated_at=now() where id;end if;
 end if;
 return (select to_jsonb(d)||jsonb_build_object('history',coalesce((select jsonb_agg(t) from(select revision,published_at from public.pluggy_display_history order by revision desc limit 30)t),'[]'::jsonb)) from public.pluggy_display d where id);
end;$$;

-- Import historical native scores once into the current competition, as requested by the owner.
-- Original result records and their prior privacy flags remain unchanged.
create table if not exists public.pluggy_rank_imports(result_id uuid primary key references public.pluggy_results(id),season_id uuid not null references public.pluggy_seasons(id));
insert into public.pluggy_rank_imports select r.id,s.id from public.pluggy_results r cross join public.pluggy_seasons s where r.season_id is null and r.created_at<s.started_at and s.ended_at is null on conflict do nothing;
create table if not exists public.pluggy_rank_edits(season_id uuid references public.pluggy_seasons(id),visitor_id uuid not null,nickname text,score integer,hidden boolean not null default false,updated_at timestamptz not null default now(),primary key(season_id,visitor_id),check(score is null or score between 0 and 10000000),check(nickname is null or length(trim(nickname)) between 1 and 30));
create table if not exists public.pluggy_rank_audit(id bigint generated always as identity primary key,season_id uuid,visitor_id uuid,action text not null,before_data jsonb,after_data jsonb,owner_id uuid,created_at timestamptz not null default now());
alter table public.pluggy_rank_imports enable row level security;alter table public.pluggy_rank_edits enable row level security;alter table public.pluggy_rank_audit enable row level security;
revoke all on public.pluggy_rank_imports,public.pluggy_rank_edits,public.pluggy_rank_audit from public,anon,authenticated;
create or replace function public.pluggy_rank_source(p_season uuid) returns table(visitor_id uuid,id uuid,nickname text,score integer,game text,mode text,created_at timestamptz) language sql stable security definer set search_path='' as $$
 select v.visitor_id,r.id,r.nickname,r.score,r.game,r.mode,r.created_at from public.pluggy_results r join public.pluggy_visits v on v.id=r.visit_id left join public.pluggy_rank_imports i on i.result_id=r.id where ((r.season_id=p_season and r.rank_public and r.rank_version>=5) or i.season_id=p_season)
$$;
create or replace function public.pluggy_rank_rows(p_season uuid) returns table(visitor_id uuid,id uuid,nickname text,score integer,game text,mode text,created_at timestamptz,hidden boolean,edited boolean,original_name text,original_score integer,"position" bigint) language sql stable security definer set search_path='' as $$
 with best as(select distinct on (r.visitor_id) r.* from public.pluggy_rank_source(p_season) r order by r.visitor_id,r.score desc,r.created_at,r.id),
 merged as(select b.visitor_id,b.id,coalesce(e.nickname,b.nickname) nickname,coalesce(e.score,b.score) score,b.game,b.mode,b.created_at,coalesce(e.hidden,false) hidden,(e.score is not null or e.nickname is not null) edited,b.nickname original_name,b.score original_score from best b left join public.pluggy_rank_edits e on e.season_id=p_season and e.visitor_id=b.visitor_id),
 ranks as(select m.visitor_id,row_number() over(order by m.score desc,m.created_at,m.id) as pos from merged m where not m.hidden)
 select m.*,r.pos from merged m left join ranks r using(visitor_id)
$$;
create or replace function public.pluggy_performance(p_visit uuid default null,p_secret uuid default null,p_run uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.pluggy_seasons; me uuid; answer jsonb;
begin
 select * into s from public.pluggy_seasons where ended_at is null;
 select visitor_id into me from public.pluggy_visits where id=p_visit and secret=p_secret;
 with ranks as (select * from public.pluggy_rank_rows(s.id) where not hidden),
 ownrun as (select r.* from public.pluggy_rank_source(s.id) r where r.id=p_run and r.visitor_id=me and not exists(select 1 from public.pluggy_rank_edits e where e.season_id=s.id and e.visitor_id=me and e.hidden)),
 gamebest as(select distinct on(r.visitor_id,r.game) r.* from public.pluggy_rank_source(s.id) r where not exists(select 1 from public.pluggy_rank_edits e where e.season_id=s.id and e.visitor_id=r.visitor_id and e.hidden) order by r.visitor_id,r.game,r.score desc,r.created_at,r.id),
 gamerank as(select *,row_number() over(partition by game order by score desc,created_at,id) as game_position from gamebest)
 select jsonb_build_object('season',jsonb_build_object('title',s.title,'startedAt',s.started_at),'participants',(select count(*) from ranks),
 'top',coalesce((select jsonb_agg(t) from(select position,nickname,score,game,mode,edited,(visitor_id=me) as mine from ranks order by position limit 10)t),'[]'::jsonb),
 'mine',(select jsonb_build_object('position',position,'nickname',nickname,'score',score,'game',game,'mode',mode,'edited',edited) from ranks where visitor_id=me),
 'run',(select jsonb_build_object('score',r.score,'position',1+(select count(*) from ranks b where b.visitor_id<>me and (b.score>r.score or (b.score=r.score and (b.created_at,b.id)<(r.created_at,r.id)))),'gamePosition',(select game_position from gamerank where visitor_id=me and game=r.game)) from ownrun r),
 'updatedAt',now()) into answer;return answer;
end;$$;
create or replace function public.pluggy_rank_owner(p_action text default 'read',p_visitor uuid default null,p_season uuid default null,p_name text default null,p_score integer default null,p_page integer default 0,p_search text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid; before_row jsonb; after_row jsonb; answer jsonb;
begin
 if not exists(select 1 from public.pluggy_admins where user_id=auth.uid()) then raise exception 'Owner access required';end if;
 select id into s from public.pluggy_seasons where ended_at is null for share;
 if p_action not in ('read','edit','hide','restore','revert') or p_page not between 0 and 100000 or length(coalesce(p_search,''))>30 then raise exception 'Invalid ranking action';end if;
 if p_action<>'read' then
  if p_season is distinct from s then raise exception 'Season changed; reload first';end if;
  if not exists(select 1 from public.pluggy_rank_source(s) where visitor_id=p_visitor) then raise exception 'Unknown player';end if;
  if p_action='edit' and (p_name is null or length(trim(p_name)) not between 1 and 30 or p_score is null or p_score not between 0 and 10000000) then raise exception 'Invalid ranking edit';end if;
  select to_jsonb(e) into before_row from public.pluggy_rank_edits e where season_id=s and visitor_id=p_visitor;
  insert into public.pluggy_rank_edits(season_id,visitor_id) values(s,p_visitor) on conflict do nothing;
  if p_action='edit' then update public.pluggy_rank_edits set nickname=trim(p_name),score=p_score,updated_at=now() where season_id=s and visitor_id=p_visitor;
  elsif p_action in ('hide','restore') then update public.pluggy_rank_edits set hidden=p_action='hide',updated_at=now() where season_id=s and visitor_id=p_visitor;
  elsif p_action='revert' then update public.pluggy_rank_edits set nickname=null,score=null,hidden=false,updated_at=now() where season_id=s and visitor_id=p_visitor;end if;
  select to_jsonb(e) into after_row from public.pluggy_rank_edits e where season_id=s and visitor_id=p_visitor;
  insert into public.pluggy_rank_audit(season_id,visitor_id,action,before_data,after_data,owner_id) values(s,p_visitor,p_action,before_row,after_row,auth.uid());
 end if;
 with rows as(select * from public.pluggy_rank_rows(s) where coalesce(p_search,'')='' or nickname ilike '%'||p_search||'%' or original_name ilike '%'||p_search||'%')
 select jsonb_build_object('season',s,'total',(select count(*) from rows),'rows',coalesce((select jsonb_agg(t) from(select * from rows order by hidden,position,created_at,id limit 50 offset p_page*50)t),'[]'::jsonb),
 'audit',coalesce((select jsonb_agg(t) from(select action,created_at,visitor_id from public.pluggy_rank_audit where season_id=s order by id desc limit 20)t),'[]'::jsonb)) into answer;return answer;
end;$$;
revoke all on function public.pluggy_validate_display(jsonb),public.pluggy_rank_source(uuid),public.pluggy_rank_rows(uuid) from public,anon,authenticated;
revoke all on function public.pluggy_start_v7(uuid,uuid,uuid,text,text),public.pluggy_result_v7(uuid,uuid,uuid,text,text,integer,jsonb,boolean),public.pluggy_display_public(),public.pluggy_display_owner(text,jsonb,integer,integer),public.pluggy_rank_owner(text,uuid,uuid,text,integer,integer,text) from public;
grant execute on function public.pluggy_start_v7(uuid,uuid,uuid,text,text),public.pluggy_result_v7(uuid,uuid,uuid,text,text,integer,jsonb,boolean),public.pluggy_display_public() to anon;
grant execute on function public.pluggy_display_owner(text,jsonb,integer,integer),public.pluggy_rank_owner(text,uuid,uuid,text,integer,integer,text) to authenticated;
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
 return jsonb_build_object('current',(select to_jsonb(t) from public.pluggy_seasons t where ended_at is null),'history',coalesce((select jsonb_agg(t) from (select ss.*,(select count(*) from public.pluggy_rank_source(ss.id)) as results,(select count(*) from public.pluggy_rank_rows(ss.id) where not hidden) as players from public.pluggy_seasons ss order by ss.started_at desc limit 50)t),'[]'::jsonb));
end;$$;


commit;
