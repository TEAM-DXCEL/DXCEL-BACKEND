begin;
select plan(12);

create temporary table projected_runs as
select private.project_comparison_runs_v2('[
  {"id":"primary","source_run_id":null,"source_run_id_missing_reason":"original ID not stored","parent_dp_generation_id":"shared-parent","parent_generation_id":null,"counts_as_new_dp_generation":true,"post_processing_only":false,"raw_data":"must not be exposed","metrics":[{"key":"zero","value":0,"status":"measured"},{"key":"missing","value":null,"status":"not_computed","missing_reason":"not stored"}]},
  {"id":"restored","parent_dp_generation_id":"shared-parent","parent_generation_id":"primary","counts_as_new_dp_generation":false,"post_processing_only":true,"metrics":[]},
  {"id":"legacy","metrics":[]}
]'::jsonb) as value;

select is(jsonb_array_length(value), 3, 'Projection preserves output count') from projected_runs;
select is(value #> '{0,source_run_id}', 'null'::jsonb, 'Unknown original ID stays null') from projected_runs;
select is(value #>> '{0,source_run_id_missing_reason}', 'original ID not stored', 'Unknown ID reason is retained') from projected_runs;
select is(value #> '{0,parent_generation_id}', 'null'::jsonb, 'Primary parent link stays explicit null') from projected_runs;
select is(value #> '{0,counts_as_new_dp_generation}', 'true'::jsonb, 'Primary counts as one DP generation') from projected_runs;
select is(value #> '{1,counts_as_new_dp_generation}', 'false'::jsonb, 'Restoration does not add a DP generation') from projected_runs;
select is(value #>> '{1,parent_generation_id}', 'primary', 'Restoration links to the primary output') from projected_runs;
select is(value #> '{1,post_processing_only}', 'true'::jsonb, 'Post processing flag is retained') from projected_runs;
select ok(not (value -> 2 ? 'counts_as_new_dp_generation'), 'Unknown legacy generation flags remain absent') from projected_runs;
select is(value #> '{0,metrics,0,value}', '0'::jsonb, 'Measured zero remains zero') from projected_runs;
select is(value #> '{0,metrics,1,value}', 'null'::jsonb, 'Missing metric stays null') from projected_runs;
select ok(not (value -> 0 ? 'raw_data'), 'Unapproved source fields are not projected') from projected_runs;

select * from finish();
rollback;
