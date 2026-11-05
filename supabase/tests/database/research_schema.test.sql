begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into auth.users(id, email) values
 ('00000000-0000-0000-0000-000000000001', 'owner@example.invalid'),
 ('00000000-0000-0000-0000-000000000002', 'viewer@example.invalid'),
 ('00000000-0000-0000-0000-000000000003', 'editor@example.invalid'),
 ('00000000-0000-0000-0000-000000000004', 'other@example.invalid');
create temporary table fixtures(name text primary key, id uuid not null);
grant all on fixtures to authenticated;
create function pg_temp.f(n text) returns uuid language sql as $$ select id from fixtures where name = n $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
insert into fixtures values ('other_project', public.create_project('Other project'));
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
insert into fixtures values ('project', public.create_project('Research project'));
select is((select count(*) from public.projects), 1::bigint, 'RLS only reveals the current member project');
select throws_ok(format('select public.set_project_member(%L, %L, ''owner'')', pg_temp.f('other_project'), '00000000-0000-0000-0000-000000000001'), '42501', 'Project access denied', 'Cannot claim another project');
select lives_ok(format('select public.set_project_member(%L, %L, ''viewer'')', pg_temp.f('project'), '00000000-0000-0000-0000-000000000002'), 'Owner adds viewer');
select lives_ok(format('select public.set_project_member(%L, %L, ''editor'')', pg_temp.f('project'), '00000000-0000-0000-0000-000000000003'), 'Owner adds editor');
select throws_ok(format('select public.set_project_member(%L, %L, ''viewer'')', pg_temp.f('project'), '00000000-0000-0000-0000-000000000001'), '23514', 'The last owner cannot be removed or demoted', 'Last owner demotion rejected');
select throws_ok(format('select public.set_project_member(%L, %L, null)', pg_temp.f('project'), '00000000-0000-0000-0000-000000000001'), '23514', 'The last owner cannot be removed or demoted', 'Last owner deletion rejected');
select throws_ok('update public.project_members set role = ''owner''', '42501', 'permission denied for table project_members', 'Direct membership mutation rejected');
select throws_ok('select token_hash from public.ingestion_tokens', '42501', 'permission denied for table ingestion_tokens', 'Token hash is not exposed');
insert into fixtures values ('experiment', public.create_experiment(pg_temp.f('project'), 1, 'Experiment', 'Hypothesis', 'Initial design', 'Initial reason', 'Evaluation plan'));
insert into fixtures select 'revision', current_revision_id from public.experiments where id = pg_temp.f('experiment');
select throws_like(format('select public.create_experiment(%L, 1, ''Duplicate'', ''H'', ''C'', ''R'', ''P'')', pg_temp.f('project')), '%duplicate key%', 'Experiment number unique per project');
select throws_ok(format('select public.revise_experiment(%L, %L, 0, ''H'', ''C'', ''R'', ''P'')', pg_temp.f('project'), pg_temp.f('experiment')), '40001', 'Revision conflict', 'Stale design revision rejected');
insert into fixtures values ('metric', public.define_metric(pg_temp.f('project'), 'Utility', 1, 'ratio', 'higher'));
insert into fixtures values ('optional_metric', public.define_metric(pg_temp.f('project'), 'Optional', 1, 'ratio', 'lower'));
insert into fixtures values ('context', public.create_comparison_context(pg_temp.f('project'), 'Context', 'synthetic-v1', 'split-v1', 'eval-v1', 10,
  jsonb_build_array(jsonb_build_object('metric_id', pg_temp.f('metric')), jsonb_build_object('metric_id', pg_temp.f('optional_metric'), 'required', false))));
insert into fixtures values ('group', public.create_run_group(pg_temp.f('project'), pg_temp.f('experiment'), pg_temp.f('revision'), pg_temp.f('context'), 2));
insert into fixtures values ('run1', public.record_run(pg_temp.f('project'), pg_temp.f('group'), 'registration-1', 1, 1, 'succeeded', 'output-1',
  jsonb_build_array(jsonb_build_object('metric_id', pg_temp.f('metric'), 'state', 'measured', 'value', 0.5))));
