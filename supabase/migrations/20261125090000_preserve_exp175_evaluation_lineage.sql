create or replace function private.project_comparison_runs_v2(runs jsonb)
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
  ) || (
    select coalesce(jsonb_object_agg(metadata.key, metadata.value), '{}'::jsonb)
    from jsonb_each(run.value) metadata
    where metadata.key in (
      'source_run_id_missing_reason', 'parent_generation_id',
      'counts_as_new_dp_generation', 'post_processing_only',
      'condition_id', 'arm_id', 'decoder_id',
      'preprocessing_release_id', 'preprocessing_source_experiment_id',
      'independent_across_conditions', 'independence_limit',
      'source_evaluation_run_id', 'source_evaluation_run_id_missing_reason',
      'evaluation_attempt', 'evaluation_attempt_missing_reason'
    )
  ) order by run.ordinality), '[]'::jsonb)
  from jsonb_array_elements(runs) with ordinality run;
$$;

revoke all on function private.project_comparison_runs_v2(jsonb) from public, anon, authenticated;

refresh materialized view private.dashboard_comparison_release_projection;
