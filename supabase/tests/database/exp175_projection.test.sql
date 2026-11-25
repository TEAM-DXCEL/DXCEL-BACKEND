begin;
select plan(13);

create temporary table exp175_projected as
select private.project_comparison_runs_v2('[
  {"id":"exp175-output","condition_id":"F_RAG","arm_id":"PT_UNIF","decoder_id":"UNIF","preprocessing_release_id":"shared-release","preprocessing_source_experiment_id":"EXP-170","independent_across_conditions":false,"independence_limit":"conditions share preprocessing","source_evaluation_run_id":"exp175-evaluation","source_evaluation_run_id_missing_reason":null,"evaluation_attempt":null,"evaluation_attempt_missing_reason":"attempt not stored","private_payload":"exclude","metrics":[]},
  {"id":"legacy-output","metrics":[]}
]'::jsonb) as value;

select is(value #>> '{0,condition_id}', 'F_RAG', 'Condition remains distinct from arm') from exp175_projected;
select is(value #>> '{0,arm_id}', 'PT_UNIF', 'Arm is preserved') from exp175_projected;
select is(value #>> '{0,decoder_id}', 'UNIF', 'Decoder is preserved') from exp175_projected;
select is(value #>> '{0,preprocessing_release_id}', 'shared-release', 'Shared representation identity is preserved') from exp175_projected;
select is(value #>> '{0,preprocessing_source_experiment_id}', 'EXP-170', 'Representation source is preserved') from exp175_projected;
select is(value #> '{0,independent_across_conditions}', 'false'::jsonb, 'Shared conditions remain dependent') from exp175_projected;
select is(value #>> '{0,independence_limit}', 'conditions share preprocessing', 'Independence limitation is preserved') from exp175_projected;
select is(value #>> '{0,source_evaluation_run_id}', 'exp175-evaluation', 'Evaluation ID remains available') from exp175_projected;
select is(value #> '{0,source_evaluation_run_id_missing_reason}', 'null'::jsonb, 'Evaluation ID reason remains null') from exp175_projected;
select is(value #> '{0,evaluation_attempt}', 'null'::jsonb, 'Unknown attempt is never inferred as zero') from exp175_projected;
select is(value #>> '{0,evaluation_attempt_missing_reason}', 'attempt not stored', 'Attempt reason is preserved') from exp175_projected;
select ok(not (value -> 1 ? 'preprocessing_release_id'), 'Legacy representation identity is not invented') from exp175_projected;
select ok(not (value -> 0 ? 'private_payload'), 'Other source fields stay outside the projection') from exp175_projected;

select * from finish();
rollback;