select is(public.record_run(pg_temp.f('project'), pg_temp.f('group'), 'registration-1', 1, 1, 'succeeded', 'output-1',
  jsonb_build_array(jsonb_build_object('metric_id', pg_temp.f('metric'), 'state', 'measured', 'value', 0.5))), pg_temp.f('run1'), 'Same registration content returns same ID');
select throws_ok(format('select public.record_run(%L, %L, ''registration-1'', 1, 1, ''succeeded'', ''changed-output'', ''[]'')', pg_temp.f('project'), pg_temp.f('group')), '23505', 'Ingestion ID conflict', 'Changed content conflicts with registration ID');
select throws_like(format('select public.record_run(%L, %L, ''bad-infinity'', 2, 1, ''succeeded'', ''output-bad'', %L)', pg_temp.f('project'), pg_temp.f('group'), jsonb_build_array(jsonb_build_object('metric_id', pg_temp.f('metric'), 'state', 'measured', 'value', 'Infinity'))), '%check constraint%', 'Infinity rejected');
select throws_like(format('select public.record_run(%L, %L, ''bad-nan'', 2, 1, ''succeeded'', ''output-bad'', %L)', pg_temp.f('project'), pg_temp.f('group'), jsonb_build_array(jsonb_build_object('metric_id', pg_temp.f('metric'), 'state', 'measured', 'value', 'NaN'))), '%check constraint%', 'NaN rejected');
select is((select count(*) from public.runs where ingestion_id like 'bad-%'), 0::bigint, 'Metric failure rolls back entire run');
select is((select count(*) from public.generation_outputs where fingerprint = 'output-bad'), 0::bigint, 'Metric failure rolls back output insert too');
select throws_like(format('select public.record_run(%L, %L, ''bad-missing'', 2, 1, ''succeeded'', ''output-bad'', %L)', pg_temp.f('project'), pg_temp.f('group'), jsonb_build_array(jsonb_build_object('metric_id', pg_temp.f('metric'), 'state', 'missing'))), '%check constraint%', 'Missing metric requires reason');
insert into fixtures values ('run2', public.record_run(pg_temp.f('project'), pg_temp.f('group'), 'registration-2', 2, 1, 'succeeded', 'output-2',
  jsonb_build_array(jsonb_build_object('metric_id', pg_temp.f('metric'), 'state', 'measured', 'value', 0.7),
    jsonb_build_object('metric_id', pg_temp.f('optional_metric'), 'state', 'missing', 'reason', 'Unavailable'))));
