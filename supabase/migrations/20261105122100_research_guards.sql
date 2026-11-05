create function private.member_role(p_project uuid)
returns public.project_role language sql stable security definer set search_path = '' as $$
  select role from public.project_members where project_id = p_project and user_id = (select auth.uid())
$$;
create function private.require_role(p_project uuid, p_roles public.project_role[])
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not coalesce(private.member_role(p_project) = any(p_roles), false) then
    raise exception 'Project access denied' using errcode = '42501';
  end if;
  perform 1 from public.projects where id = p_project and archived_at is null for update;
  if not found or not coalesce(private.member_role(p_project) = any(p_roles), false) then
    raise exception 'Project access denied' using errcode = '42501';
  end if;
end $$;
create function private.immutable_record()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'Historical records cannot be updated or deleted' using errcode = '23514';
end $$;
create function private.guard_member()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and (new.project_id, new.user_id) is distinct from (old.project_id, old.user_id) then
    raise exception 'Membership identity cannot change' using errcode = '23514';
  end if;
  perform 1 from public.projects where id = old.project_id for update;
  if old.role = 'owner' and (tg_op = 'DELETE' or new.role <> 'owner')
    and not exists (select 1 from public.project_members where project_id = old.project_id and user_id <> old.user_id and role = 'owner') then
    raise exception 'The last owner cannot be removed or demoted' using errcode = '23514';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
create trigger guard_member before update or delete on public.project_members for each row execute function private.guard_member();

create function private.guard_experiment()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (new.project_id, new.id, new.number, new.created_by, new.created_at, new.previous_experiment_id)
    is distinct from (old.project_id, old.id, old.number, old.created_by, old.created_at, old.previous_experiment_id) then
    raise exception 'Experiment identity and ancestry cannot change' using errcode = '23514';
  end if;
  if new.representative_group_id is not null and new.representative_group_id is distinct from old.representative_group_id
    and not exists (select 1 from public.run_groups where project_id = new.project_id and id = new.representative_group_id and state = 'finalized') then
    raise exception 'Representative result must be finalized' using errcode = '23514';
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger guard_experiment before update on public.experiments for each row execute function private.guard_experiment();
create trigger prevent_experiment_delete before delete on public.experiments for each row execute function private.immutable_record();
create trigger prevent_project_delete before delete on public.projects for each row execute function private.immutable_record();

create function private.guard_group()
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
create trigger guard_group before insert or update on public.run_groups for each row execute function private.guard_group();
create trigger prevent_group_delete before delete on public.run_groups for each row execute function private.immutable_record();

create function private.guard_group_child()
returns trigger language plpgsql set search_path = '' as $$
declare row_data jsonb; p uuid; g uuid; slot integer; parent public.run_groups; r public.runs;
begin
  row_data := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  p := (row_data ->> 'project_id')::uuid;
  g := (row_data ->> 'group_id')::uuid;
  select * into parent from public.run_groups where project_id = p and id = g for update;
  if not found or parent.state <> 'draft' then raise exception 'Group is not editable' using errcode = '23514'; end if;
  if tg_op = 'UPDATE' then raise exception 'Replace draft selections instead of updating them' using errcode = '23514'; end if;
  if tg_op = 'DELETE' then return old; end if;
  slot := (row_data ->> 'repetition')::integer;
  if slot > parent.expected_repetitions then raise exception 'Repetition is outside the group plan' using errcode = '23514'; end if;
  if tg_table_name = 'runs' then
    if new.config <> parent.config then raise exception 'Run config differs from group plan' using errcode = '23514'; end if;
  elsif tg_table_name = 'run_group_selections' then
    if exists (select 1 from public.run_group_exclusions where project_id = p and group_id = g and repetition = slot) then
      raise exception 'Repetition already excluded' using errcode = '23514';
    end if;
    select * into r from public.runs where project_id = p and id = new.run_id;
    if not found or r.repetition <> slot then raise exception 'Selected repetition does not match' using errcode = '23514'; end if;
  else
    if exists (select 1 from public.run_group_selections where project_id = p and group_id = g and repetition = slot) then
      raise exception 'Repetition already selected' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
create trigger guard_run_insert before insert on public.runs for each row execute function private.guard_group_child();
create trigger guard_selection before insert or update or delete on public.run_group_selections for each row execute function private.guard_group_child();
create trigger guard_exclusion before insert or update or delete on public.run_group_exclusions for each row execute function private.guard_group_child();

