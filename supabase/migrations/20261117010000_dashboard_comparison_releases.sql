create table private.dashboard_comparison_releases (
  release_key text primary key,
  created_at timestamptz not null default now(),
  is_current boolean not null default false,
  baseline_sha256 text not null check (baseline_sha256 ~ '^[a-f0-9]{64}$'),
  selected_sha256 text not null check (selected_sha256 ~ '^[a-f0-9]{64}$'),
  baseline_catalog jsonb not null,
  selected_delta jsonb not null,
  check ((baseline_catalog ->> 'schema_version') is not distinct from '2'),
  check ((baseline_catalog ->> 'kind') is not distinct from 'baseline_catalog'),
  check ((selected_delta ->> 'schema_version') is not distinct from '2'),
  check ((selected_delta ->> 'kind') is not distinct from 'selected_experiments_delta'),
  check ((selected_delta ->> 'baseline_catalog_ref') is not distinct from 'dashboard-baselines.json')
);

create unique index dashboard_comparison_one_current
  on private.dashboard_comparison_releases (is_current)
  where is_current;

alter table private.dashboard_comparison_releases enable row level security;
revoke all on private.dashboard_comparison_releases from public, anon, authenticated;

create view private.dashboard_official_baselines_v2 as
select release.release_key, baseline.value ->> 'id' as group_id, baseline.value as payload
from private.dashboard_comparison_releases release
cross join lateral jsonb_array_elements(release.baseline_catalog -> 'baselines') baseline
where release.is_current
  and baseline.value ->> 'category' = 'official_baseline'
  and baseline.value ->> 'official_baseline' = 'true';

create view private.dashboard_selected_comparison_groups_v2 as
with current_release as (
  select release_key, selected_delta
  from private.dashboard_comparison_releases
  where is_current
)
select release.release_key, entry.value ->> 'id' as group_id, entry.value as payload
from current_release release
cross join lateral jsonb_array_elements(release.selected_delta -> 'evaluation_groups') entry
union all
select release.release_key, entry.value ->> 'id' as group_id, entry.value as payload
from current_release release
cross join private.selected_evaluation_archive archive
cross join lateral jsonb_array_elements(archive.payload -> 'evaluation_groups') entry
where not exists (
  select 1
  from jsonb_array_elements(release.selected_delta -> 'excluded_existing_conditions') exclusion
  where exclusion.value ->> 'experiment_id' = archive.experiment_id
    and exclusion.value ->> 'condition_id' = entry.value ->> 'condition'
    and exclusion.value ->> 'action' = 'exclude_from_selected_comparison_only'
    and exclusion.value ->> 'source_deleted' = 'false'
);

revoke all on private.dashboard_official_baselines_v2, private.dashboard_selected_comparison_groups_v2
  from public, anon, authenticated;
