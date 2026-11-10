begin;
set local search_path = public, extensions;
select no_plan();
grant usage on schema extensions to service_role;

insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-000000000031', 'uploader-owner@example.invalid'),
  ('00000000-0000-0000-0000-000000000032', 'uploader-viewer@example.invalid');
create temporary table ingestion_fixture (key text primary key, value text not null);
grant all on ingestion_fixture to authenticated, service_role;
create function pg_temp.fixture(k text) returns text language sql as $$
  select value from ingestion_fixture where key = k
$$;
create function pg_temp.register_fixture(
  token text, ingestion text, generation text, digest text, metric uuid, attempt integer default 1,
  previous uuid default null, target uuid default null
) returns jsonb language sql as $$
  select public.register_ingested_evaluation(
    token, coalesce(target, pg_temp.fixture('group')::uuid), ingestion, 1, attempt,
    generation, digest, previous, '2026-11-10 00:00:00Z', '2026-11-10 00:01:00Z',
    jsonb_build_array(jsonb_build_object('metric_id', metric, 'state', 'measured', 'value', 0))
  )
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000031', true);
do $$
declare p uuid; q uuid; e uuid; f uuid; v uuid; w uuid; m uuid; n uuid; c uuid; d uuid; g uuid; h uuid;
begin
  p := public.create_project('Uploader fixture');
  q := public.create_project('Other uploader project');
  perform public.set_project_member(p, '00000000-0000-0000-0000-000000000032', 'viewer');
  e := public.create_experiment(p, 1, 'Experiment', 'H', 'C', 'R', 'P');
  f := public.create_experiment(q, 1, 'Experiment', 'H', 'C', 'R', 'P');
  select current_revision_id into v from public.experiments where id = e;
  select current_revision_id into w from public.experiments where id = f;
  m := public.define_metric(p, 'Metric', 1, 'ratio', 'higher');
  n := public.define_metric(q, 'Metric', 1, 'ratio', 'higher');
  c := public.create_comparison_context(p, 'Condition', 'dataset', 'split', 'eval-a', 10, jsonb_build_array(jsonb_build_object('metric_id', m)));
  d := public.create_comparison_context(q, 'Condition', 'dataset', 'split', 'eval-a', 10, jsonb_build_array(jsonb_build_object('metric_id', n)));
  g := public.create_run_group(p, e, v, c, 2);
  h := public.create_run_group(q, f, w, d, 2);
  insert into ingestion_fixture values ('project', p), ('group', g), ('metric', m), ('other_group', h);
end $$;
insert into ingestion_fixture
select item.key, item.value
from public.issue_ingestion_token(pg_temp.fixture('project')::uuid, 'Test token', now() + interval '1 day') t
cross join lateral (values ('token_id', t.token_id::text), ('token', t.token)) item(key, value);
select matches(pg_temp.fixture('token'), '^dxcel_[0-9a-f]{64}$', 'Owner can issue a registration-only token');
select throws_ok('select token_hash from public.ingestion_tokens', '42501', 'permission denied for table ingestion_tokens', 'Owner cannot read token hashes');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000032', true);
select throws_ok(
  $$select public.issue_ingestion_token(pg_temp.fixture('project')::uuid, 'Viewer', now() + interval '1 day')$$,
  '42501', 'Project access denied', 'Viewer cannot issue tokens'
);
select throws_ok(
  $$select public.revoke_ingestion_token(pg_temp.fixture('project')::uuid, pg_temp.fixture('token_id')::uuid)$$,
  '42501', 'Project access denied', 'Viewer cannot revoke tokens'
);
select ok(not has_function_privilege('anon', 'public.register_ingested_evaluation(text,uuid,text,integer,integer,text,text,uuid,timestamptz,timestamptz,jsonb)', 'EXECUTE'), 'Anon cannot bypass Edge validation');
select ok(not has_function_privilege('authenticated', 'public.register_ingested_evaluation(text,uuid,text,integer,integer,text,text,uuid,timestamptz,timestamptz,jsonb)', 'EXECUTE'), 'User cannot bypass Edge validation');

reset role;
select is(
  (select token_hash from public.ingestion_tokens where id = pg_temp.fixture('token_id')::uuid),
  encode(sha256(convert_to(pg_temp.fixture('token'), 'UTF8')), 'hex'),
  'Only the token digest is stored'
);
insert into public.ingestion_tokens (project_id, name, token_hash, created_by, created_at, expires_at)
values (pg_temp.fixture('project')::uuid, 'Expired fixture',
  encode(sha256(convert_to('dxcel_' || repeat('e', 64), 'UTF8')), 'hex'),
  '00000000-0000-0000-0000-000000000031', now() - interval '2 days', now() - interval '1 day');
