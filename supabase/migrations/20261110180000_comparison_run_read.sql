create function public.read_comparison_run(p_run_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r.id,
    'experimentNumber', e.number,
    'dataset', g.config ->> 'dataset',
    'arm', g.config ->> 'arm',
    'repetition', r.repetition,
    'attempt', r.attempt,
    'commonN', c.sample_size,
    'metrics', (
      select jsonb_agg(jsonb_build_object(
        'key', definition.key,
        'definition', definition.value - array['source', 'sourceField', 'aliases', 'aggregation'],
        'state', rm.state,
        'value', rm.value,
        'reason', rm.reason
      ) order by definition.key)
      from jsonb_each(c.evaluation_config -> 'metricDefinitions') as definition
      join public.metric_definitions md
        on md.project_id = c.project_id
        and md.name = definition.value ->> 'displayName'
        and md.version = 1
      join public.context_metrics cm
        on cm.project_id = c.project_id and cm.context_id = c.id and cm.metric_definition_id = md.id
      left join public.run_metrics rm
        on rm.project_id = r.project_id and rm.run_id = r.id and rm.metric_definition_id = md.id
    )
  )
  from public.runs r
  join public.run_groups g on g.project_id = r.project_id and g.id = r.group_id
  join public.experiments e on e.project_id = g.project_id and e.id = g.experiment_id
  join public.comparison_contexts c on c.project_id = r.project_id and c.id = r.context_id
  where r.id = p_run_id and r.status = 'succeeded' and e.archived_at is null;
$$;

revoke all on function public.read_comparison_run(uuid) from public, anon, authenticated;
grant execute on function public.read_comparison_run(uuid) to service_role;