create function private.guard_context_metric()
returns trigger language plpgsql set search_path = '' as $$
begin
  perform 1 from public.comparison_contexts where project_id = new.project_id and id = new.context_id for update;
  if exists (select 1 from public.run_groups where project_id = new.project_id and context_id = new.context_id) then
    raise exception 'Metric set is frozen once a group references its context' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger guard_context_metric before insert on public.context_metrics for each row execute function private.guard_context_metric();
create function private.guard_metric_insert()
returns trigger language plpgsql set search_path = '' as $$
declare g uuid; s public.group_state;
begin
  select group_id into g from public.runs where project_id = new.project_id and id = new.run_id;
  select state into s from public.run_groups where project_id = new.project_id and id = g for update;
  if s is distinct from 'draft' then raise exception 'Finalized metrics cannot change' using errcode = '23514'; end if;
  return new;
end $$;
create trigger guard_metric before insert on public.run_metrics for each row execute function private.guard_metric_insert();
create function private.guard_baseline()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.kind = 'internal' and not exists (select 1 from public.run_groups where project_id = new.project_id and id = new.group_id and state = 'finalized') then
    raise exception 'Baseline result must be finalized' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger guard_baseline before insert on public.baseline_versions for each row execute function private.guard_baseline();
create function private.guard_reported_metric()
returns trigger language plpgsql set search_path = '' as $$
declare b public.baseline_versions;
begin
  select * into b from public.baseline_versions where project_id = new.project_id and id = new.baseline_id;
  if b.kind is distinct from 'reported' or b.context_id is not null and not exists (
    select 1 from public.context_metrics where project_id = b.project_id and context_id = b.context_id and metric_definition_id = new.metric_definition_id
  ) then raise exception 'Reported metric does not belong to the baseline context' using errcode = '23514'; end if;
  return new;
end $$;
create trigger guard_reported_metric before insert on public.baseline_reported_metrics for each row execute function private.guard_reported_metric();

create function private.audit_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare d jsonb;
begin
  d := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  insert into public.audit_events(project_id, actor_id, entity_type, entity_id, action, reason)
    values (case when tg_table_name = 'projects' then (d ->> 'id')::uuid else (d ->> 'project_id')::uuid end,
      auth.uid(), tg_table_name, coalesce(d ->> 'id', d ->> 'user_id', d ->> 'run_id', d ->> 'group_id', d ->> 'context_id'),
      lower(tg_op), coalesce(d ->> 'change_reason', d ->> 'reason', nullif(current_setting('dxcel.change_reason', true), '')));
  return null;
end $$;

do $$ declare t text; begin
  foreach t in array array['experiment_revisions','comparison_contexts','metric_definitions','context_metrics',
    'generation_outputs','runs','run_metrics','baseline_versions','baseline_reported_metrics','note_revisions','audit_events'] loop
    execute format('create trigger immutable_record before update or delete on public.%I for each row execute function private.immutable_record()', t);
  end loop;
  foreach t in array array['projects','project_members','experiments','experiment_revisions','comparison_contexts',
    'metric_definitions','context_metrics','run_groups','generation_outputs','runs','run_metrics','run_group_selections',
    'run_group_exclusions','baseline_versions','baseline_reported_metrics','notes','note_revisions','ingestion_tokens'] loop
    execute format('create trigger audit_change after insert or update or delete on public.%I for each row execute function private.audit_change()', t);
  end loop;
  foreach t in array array['projects','project_members','experiments','experiment_revisions','comparison_contexts',
    'metric_definitions','context_metrics','run_groups','generation_outputs','runs','run_metrics','run_group_selections',
    'run_group_exclusions','baseline_versions','baseline_reported_metrics','notes','note_revisions','ingestion_tokens','audit_events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated, service_role', t);
    if t = 'projects' then
      execute 'create policy member_read on public.projects for select to authenticated using (private.member_role(id) is not null)';
    elsif t = 'ingestion_tokens' then
      execute 'create policy owner_read on public.ingestion_tokens for select to authenticated using (private.member_role(project_id) = ''owner'')';
    else
      execute format('create policy member_read on public.%I for select to authenticated using (private.member_role(project_id) is not null)', t);
    end if;
    if t <> 'ingestion_tokens' then execute format('grant select on public.%I to authenticated', t); end if;
  end loop;
end $$;
grant select (id, project_id, name, created_by, created_at, expires_at, revoked_at) on public.ingestion_tokens to authenticated;
grant usage on schema private to authenticated;
revoke all on all functions in schema private from public, anon, authenticated, service_role;
grant execute on function private.member_role(uuid) to authenticated;