set local role service_role;
select throws_ok(
  $$select pg_temp.register_fixture('dxcel_' || repeat('e', 64), 'expired-eval', 'generation-1', repeat('a', 64), pg_temp.fixture('metric')::uuid)$$,
  '28000', 'Invalid registration token', 'Expired token cannot register a result'
);
insert into ingestion_fixture
select 'first', pg_temp.register_fixture(pg_temp.fixture('token'), 'eval-1', 'generation-1', repeat('a', 64), pg_temp.fixture('metric')::uuid)::text;
select is((pg_temp.fixture('first')::jsonb ->> 'duplicate'), 'false', 'First registration creates a run');
select is(
  pg_temp.register_fixture(pg_temp.fixture('token'), 'eval-1', 'generation-1', repeat('a', 64), pg_temp.fixture('metric')::uuid),
  jsonb_build_object('run_id', pg_temp.fixture('first')::jsonb ->> 'run_id', 'duplicate', true),
  'Same registration returns the existing run'
);
select is(current_setting('request.jwt.claim.sub', true), '00000000-0000-0000-0000-000000000032', 'Uploader claim is restored');
select throws_ok(
  $$select pg_temp.register_fixture(pg_temp.fixture('token'), 'eval-1', 'generation-2', repeat('a', 64), pg_temp.fixture('metric')::uuid)$$,
  '23505', 'Ingestion ID conflict', 'Changed content with the same registration ID conflicts'
);
select throws_ok(
  $$select pg_temp.register_fixture(pg_temp.fixture('token'), 'eval-2', 'generation-1', repeat('b', 64), pg_temp.fixture('metric')::uuid, 2)$$,
  '23505', 'Generation ID conflict', 'Same generation ID with a different digest conflicts'
);
select throws_ok(
  $$select pg_temp.register_fixture(pg_temp.fixture('token'), 'eval-3', 'generation-1', repeat('a', 64), pg_temp.fixture('metric')::uuid, 2, null, pg_temp.fixture('other_group')::uuid)$$,
  '42501', 'Project access denied', 'Token cannot write to another project'
);
select throws_ok(
  $$select pg_temp.register_fixture('dxcel_' || repeat('f', 64), 'eval-4', 'generation-1', repeat('a', 64), pg_temp.fixture('metric')::uuid, 2)$$,
  '28000', 'Invalid registration token', 'Unknown token is rejected'
);
select throws_ok(
  $$select pg_temp.register_fixture(pg_temp.fixture('token'), 'eval-5', 'generation-1', repeat('a', 64), '00000000-0000-0000-0000-000000000099', 2)$$,
  '23514', 'Metric is outside comparison context', 'Unapproved metric is rejected'
);
insert into ingestion_fixture
select 'second', pg_temp.register_fixture(pg_temp.fixture('token'), 'eval-6', 'generation-1', repeat('a', 64), pg_temp.fixture('metric')::uuid, 2, (pg_temp.fixture('first')::jsonb ->> 'run_id')::uuid)::text;
insert into ingestion_fixture
select 'third', pg_temp.register_fixture(pg_temp.fixture('token'), 'eval-7', 'generation-2', repeat('a', 64), pg_temp.fixture('metric')::uuid, 3)::text;
reset role;
select is((select count(*) from public.runs where project_id = pg_temp.fixture('project')::uuid), 3::bigint, 'Only three unique accepted runs persist');
select is(
  (select generation_output_id from public.runs where ingestion_id = 'eval-1'),
  (select generation_output_id from public.runs where ingestion_id = 'eval-6'),
  'Re-evaluation retains the generation output'
);
select isnt(
  (select generation_output_id from public.runs where ingestion_id = 'eval-1'),
  (select generation_output_id from public.runs where ingestion_id = 'eval-7'),
  'Independent generations remain distinct when their byte hashes match'
);
select is(
  (select value from public.run_metrics where run_id = (pg_temp.fixture('first')::jsonb ->> 'run_id')::uuid),
  0::float8, 'Measured zero is stored'
);
select is(
  (select count(*) from public.audit_events where action = 'token_registration'
    and entity_id = pg_temp.fixture('first')::jsonb ->> 'run_id'
    and details ->> 'token_id' = pg_temp.fixture('token_id')),
  1::bigint, 'Registration audit retains only the token identifier once'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000031', true);
select ok(public.revoke_ingestion_token(pg_temp.fixture('project')::uuid, pg_temp.fixture('token_id')::uuid), 'Owner can revoke the token');
set local role service_role;
select throws_ok(
  $$select pg_temp.register_fixture(pg_temp.fixture('token'), 'eval-1', 'generation-1', repeat('a', 64), pg_temp.fixture('metric')::uuid)$$,
  '28000', 'Invalid registration token', 'Revoked token cannot replay a completed registration'
);
reset role;
select * from finish();
rollback;
