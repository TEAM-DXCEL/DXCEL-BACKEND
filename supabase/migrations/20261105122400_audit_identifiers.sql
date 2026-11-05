create or replace function private.audit_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare d jsonb; detail jsonb;
begin
  d := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  detail := jsonb_strip_nulls(jsonb_build_object('metric_definition_id', d -> 'metric_definition_id', 'repetition', d -> 'repetition', 'version', d -> 'version'));
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
      auth.uid(), tg_table_name, coalesce(d ->> 'id', d ->> 'user_id', d ->> 'run_id', d ->> 'group_id', d ->> 'context_id', d ->> 'baseline_id'),
      lower(tg_op), coalesce(d ->> 'change_reason', d ->> 'reason', nullif(current_setting('dxcel.change_reason', true), '')), detail);
  return null;
end $$;

create or replace function private.require_role(p_project uuid, p_roles public.project_role[])
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not coalesce(private.member_role(p_project) = any(p_roles), false) then
    raise exception 'Project access denied' using errcode = '42501';
  end if;
  perform 1 from public.projects where id = p_project and archived_at is null for update;
  if not found or not coalesce(private.member_role(p_project) = any(p_roles), false) then
    raise exception 'Project access denied' using errcode = '42501';
  end if;
  perform set_config('dxcel.change_reason', '', true);
end $$;
