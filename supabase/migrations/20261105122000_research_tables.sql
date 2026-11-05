create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create type public.project_role as enum ('owner', 'editor', 'viewer');
create type public.run_status as enum ('queued', 'running', 'succeeded', 'failed', 'cancelled');
create type public.group_state as enum ('draft', 'finalized');
create type public.metric_state as enum ('measured', 'missing', 'error');
create type public.metric_direction as enum ('higher', 'lower', 'target');
create type public.baseline_kind as enum ('internal', 'reported');

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 200),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  archived_at timestamptz
);
create table public.project_members (
  project_id uuid not null references public.projects(id),
  user_id uuid not null references auth.users(id),
  role public.project_role not null,
  joined_at timestamptz not null default now(),
  primary key (project_id, user_id)
);
create index project_members_user_idx on public.project_members(user_id, project_id);

create table public.experiments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id),
  number integer not null check (number > 0),
  title text not null check (length(btrim(title)) between 1 and 300),
  owner_id uuid,
  previous_experiment_id uuid,
  current_revision_id uuid,
  representative_group_id uuid,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  unique (project_id, id),
  unique (project_id, number),
  foreign key (project_id, owner_id) references public.project_members(project_id, user_id),
  foreign key (project_id, previous_experiment_id) references public.experiments(project_id, id),
  check (previous_experiment_id is distinct from id)
);
create index experiments_updated_idx on public.experiments(project_id, updated_at desc, id desc);
create table public.experiment_revisions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null,
  experiment_id uuid not null,
  version integer not null check (version > 0),
  hypothesis text not null check (length(btrim(hypothesis)) between 1 and 20000),
  changes text not null check (length(btrim(changes)) between 1 and 20000),
  change_reason text not null check (length(btrim(change_reason)) between 1 and 20000),
  evaluation_plan text not null check (length(btrim(evaluation_plan)) between 1 and 20000),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (project_id, id),
  unique (project_id, experiment_id, id),
  unique (project_id, experiment_id, version),
  foreign key (project_id, experiment_id) references public.experiments(project_id, id)
);
alter table public.experiments add foreign key (project_id, id, current_revision_id)
  references public.experiment_revisions(project_id, experiment_id, id);

create table public.comparison_contexts (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id),
  name text not null check (length(btrim(name)) between 1 and 200),
  dataset_fingerprint text not null check (length(btrim(dataset_fingerprint)) between 1 and 256),
  split_fingerprint text not null check (length(btrim(split_fingerprint)) between 1 and 256),
  evaluation_version text not null check (length(btrim(evaluation_version)) between 1 and 256),
  evaluation_config jsonb not null default '{}' check (jsonb_typeof(evaluation_config) = 'object'),
  sample_size integer not null check (sample_size > 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (project_id, id)
);
create table public.metric_definitions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id),
  name text not null check (length(btrim(name)) between 1 and 200),
  version integer not null check (version > 0),
  unit text not null check (length(btrim(unit)) between 1 and 80),
  direction public.metric_direction not null,
  target double precision,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (project_id, id),
  unique (project_id, name, version),
  check ((direction = 'target') = (target is not null)),
  check (target is null or target > '-Infinity'::float8 and target < 'Infinity'::float8)
);
create table public.context_metrics (
  project_id uuid not null,
  context_id uuid not null,
  metric_definition_id uuid not null,
  required boolean not null default true,
  primary key (project_id, context_id, metric_definition_id),
  foreign key (project_id, context_id) references public.comparison_contexts(project_id, id),
  foreign key (project_id, metric_definition_id) references public.metric_definitions(project_id, id)
);
create table public.run_groups (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null,
  experiment_id uuid not null,
  revision_id uuid not null,
  context_id uuid not null,
  config jsonb not null default '{}' check (jsonb_typeof(config) = 'object'),
  expected_repetitions integer not null check (expected_repetitions between 1 and 10000),
  state public.group_state not null default 'draft',
  finalized_at timestamptz,
  finalized_by uuid references auth.users(id),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (project_id, id),
  unique (project_id, experiment_id, id),
  unique (project_id, id, context_id),
  foreign key (project_id, experiment_id, revision_id) references public.experiment_revisions(project_id, experiment_id, id),
  foreign key (project_id, context_id) references public.comparison_contexts(project_id, id),
  check ((state = 'finalized') = (finalized_at is not null and finalized_by is not null)),
  check (state = 'finalized' or finalized_at is null and finalized_by is null)
);
alter table public.experiments add foreign key (project_id, id, representative_group_id)
  references public.run_groups(project_id, experiment_id, id);