select throws_ok(format('select public.finalize_run_group(%L, %L, %L, ''[]'', ''Incomplete'')', pg_temp.f('project'), pg_temp.f('group'), jsonb_build_array(jsonb_build_object('repetition', 1, 'run_id', pg_temp.f('run1')))), '23514', 'Every repetition needs a selection or exclusion, with at least one selection', 'Cannot finalize incomplete repetitions');
select is((select count(*) from public.run_group_selections), 0::bigint, 'Failed finalization rolls back selections');
select lives_ok(format('select public.finalize_run_group(%L, %L, %L, ''[]'', ''Reviewed'')', pg_temp.f('project'), pg_temp.f('group'), jsonb_build_array(jsonb_build_object('repetition', 1, 'run_id', pg_temp.f('run1')), jsonb_build_object('repetition', 2, 'run_id', pg_temp.f('run2')))), 'Complete valid group finalized');
select cmp_ok(abs((select mean from public.run_group_metric_summaries where metric_definition_id = pg_temp.f('metric')) - 0.6), '<', 0.00000001::float8, 'Mean uses finalized selections');
select is((select sample_count from public.run_group_metric_summaries where metric_definition_id = pg_temp.f('metric')), 2::bigint, 'Two independent samples counted');
select cmp_ok(abs((select stddev from public.run_group_metric_summaries where metric_definition_id = pg_temp.f('metric')) - sqrt(0.02::float8)), '<', 0.00000001::float8, 'Sample standard deviation used');
select is((select unavailable_count from public.run_group_metric_summaries where metric_definition_id = pg_temp.f('optional_metric')), 2::bigint, 'Omitted and explicitly missing optional metrics both count as unavailable');
select throws_ok(format('select public.record_run(%L, %L, ''late-run'', 1, 2, ''failed'', null, ''[]'')', pg_temp.f('project'), pg_temp.f('group')), '23514', 'Invalid or finalized group', 'Cannot append a new result to finalized group');
select lives_ok(format('select public.set_representative_result(%L, %L, %L, ''Reviewed representative'')', pg_temp.f('project'), pg_temp.f('experiment'), pg_temp.f('group')), 'Finalized group can become representative');
insert into fixtures values ('baseline1', public.create_baseline_version(pg_temp.f('project'), 'Reference', 'internal', 'Initial reference', pg_temp.f('group')));
insert into fixtures values ('baseline2', public.create_baseline_version(pg_temp.f('project'), 'Reference', 'internal', 'Confirmed reference', pg_temp.f('group')));
select is((select previous_baseline_id from public.baseline_versions where id = pg_temp.f('baseline2')), pg_temp.f('baseline1'), 'New baseline preserves prior version');
select is((select count(*) from public.baseline_versions), 2::bigint, 'Both baseline versions retained');
insert into fixtures values ('note', public.create_note(pg_temp.f('project'), 'Initial observation', 'Initial note', pg_temp.f('experiment')));
select is(public.revise_note(pg_temp.f('project'), pg_temp.f('note'), 1, 'Updated observation', 'Clarification'), 2, 'Note revision appended');
select throws_ok(format('select public.revise_note(%L, %L, 1, ''Stale edit'', ''Reason'')', pg_temp.f('project'), pg_temp.f('note')), '40001', 'Revision conflict', 'Concurrent stale note edit rejected');
select is((select count(*) from public.note_revisions), 2::bigint, 'Prior note body retained');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
select is((select count(*) from public.experiments), 1::bigint, 'Viewer can read project experiment');
select throws_ok(format('select public.create_experiment(%L, 2, ''X'', ''H'', ''C'', ''R'', ''P'')', pg_temp.f('project')), '42501', 'Project access denied', 'Viewer cannot create experiment');
select throws_ok(format('select public.set_project_member(%L, %L, ''owner'')', pg_temp.f('project'), '00000000-0000-0000-0000-000000000002'), '42501', 'Project access denied', 'Viewer cannot escalate role');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
select throws_ok(format('select public.set_project_member(%L, %L, ''owner'')', pg_temp.f('project'), '00000000-0000-0000-0000-000000000003'), '42501', 'Project access denied', 'Editor cannot escalate role');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
select is((select count(*) from public.experiments), 0::bigint, 'Other project member cannot read experiments');
select is((select count(*) from public.run_group_metric_summaries), 0::bigint, 'Aggregation view respects RLS');
select throws_ok(format('select public.revise_note(%L, %L, 2, ''Attack'', ''Reason'')', pg_temp.f('project'), pg_temp.f('note')), '42501', 'Project access denied', 'Other project cannot edit notes');

reset role;
select throws_ok(format('update public.runs set status = ''failed'' where id = %L', pg_temp.f('run1')), '23514', 'Historical records cannot be updated or deleted', 'DB trigger protects historical results even for privileged SQL');
select throws_ok(format('delete from public.run_group_selections where group_id = %L', pg_temp.f('group')), '23514', 'Group is not editable', 'DB trigger protects finalized selections');
select throws_ok(format('update public.experiments set number = 99 where id = %L', pg_temp.f('experiment')), '23514', 'Experiment identity and ancestry cannot change', 'Experiment number cannot change');
select throws_like(format('insert into public.notes(project_id, experiment_id, created_by) values (%L, %L, %L)', pg_temp.f('other_project'), pg_temp.f('experiment'), '00000000-0000-0000-0000-000000000004'), '%foreign key constraint%', 'Composite FK blocks cross-project links');
select is((select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity), 19::bigint, 'All 19 domain tables have RLS');
select ok(not exists(select 1 from public.audit_events where reason like '%token_hash%'), 'Audit does not copy token hashes');
set local role anon;
select throws_ok('select * from public.projects', '42501', 'permission denied for table projects', 'Anonymous reads denied');
select throws_ok('select public.create_project(''Anonymous'')', '42501', 'permission denied for function create_project', 'Anonymous RPC execution denied');
reset role;
select * from finish();
rollback;
