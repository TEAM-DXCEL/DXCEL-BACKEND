create function private.project_comparison_runs_v2(runs jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', run.value -> 'id',
    'experiment_id', run.value -> 'experiment_id',
    'dataset', run.value -> 'dataset',
    'condition', run.value -> 'condition',
    'repetition_index', run.value -> 'repetition_index',
    'source_run_id', run.value -> 'source_run_id',
    'parent_dp_generation_id', run.value -> 'parent_dp_generation_id',
    'generation_status', run.value -> 'generation_status',
    'synthetic_rows', run.value -> 'synthetic_rows',
    'evaluation_result_ref', run.value -> 'evaluation_result_ref',
    'dp', jsonb_build_object(
      'epsilon_upper_bound', run.value #> '{dp,epsilon_upper_bound}',
      'delta', run.value #> '{dp,delta}'
    ),
    'metrics', (
      select jsonb_agg(jsonb_build_object(
        'key', metric.value -> 'key',
        'value', metric.value -> 'value',
        'status', metric.value -> 'status',
        'missing_reason', metric.value -> 'missing_reason',
        'source_ref', metric.value -> 'source_ref',
        'valid_evaluation_replicates', metric.value -> 'valid_evaluation_replicates',
        'evaluation_replicate_values_missing_reason',
          metric.value -> 'evaluation_replicate_values_missing_reason'
      ) order by metric.ordinality)
      from jsonb_array_elements(run.value -> 'metrics') with ordinality metric
    )
  ) order by run.ordinality), '[]'::jsonb)
  from jsonb_array_elements(runs) with ordinality run;
$$;

create function private.project_comparison_summaries_v2(summaries jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    (summary.value - array['generation_values', 'provided_summary', 'provided_summary_missing_reason'])
    || jsonb_build_object('generation_values', (
      select jsonb_agg(jsonb_build_object(
        'generation_id', point.value -> 'generation_id',
        'value', point.value -> 'value'
      ) order by point.ordinality)
      from jsonb_array_elements(summary.value -> 'generation_values') with ordinality point
    ))
    order by summary.ordinality
  ), '[]'::jsonb)
  from jsonb_array_elements(summaries) with ordinality summary;
$$;

create function public.read_dashboard_comparison_release()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'baseline_catalog', jsonb_build_object(
      'schema_version', release.baseline_catalog -> 'schema_version',
      'kind', release.baseline_catalog -> 'kind',
      'metric_definitions', release.baseline_catalog -> 'metric_definitions',
      'native_diagnostic_metric_definitions',
        release.baseline_catalog -> 'native_diagnostic_metric_definitions',
      'baselines', (
        select jsonb_agg(
          (entry.value - array['runs', 'summaries', 'native_utility_diagnostic_summaries'])
          || jsonb_build_object(
            'runs', private.project_comparison_runs_v2(entry.value -> 'runs'),
            'summaries', private.project_comparison_summaries_v2(entry.value -> 'summaries'),
            'native_utility_diagnostic_summaries', case
              when jsonb_typeof(entry.value -> 'native_utility_diagnostic_summaries') = 'array'
              then (
                select jsonb_agg(native.value - 'generation_values' order by native.ordinality)
                from jsonb_array_elements(entry.value -> 'native_utility_diagnostic_summaries')
                  with ordinality native
              )
              else null
            end
          )
          order by entry.ordinality
        )
        from jsonb_array_elements(release.baseline_catalog -> 'baselines') with ordinality entry
      )
    ),
    'selected_delta', (
      release.selected_delta - array[
        'evaluation_groups', 'generation_runs', 'policy', 'schema_compatibility'
      ]
    ) || jsonb_build_object(
      'evaluation_groups', (
        select jsonb_agg(
          (entry.value - array['summaries', 'comparison_pairs'])
          || jsonb_build_object(
            'summaries', private.project_comparison_summaries_v2(entry.value -> 'summaries')
          )
          order by entry.ordinality
        )
        from jsonb_array_elements(release.selected_delta -> 'evaluation_groups')
          with ordinality entry
      ),
      'generation_runs', private.project_comparison_runs_v2(release.selected_delta -> 'generation_runs')
    )
  )
  from private.dashboard_comparison_releases release
  where release.is_current;
$$;

revoke all on function private.project_comparison_runs_v2(jsonb),
  private.project_comparison_summaries_v2(jsonb) from public, anon, authenticated;
revoke all on function public.read_dashboard_comparison_release() from public, anon, authenticated;
grant execute on function public.read_dashboard_comparison_release() to service_role;
