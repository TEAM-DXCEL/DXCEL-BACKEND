create function public.create_project(p_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare result uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  insert into public.projects(name, created_by) values (p_name, auth.uid()) returning id into result;
  insert into public.project_members(project_id, user_id, role) values (result, auth.uid(), 'owner');
  return result;
end $$;
create function public.set_project_member(p_project uuid, p_user uuid, p_role public.project_role)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_role(p_project, array['owner']::public.project_role[]);
  if p_role is null then
    delete from public.project_members where project_id = p_project and user_id = p_user;
  else
    insert into public.project_members(project_id, user_id, role) values (p_project, p_user, p_role)
      on conflict (project_id, user_id) do update set role = excluded.role;
  end if;
end $$;
create function public.create_experiment(
  p_project uuid, p_number integer, p_title text, p_hypothesis text, p_changes text,
  p_reason text, p_plan text, p_owner uuid default null, p_previous uuid default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare result uuid; revision uuid;
begin
  perform private.require_role(p_project, array['owner','editor']::public.project_role[]);
  if p_previous is not null and not exists (select 1 from public.experiments where project_id = p_project and id = p_previous)
    or p_owner is not null and not exists (select 1 from public.project_members where project_id = p_project and user_id = p_owner) then
    raise exception 'Invalid project reference' using errcode = '23514';
  end if;
  insert into public.experiments(project_id, number, title, owner_id, previous_experiment_id, created_by)
    values (p_project, p_number, p_title, p_owner, p_previous, auth.uid()) returning id into result;
  insert into public.experiment_revisions(project_id, experiment_id, version, hypothesis, changes, change_reason, evaluation_plan, created_by)
    values (p_project, result, 1, p_hypothesis, p_changes, p_reason, p_plan, auth.uid()) returning id into revision;
  update public.experiments set current_revision_id = revision where id = result;
  return result;
end $$;
create function public.revise_experiment(
  p_project uuid, p_experiment uuid, p_expected_revision integer,
  p_hypothesis text, p_changes text, p_reason text, p_plan text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare current_version integer; result uuid;
begin
  perform private.require_role(p_project, array['owner','editor']::public.project_role[]);
  select r.version into current_version from public.experiments e join public.experiment_revisions r
    on r.project_id = e.project_id and r.id = e.current_revision_id where e.project_id = p_project and e.id = p_experiment and e.archived_at is null;
  if not found then raise exception 'Invalid project reference' using errcode = '23514'; end if;
  if p_expected_revision is distinct from current_version then raise exception 'Revision conflict' using errcode = '40001'; end if;
  insert into public.experiment_revisions(project_id, experiment_id, version, hypothesis, changes, change_reason, evaluation_plan, created_by)
    values (p_project, p_experiment, current_version + 1, p_hypothesis, p_changes, p_reason, p_plan, auth.uid()) returning id into result;
  update public.experiments set current_revision_id = result where project_id = p_project and id = p_experiment;
  return result;
end $$;
create function public.define_metric(p_project uuid, p_name text, p_version integer, p_unit text, p_direction public.metric_direction, p_target double precision default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare result uuid;
begin
  perform private.require_role(p_project, array['owner','editor']::public.project_role[]);
  insert into public.metric_definitions(project_id, name, version, unit, direction, target, created_by)
    values (p_project, p_name, p_version, p_unit, p_direction, p_target, auth.uid()) returning id into result;
  return result;
end $$;
create function public.create_comparison_context(
  p_project uuid, p_name text, p_dataset text, p_split text, p_evaluation_version text,
  p_sample_size integer, p_metrics jsonb, p_config jsonb default '{}'
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare result uuid; m jsonb;
begin
  perform private.require_role(p_project, array['owner','editor']::public.project_role[]);
  if jsonb_typeof(p_metrics) is distinct from 'array' or jsonb_array_length(p_metrics) not between 1 and 200
    or octet_length(p_config::text) > 65536 then raise exception 'Invalid context payload' using errcode = '22023'; end if;
  insert into public.comparison_contexts(project_id, name, dataset_fingerprint, split_fingerprint, evaluation_version, sample_size, evaluation_config, created_by)
    values (p_project, p_name, p_dataset, p_split, p_evaluation_version, p_sample_size, p_config, auth.uid()) returning id into result;
  for m in select value from jsonb_array_elements(p_metrics) loop
    if not exists (select 1 from public.metric_definitions where project_id = p_project and id = (m ->> 'metric_id')::uuid) then
      raise exception 'Invalid project reference' using errcode = '23514';
    end if;
    insert into public.context_metrics(project_id, context_id, metric_definition_id, required)
      values (p_project, result, (m ->> 'metric_id')::uuid, coalesce((m ->> 'required')::boolean, true));
  end loop;
  return result;
end $$;
create function public.create_run_group(p_project uuid, p_experiment uuid, p_revision uuid, p_context uuid, p_repetitions integer, p_config jsonb default '{}')
returns uuid language plpgsql security definer set search_path = '' as $$
declare result uuid;
begin
  perform private.require_role(p_project, array['owner','editor']::public.project_role[]);
  if not exists (select 1 from public.experiment_revisions where project_id = p_project and experiment_id = p_experiment and id = p_revision)
    or not exists (select 1 from public.experiments where project_id = p_project and id = p_experiment and archived_at is null)
    or not exists (select 1 from public.comparison_contexts where project_id = p_project and id = p_context)
    or octet_length(p_config::text) > 65536 then raise exception 'Invalid group references or config' using errcode = '23514'; end if;
  insert into public.run_groups(project_id, experiment_id, revision_id, context_id, config, expected_repetitions, created_by)
    values (p_project, p_experiment, p_revision, p_context, p_config, p_repetitions, auth.uid()) returning id into result;
  return result;
end $$;
create function public.record_run(
  p_project uuid, p_group uuid, p_ingestion_id text, p_repetition integer, p_attempt integer,
  p_status public.run_status, p_fingerprint text, p_metrics jsonb,
  p_previous uuid default null, p_started_at timestamptz default null, p_finished_at timestamptz default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare result uuid; payload jsonb; canonical_metrics jsonb; existing public.runs; g public.run_groups;
  output_id uuid; m jsonb; completed_at timestamptz;
begin
  perform private.require_role(p_project, array['owner','editor']::public.project_role[]);
  if p_status not in ('succeeded','failed','cancelled') or p_status is null
    or jsonb_typeof(p_metrics) is distinct from 'array' or jsonb_array_length(p_metrics) > 200
    or octet_length(p_metrics::text) > 131072 then raise exception 'Invalid result payload' using errcode = '22023'; end if;
  select coalesce(jsonb_agg(value order by value ->> 'metric_id'), '[]') into canonical_metrics from jsonb_array_elements(p_metrics);
  payload := jsonb_build_object('version', 1, 'group_id', p_group, 'repetition', p_repetition, 'attempt', p_attempt,
    'status', p_status, 'fingerprint', p_fingerprint, 'metrics', canonical_metrics, 'previous_run_id', p_previous,
    'started_at', p_started_at, 'finished_at', p_finished_at);
  select * into existing from public.runs where project_id = p_project and ingestion_id = p_ingestion_id;
  if found then
    if existing.request_payload <> payload then raise exception 'Ingestion ID conflict' using errcode = '23505'; end if;
    return existing.id;
  end if;
  select * into g from public.run_groups where project_id = p_project and id = p_group and state = 'draft' for update;
  if not found then raise exception 'Invalid or finalized group' using errcode = '23514'; end if;
  if p_previous is not null and not exists (
    select 1 from public.runs r join public.run_groups origin on origin.project_id = r.project_id and origin.id = r.group_id
    where r.project_id = p_project and r.id = p_previous and origin.experiment_id = g.experiment_id
  ) then raise exception 'Invalid previous run' using errcode = '23514'; end if;
  if p_fingerprint is not null then
    insert into public.generation_outputs(project_id, fingerprint) values (p_project, p_fingerprint)
      on conflict (project_id, fingerprint) do nothing;
    select id into output_id from public.generation_outputs where project_id = p_project and fingerprint = p_fingerprint;
  end if;
  completed_at := coalesce(p_finished_at, now());
  insert into public.runs(project_id, group_id, context_id, ingestion_id, request_payload, repetition, attempt, generation_output_id,
    previous_run_id, status, config, started_at, finished_at)
    values (p_project, p_group, g.context_id, p_ingestion_id, payload, p_repetition, p_attempt, output_id,
      p_previous, p_status, g.config, p_started_at, completed_at) returning id into result;
  for m in select value from jsonb_array_elements(canonical_metrics) loop
    if not exists (select 1 from public.context_metrics where project_id = p_project and context_id = g.context_id and metric_definition_id = (m ->> 'metric_id')::uuid) then
      raise exception 'Metric is outside comparison context' using errcode = '23514';
    end if;
    insert into public.run_metrics(project_id, run_id, context_id, metric_definition_id, state, value, reason)
      values (p_project, result, g.context_id, (m ->> 'metric_id')::uuid, (m ->> 'state')::public.metric_state,
        (m ->> 'value')::double precision, m ->> 'reason');
  end loop;
  update public.experiments set updated_at = now() where project_id = p_project and id = g.experiment_id;
  return result;
end $$;
create function public.finalize_run_group(p_project uuid, p_group uuid, p_selections jsonb, p_exclusions jsonb, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare row_data jsonb;
begin
  perform private.require_role(p_project, array['owner','editor']::public.project_role[]);
  if jsonb_typeof(p_selections) is distinct from 'array' or jsonb_typeof(p_exclusions) is distinct from 'array'
    or jsonb_array_length(p_selections) + jsonb_array_length(p_exclusions) > 10000
    or p_reason is null or length(btrim(p_reason)) not between 1 and 20000 then
    raise exception 'Invalid selection payload or reason' using errcode = '22023';
  end if;
  perform 1 from public.run_groups where project_id = p_project and id = p_group and state = 'draft' for update;
  if not found then raise exception 'Invalid or finalized group' using errcode = '23514'; end if;
  perform set_config('dxcel.change_reason', p_reason, true);
  for row_data in select value from jsonb_array_elements(p_selections) loop
    if not exists (select 1 from public.runs where project_id = p_project and id = (row_data ->> 'run_id')::uuid) then
      raise exception 'Invalid project reference' using errcode = '23514';
    end if;
    insert into public.run_group_selections(project_id, group_id, repetition, run_id)
      values (p_project, p_group, (row_data ->> 'repetition')::integer, (row_data ->> 'run_id')::uuid);
  end loop;
  for row_data in select value from jsonb_array_elements(p_exclusions) loop
    insert into public.run_group_exclusions(project_id, group_id, repetition, reason)
      values (p_project, p_group, (row_data ->> 'repetition')::integer, row_data ->> 'reason');
  end loop;
  update public.run_groups set state = 'finalized', finalized_at = now(), finalized_by = auth.uid() where project_id = p_project and id = p_group;
end $$;
create function public.set_representative_result(p_project uuid, p_experiment uuid, p_group uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_role(p_project, array['owner','editor']::public.project_role[]);
  if p_reason is null or length(btrim(p_reason)) not between 1 and 20000 or not exists (
    select 1 from public.run_groups where project_id = p_project and experiment_id = p_experiment and id = p_group and state = 'finalized'
  ) then raise exception 'A finalized result and reason are required' using errcode = '23514'; end if;
  perform set_config('dxcel.change_reason', p_reason, true);
  update public.experiments set representative_group_id = p_group where project_id = p_project and id = p_experiment;
end $$;
create function public.create_baseline_version(
  p_project uuid, p_name text, p_kind public.baseline_kind, p_reason text,
  p_group uuid default null, p_context uuid default null, p_source text default null, p_metrics jsonb default '[]'
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare result uuid; previous public.baseline_versions; m jsonb; context_id uuid := p_context;
begin
  perform private.require_role(p_project, array['owner','editor']::public.project_role[]);
  if jsonb_typeof(p_metrics) is distinct from 'array' or jsonb_array_length(p_metrics) > 200 then raise exception 'Invalid metrics' using errcode = '22023'; end if;
  if p_kind = 'internal' then
    select g.context_id into context_id from public.run_groups g where g.project_id = p_project and g.id = p_group and g.state = 'finalized';
    if not found or p_context is not null and p_context <> context_id or p_metrics <> '[]' then
      raise exception 'Invalid finalized baseline' using errcode = '23514';
    end if;
  elsif p_context is not null and not exists (select 1 from public.comparison_contexts where project_id = p_project and id = p_context) then
    raise exception 'Invalid project reference' using errcode = '23514';
  end if;
  select * into previous from public.baseline_versions where project_id = p_project and name = p_name order by version desc limit 1;
  insert into public.baseline_versions(project_id, name, version, kind, group_id, context_id, source, reason, previous_baseline_id, created_by)
    values (p_project, p_name, coalesce(previous.version, 0) + 1, p_kind, p_group, context_id, p_source, p_reason, previous.id, auth.uid()) returning id into result;
  for m in select value from jsonb_array_elements(p_metrics) loop
    if not exists (select 1 from public.metric_definitions where project_id = p_project and id = (m ->> 'metric_id')::uuid) then
      raise exception 'Invalid project reference' using errcode = '23514';
    end if;
    insert into public.baseline_reported_metrics(project_id, baseline_id, metric_definition_id, mean, stddev, sample_count)
      values (p_project, result, (m ->> 'metric_id')::uuid, (m ->> 'mean')::float8, (m ->> 'stddev')::float8, (m ->> 'sample_count')::integer);
  end loop;
  return result;
end $$;
create function public.create_note(p_project uuid, p_body text, p_reason text, p_experiment uuid default null, p_run uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare result uuid;
begin
  perform private.require_role(p_project, array['owner','editor']::public.project_role[]);
  if p_experiment is not null and not exists (select 1 from public.experiments where project_id = p_project and id = p_experiment)
    or p_run is not null and not exists (select 1 from public.runs where project_id = p_project and id = p_run) then
    raise exception 'Invalid project reference' using errcode = '23514';
  end if;
  insert into public.notes(project_id, experiment_id, run_id, created_by) values (p_project, p_experiment, p_run, auth.uid()) returning id into result;
  insert into public.note_revisions(project_id, note_id, version, body, reason, created_by) values (p_project, result, 1, p_body, p_reason, auth.uid());
  update public.notes set current_revision = 1 where project_id = p_project and id = result;
  return result;
end $$;
create function public.revise_note(p_project uuid, p_note uuid, p_expected_revision integer, p_body text, p_reason text)
returns integer language plpgsql security definer set search_path = '' as $$
declare current_version integer;
begin
  perform private.require_role(p_project, array['owner','editor']::public.project_role[]);
  select current_revision into current_version from public.notes where project_id = p_project and id = p_note for update;
  if not found then raise exception 'Invalid project reference' using errcode = '23514'; end if;
  if p_expected_revision is distinct from current_version then raise exception 'Revision conflict' using errcode = '40001'; end if;
  insert into public.note_revisions(project_id, note_id, version, body, reason, created_by)
    values (p_project, p_note, current_version + 1, p_body, p_reason, auth.uid());
  update public.notes set current_revision = current_version + 1 where project_id = p_project and id = p_note;
  return current_version + 1;
end $$;

create view public.run_group_metric_summaries with (security_invoker = true) as
select s.project_id, s.group_id, m.metric_definition_id,
  avg(m.value) filter (where m.state = 'measured') as mean,
  stddev_samp(m.value) filter (where m.state = 'measured') as stddev,
  count(m.value) filter (where m.state = 'measured') as sample_count,
  count(*) filter (where m.state <> 'measured') as unavailable_count
from public.run_group_selections s
join public.run_groups g on g.project_id = s.project_id and g.id = s.group_id and g.state = 'finalized'
join public.run_metrics m on m.project_id = s.project_id and m.run_id = s.run_id
group by s.project_id, s.group_id, m.metric_definition_id;
revoke all on public.run_group_metric_summaries from public, anon, authenticated, service_role;
grant select on public.run_group_metric_summaries to authenticated;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any(array['create_project','set_project_member','create_experiment','revise_experiment',
      'define_metric','create_comparison_context','create_run_group','record_run','finalize_run_group','set_representative_result',
      'create_baseline_version','create_note','revise_note']) loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.signature);
    execute format('grant execute on function %s to authenticated', f.signature);
  end loop;
end $$;
