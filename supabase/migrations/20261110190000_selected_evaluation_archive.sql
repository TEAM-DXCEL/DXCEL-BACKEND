create table private.selected_evaluation_archive (
  experiment_id text primary key check (experiment_id ~ '^EXP-[0-9]+$'),
  payload jsonb not null,
  check ((payload #>> '{experiment,id}') is not distinct from experiment_id),
  check ((payload #>> '{experiment,type}') is not distinct from 'evaluation')
);

alter table private.selected_evaluation_archive enable row level security;

create function public.read_selected_evaluations()
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select payload
  from private.selected_evaluation_archive
  order by experiment_id;
$$;

revoke all on function public.read_selected_evaluations() from public, anon, authenticated;
grant execute on function public.read_selected_evaluations() to service_role;
