create function private.record_run_for_project(
  p_project uuid, p_group uuid, p_ingestion_id text, p_repetition integer, p_attempt integer,
  p_status public.run_status, p_fingerprint text, p_metrics jsonb,
  p_previous uuid default null, p_started_at timestamptz default null, p_finished_at timestamptz default null
)
returns uuid language plpgsql set search_path = '' as $$
declare result uuid; payload jsonb; canonical_metrics jsonb; existing public.runs; g public.run_groups;
  output_id uuid; m jsonb; completed_at timestamptz;
begin
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

revoke execute on function private.record_run_for_project(
  uuid, uuid, text, integer, integer, public.run_status, text, jsonb, uuid, timestamptz, timestamptz
) from public, anon, authenticated, service_role;

create or replace function public.record_run(
  p_project uuid, p_group uuid, p_ingestion_id text, p_repetition integer, p_attempt integer,
  p_status public.run_status, p_fingerprint text, p_metrics jsonb,
  p_previous uuid default null, p_started_at timestamptz default null, p_finished_at timestamptz default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_role(p_project, array['owner','editor']::public.project_role[]);
  return private.record_run_for_project(
    p_project, p_group, p_ingestion_id, p_repetition, p_attempt, p_status,
    p_fingerprint, p_metrics, p_previous, p_started_at, p_finished_at
  );
end $$;

create function public.issue_ingestion_token(p_project uuid, p_name text, p_expires_at timestamptz)
returns table (token_id uuid, token text, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_token text;
  v_id uuid;
begin
  perform private.require_role(p_project, array['owner']::public.project_role[]);
  if p_name is null or length(btrim(p_name)) not between 1 and 80
     or p_expires_at is null or p_expires_at <= clock_timestamp()
     or p_expires_at > clock_timestamp() + interval '90 days' then
    raise exception 'Invalid token metadata' using errcode = '22023';
  end if;

  v_token := 'dxcel_' || replace(gen_random_uuid()::text, '-', '') ||
    replace(gen_random_uuid()::text, '-', '');
  insert into public.ingestion_tokens (project_id, name, token_hash, created_by, expires_at)
  values (p_project, btrim(p_name), encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), v_actor, p_expires_at)
  returning id into v_id;
  return query select v_id, v_token, p_expires_at;
end;
$$;

create function public.revoke_ingestion_token(p_project uuid, p_token_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_role(p_project, array['owner']::public.project_role[]);

  update public.ingestion_tokens
  set revoked_at = clock_timestamp()
  where id = p_token_id and project_id = p_project and revoked_at is null;
  return found;
end;
$$;

create function public.register_ingested_evaluation(
  p_token text,
  p_group_id uuid,
  p_ingestion_id text,
  p_repetition integer,
  p_attempt integer,
  p_generation_id text,
  p_generation_sha256 text,
  p_previous_run_id uuid,
  p_started_at timestamptz,
  p_finished_at timestamptz,
  p_metrics jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token public.ingestion_tokens%rowtype;
  v_run uuid;
  v_fingerprint text;
  v_duplicate boolean;
begin
  if p_token is null or p_token !~ '^dxcel_[0-9a-f]{64}$' then
    raise exception 'Invalid registration token' using errcode = '28000';
  end if;

  select * into v_token from public.ingestion_tokens
  where token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex');
  if not found then
    raise exception 'Invalid registration token' using errcode = '28000';
  end if;

  perform 1 from public.projects where id = v_token.project_id and archived_at is null for update;
  if not found or not exists (
    select 1 from public.ingestion_tokens t join public.project_members m
      on m.project_id = t.project_id and m.user_id = t.created_by
    where t.id = v_token.id and t.revoked_at is null and t.expires_at > clock_timestamp()
      and m.role in ('owner', 'editor')
  ) then
    raise exception 'Invalid registration token' using errcode = '28000';
  end if;

  if p_generation_id is null or p_generation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
     or p_generation_sha256 is null or p_generation_sha256 !~ '^[0-9a-f]{64}$'
     or p_ingestion_id is null or p_ingestion_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
     or p_started_at is null or p_finished_at is null or p_finished_at < p_started_at then
    raise exception 'Invalid evaluation identity or timestamps' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.run_groups where id = p_group_id and project_id = v_token.project_id
  ) then
    raise exception 'Project access denied' using errcode = '42501';
  end if;

  v_fingerprint := p_generation_id || ':' || p_generation_sha256;
  if exists (
    select 1 from public.generation_outputs
    where project_id = v_token.project_id
      and left(fingerprint, -65) = p_generation_id and fingerprint <> v_fingerprint
  ) then
    raise exception 'Generation ID conflict' using errcode = '23505';
  end if;

  if p_previous_run_id is not null and not exists (
    select 1 from public.runs r join public.generation_outputs o
      on o.id = r.generation_output_id and o.project_id = r.project_id
    where r.id = p_previous_run_id and r.project_id = v_token.project_id
      and o.fingerprint = v_fingerprint
  ) then
    raise exception 'Previous run must use the same generation' using errcode = '23514';
  end if;

  select exists (
    select 1 from public.runs where project_id = v_token.project_id and ingestion_id = p_ingestion_id
  ) into v_duplicate;
  v_run := private.record_run_for_project(
    p_project => v_token.project_id,
    p_group => p_group_id,
    p_ingestion_id => p_ingestion_id,
    p_repetition => p_repetition,
    p_attempt => p_attempt,
    p_status => 'succeeded',
    p_fingerprint => v_fingerprint,
    p_metrics => p_metrics,
    p_previous => p_previous_run_id,
    p_started_at => p_started_at,
    p_finished_at => p_finished_at
  );
  if not v_duplicate then
    insert into public.audit_events(project_id, actor_id, entity_type, entity_id, action, details)
    values (v_token.project_id, v_token.created_by, 'runs', v_run::text, 'token_registration',
      jsonb_build_object('token_id', v_token.id));
  end if;
  return jsonb_build_object('run_id', v_run, 'duplicate', v_duplicate);
end;
$$;

revoke execute on function public.issue_ingestion_token(uuid, text, timestamptz)
  from public, anon, authenticated, service_role;
revoke execute on function public.revoke_ingestion_token(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke execute on function public.register_ingested_evaluation(text, uuid, text, integer, integer, text, text, uuid, timestamptz, timestamptz, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.issue_ingestion_token(uuid, text, timestamptz) to authenticated;
grant execute on function public.revoke_ingestion_token(uuid, uuid) to authenticated;
grant execute on function public.register_ingested_evaluation(text, uuid, text, integer, integer, text, text, uuid, timestamptz, timestamptz, jsonb) to service_role;
