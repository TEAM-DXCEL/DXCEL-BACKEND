alter function public.read_dashboard_comparison_release() set schema private;
alter function private.read_dashboard_comparison_release()
  rename to project_dashboard_comparison_release;
revoke all on function private.project_dashboard_comparison_release() from service_role;

create materialized view private.dashboard_comparison_release_projection as
select private.project_dashboard_comparison_release() as payload;

revoke all on private.dashboard_comparison_release_projection from public, anon, authenticated;

create function private.refresh_dashboard_comparison_release_projection()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  refresh materialized view private.dashboard_comparison_release_projection;
  return null;
end;
$$;

revoke all on function private.refresh_dashboard_comparison_release_projection()
  from public, anon, authenticated;

create trigger refresh_dashboard_comparison_release_projection
after insert or update or delete or truncate on private.dashboard_comparison_releases
for each statement execute function private.refresh_dashboard_comparison_release_projection();

create function public.read_dashboard_comparison_release()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select payload from private.dashboard_comparison_release_projection;
$$;

revoke all on function public.read_dashboard_comparison_release() from public, anon, authenticated;
grant execute on function public.read_dashboard_comparison_release() to service_role;