create table public.generation_outputs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id),
  fingerprint text not null check (length(btrim(fingerprint)) between 1 and 256),
  created_at timestamptz not null default now(),
  unique (project_id, id),
  unique (project_id, fingerprint)
);
create table public.runs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null,
  group_id uuid not null,
  context_id uuid not null,
  ingestion_id text not null check (length(btrim(ingestion_id)) between 1 and 200),
  request_payload jsonb not null check (jsonb_typeof(request_payload) = 'object' and octet_length(request_payload::text) <= 262144),
  repetition integer not null check (repetition > 0),
  attempt integer not null check (attempt > 0),
  generation_output_id uuid,
  previous_run_id uuid,
  status public.run_status not null,
  config jsonb not null check (jsonb_typeof(config) = 'object'),
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  unique (project_id, id),
  unique (project_id, id, context_id),
  unique (project_id, ingestion_id),
  unique (project_id, group_id, repetition, attempt),
  foreign key (project_id, group_id, context_id) references public.run_groups(project_id, id, context_id),
  foreign key (project_id, generation_output_id) references public.generation_outputs(project_id, id),
  foreign key (project_id, previous_run_id) references public.runs(project_id, id),
  check (previous_run_id is distinct from id),
  check (status <> 'succeeded' or generation_output_id is not null),
  check ((status in ('succeeded', 'failed', 'cancelled')) = (finished_at is not null)),
  check (started_at is null or finished_at is null or started_at <= finished_at)
);
create index runs_group_idx on public.runs(project_id, group_id, created_at desc, id desc);
create table public.run_metrics (
  project_id uuid not null,
  run_id uuid not null,
  context_id uuid not null,
  metric_definition_id uuid not null,
  state public.metric_state not null,
  value double precision,
  reason text,
  primary key (project_id, run_id, metric_definition_id),
  foreign key (project_id, run_id, context_id) references public.runs(project_id, id, context_id),
  foreign key (project_id, context_id, metric_definition_id) references public.context_metrics(project_id, context_id, metric_definition_id),
  check ((state = 'measured' and value is not null and reason is null)
    or (state in ('missing', 'error') and value is null and reason is not null and length(btrim(reason)) > 0)),
  check (value is null or value > '-Infinity'::float8 and value < 'Infinity'::float8)
);
create table public.run_group_selections (
  project_id uuid not null,
  group_id uuid not null,
  repetition integer not null check (repetition > 0),
  run_id uuid not null,
  primary key (project_id, group_id, repetition),
  unique (project_id, group_id, run_id),
  foreign key (project_id, group_id) references public.run_groups(project_id, id),
  foreign key (project_id, run_id) references public.runs(project_id, id)
);
create table public.run_group_exclusions (
  project_id uuid not null,
  group_id uuid not null,
  repetition integer not null check (repetition > 0),
  reason text not null check (length(btrim(reason)) between 1 and 20000),
  primary key (project_id, group_id, repetition),
  foreign key (project_id, group_id) references public.run_groups(project_id, id)
);
create table public.baseline_versions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id),
  name text not null check (length(btrim(name)) between 1 and 200),
  version integer not null check (version > 0),
  kind public.baseline_kind not null,
  group_id uuid,
  context_id uuid,
  source text,
  reason text not null check (length(btrim(reason)) between 1 and 20000),
  previous_baseline_id uuid,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (project_id, id),
  unique (project_id, name, version),
  foreign key (project_id, group_id, context_id) references public.run_groups(project_id, id, context_id),
  foreign key (project_id, context_id) references public.comparison_contexts(project_id, id),
  foreign key (project_id, previous_baseline_id) references public.baseline_versions(project_id, id),
  check (previous_baseline_id is distinct from id),
  check ((kind = 'internal' and group_id is not null and context_id is not null and source is null)
    or (kind = 'reported' and group_id is null and source is not null and length(btrim(source)) > 0))
);
create table public.baseline_reported_metrics (
  project_id uuid not null,
  baseline_id uuid not null,
  metric_definition_id uuid not null,
  mean double precision not null check (mean > '-Infinity'::float8 and mean < 'Infinity'::float8),
  stddev double precision check (stddev >= 0 and stddev < 'Infinity'::float8),
  sample_count integer check (sample_count > 0),
  primary key (project_id, baseline_id, metric_definition_id),
  foreign key (project_id, baseline_id) references public.baseline_versions(project_id, id),
  foreign key (project_id, metric_definition_id) references public.metric_definitions(project_id, id),
  check (sample_count is distinct from 1 or stddev is null)
);
create table public.notes (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null,
  experiment_id uuid,
  run_id uuid,
  current_revision integer not null default 0 check (current_revision >= 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (project_id, id),
  foreign key (project_id, experiment_id) references public.experiments(project_id, id),
  foreign key (project_id, run_id) references public.runs(project_id, id),
  check (num_nonnulls(experiment_id, run_id) = 1)
);
create table public.note_revisions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null,
  note_id uuid not null,
  version integer not null check (version > 0),
  body text not null check (length(btrim(body)) between 1 and 100000),
  reason text not null check (length(btrim(reason)) between 1 and 20000),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (project_id, note_id, version),
  foreign key (project_id, note_id) references public.notes(project_id, id)
);
create table public.ingestion_tokens (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id),
  name text not null check (length(btrim(name)) between 1 and 200),
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  unique (project_id, id),
  check (expires_at > created_at)
);
create table public.audit_events (
  id bigint generated always as identity primary key,
  project_id uuid not null references public.projects(id),
  actor_id uuid references auth.users(id),
  entity_type text not null,
  entity_id text not null,
  action text not null,
  reason text,
  created_at timestamptz not null default now()
);
create index audit_events_project_idx on public.audit_events(project_id, created_at desc, id desc);
create index notes_experiment_idx on public.notes(project_id, experiment_id);
create index notes_run_idx on public.notes(project_id, run_id);
