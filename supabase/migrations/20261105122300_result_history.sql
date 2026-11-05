alter table public.audit_events add column details jsonb not null default '{}' check (jsonb_typeof(details) = 'object');

create or replace function private.audit_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare d jsonb; detail jsonb := '{}';
begin
  d := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  if tg_table_name = 'experiments' and tg_op = 'UPDATE' then
    if new.representative_group_id is distinct from old.representative_group_id then
      detail := jsonb_build_object(
        'previous_group_id', old.representative_group_id, 'group_id', new.representative_group_id,
        'previous_context_id', (select context_id from public.run_groups where project_id = old.project_id and id = old.representative_group_id),
        'context_id', (select context_id from public.run_groups where project_id = new.project_id and id = new.representative_group_id));
    end if;
  end if;
  insert into public.audit_events(project_id, actor_id, entity_type, entity_id, action, reason, details)
    values (case when tg_table_name = 'projects' then (d ->> 'id')::uuid else (d ->> 'project_id')::uuid end,
      auth.uid(), tg_table_name, coalesce(d ->> 'id', d ->> 'user_id', d ->> 'run_id', d ->> 'group_id', d ->> 'context_id'),
      lower(tg_op), coalesce(d ->> 'change_reason', d ->> 'reason', nullif(current_setting('dxcel.change_reason', true), '')), detail);
  return null;
end $$;
create or replace function private.guard_metric_insert()
returns trigger language plpgsql set search_path = '' as $$
declare g uuid; s public.group_state;
begin
  select group_id into g from public.runs where project_id = new.project_id and id = new.run_id for update;
  select state into s from public.run_groups where project_id = new.project_id and id = g for update;
  if s is distinct from 'draft' or exists (
    select 1 from public.run_group_selections selection join public.run_groups selected_group
      on selected_group.project_id = selection.project_id and selected_group.id = selection.group_id
    where selection.project_id = new.project_id and selection.run_id = new.run_id and selected_group.state = 'finalized'
  ) then raise exception 'Finalized metrics cannot change' using errcode = '23514'; end if;
  return new;
end $$;

create or replace function public.record_run(
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
  insert into public.run_metrics(project_id, run_id, context_id, metric_definition_id, state, reason)
    select p_project, result, g.context_id, cm.metric_definition_id, 'missing', 'Not supplied in registration'
    from public.context_metrics cm where cm.project_id = p_project and cm.context_id = g.context_id
      and not exists (select 1 from public.run_metrics m where m.project_id = p_project and m.run_id = result and m.metric_definition_id = cm.metric_definition_id);
  update public.experiments set updated_at = now() where project_id = p_project and id = g.experiment_id;
  return result;
end $$;

create or replace function private.guard_group()
returns trigger language plpgsql set search_path = '' as $$
declare accounted integer;
begin
  if tg_op = 'INSERT' then
    if new.state <> 'draft' then raise exception 'Groups start as drafts' using errcode = '23514'; end if;
    perform 1 from public.comparison_contexts where project_id = new.project_id and id = new.context_id for update;
    return new;
  end if;
  if old.state = 'finalized' or (to_jsonb(new) - array['state','finalized_at','finalized_by'])
    is distinct from (to_jsonb(old) - array['state','finalized_at','finalized_by']) then
    raise exception 'Group design and finalized groups are immutable' using errcode = '23514';
  end if;
  if new.state = 'finalized' then
    perform r.id from public.runs r join public.run_group_selections s on s.project_id = r.project_id and s.run_id = r.id
      where s.project_id = new.project_id and s.group_id = new.id order by r.id for update of r;
    select (select count(*) from public.run_group_selections where project_id = new.project_id and group_id = new.id)
      + (select count(*) from public.run_group_exclusions where project_id = new.project_id and group_id = new.id) into accounted;
    if accounted <> new.expected_repetitions or not exists
      (select 1 from public.run_group_selections where project_id = new.project_id and group_id = new.id) then
      raise exception 'Every repetition needs a selection or exclusion, with at least one selection' using errcode = '23514';
    end if;
    if exists (
      select 1 from public.run_group_selections s join public.runs r on r.project_id = s.project_id and r.id = s.run_id
      join public.run_groups origin on origin.project_id = r.project_id and origin.id = r.group_id
      where s.project_id = new.project_id and s.group_id = new.id
      and (r.status <> 'succeeded' or origin.revision_id <> new.revision_id or r.context_id <> new.context_id or r.config <> new.config
        or exists (select 1 from public.context_metrics cm where cm.project_id = new.project_id and cm.context_id = new.context_id and cm.required
          and not exists (select 1 from public.run_metrics m where m.project_id = r.project_id and m.run_id = r.id
            and m.metric_definition_id = cm.metric_definition_id and m.state = 'measured')))
    ) then raise exception 'Selections require compatible successful runs and all required metrics' using errcode = '23514'; end if;
    if exists (
      select r.generation_output_id from public.run_group_selections s join public.runs r on r.project_id = s.project_id and r.id = s.run_id
      where s.project_id = new.project_id and s.group_id = new.id group by r.generation_output_id having count(*) > 1
    ) then raise exception 'The same generation output cannot count as independent repetitions' using errcode = '23514'; end if;
  end if;
  return new;
end $$;
