-- Play first. Anonymous results remain in private analytics until a name is confirmed.
begin;
alter table public.pluggy_results add column if not exists name_confirmed boolean not null default true;
create or replace function public.pluggy_result_v8(p_run uuid,p_visit uuid,p_secret uuid,p_name text,p_game text,p_score integer,p_rounds jsonb,p_public boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare reply jsonb;
begin
 if not exists(select 1 from public.pluggy_visits where id=p_visit and secret=p_secret) then raise exception 'Invalid visit';end if;
 -- Serialize with existing result creation so retries cannot undo a confirmed name.
 perform 1 from public.pluggy_runs where id=p_run and visit_id=p_visit for update;
 if exists(select 1 from public.pluggy_results where id=p_run and visit_id=p_visit) then return jsonb_build_object('run',p_run,'saved',true);end if;
 reply=public.pluggy_result_v7(p_run,p_visit,p_secret,'ผู้เล่น',p_game,p_score,p_rounds,false);
 update public.pluggy_results set name_confirmed=false where id=p_run and visit_id=p_visit;
 return reply;
end;$$;
create or replace function public.pluggy_name_result(p_run uuid,p_visit uuid,p_secret uuid,p_name text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.pluggy_results; g public.pluggy_runs; eligible boolean;
begin
 if not exists(select 1 from public.pluggy_visits where id=p_visit and secret=p_secret) then raise exception 'Invalid visit';end if;
 if p_name is null or length(trim(p_name)) not between 1 and 30 then raise exception 'Invalid name';end if;
 select * into g from public.pluggy_runs where id=p_run and visit_id=p_visit for update;
 select * into r from public.pluggy_results where id=p_run and visit_id=p_visit for update;
 if r.id is null or g.completed_at is null then raise exception 'Result not saved';end if;
 if r.name_confirmed then
  if r.nickname<>trim(p_name) then raise exception 'Name already confirmed';end if;
  return jsonb_build_object('ranked',r.rank_public,'run',p_run);
 end if;
 -- Use the original completion time, never the later name submission time.
 eligible=g.completed_at>=g.started_at+make_interval(secs=>case when g.game='shuffle' then 12 else 24 end) and exists(select 1 from public.pluggy_seasons where id=g.season_id and ended_at is null);
 update public.pluggy_results set nickname=trim(p_name),name_confirmed=true,rank_public=eligible where id=p_run and visit_id=p_visit;
 update public.pluggy_visits set nickname=trim(p_name) where id=p_visit;
 return jsonb_build_object('ranked',eligible,'run',p_run);
end;$$;
revoke all on function public.pluggy_result_v8(uuid,uuid,uuid,text,text,integer,jsonb,boolean),public.pluggy_name_result(uuid,uuid,uuid,text) from public;
grant execute on function public.pluggy_result_v8(uuid,uuid,uuid,text,text,integer,jsonb,boolean),public.pluggy_name_result(uuid,uuid,uuid,text) to anon;

create or replace function public.pluggy_coupon_claim(p_run uuid,p_visit uuid,p_secret uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.pluggy_coupon_settings;v public.pluggy_coupon_versions;r public.pluggy_runs;me uuid;last_mine integer;last_global integer;choices integer[];selected integer;
begin
 select visitor_id into me from public.pluggy_visits where id=p_visit and secret=p_secret;if me is null then raise exception 'Invalid visit';end if;
 select * into r from public.pluggy_runs where id=p_run and visit_id=p_visit;
 if r.id is null then return jsonb_build_object('pending',true);end if;
 if not exists(select 1 from public.pluggy_results where id=p_run and visit_id=p_visit) then return jsonb_build_object('pending',true);end if;
 if not exists(select 1 from public.pluggy_results where id=p_run and visit_id=p_visit and name_confirmed) then return jsonb_build_object('name_required',true);end if;
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

commit;
