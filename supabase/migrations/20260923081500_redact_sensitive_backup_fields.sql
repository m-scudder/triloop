-- Redact exact location and free-text health-adjacent content from cloud backups.
-- Structured recovery signals remain because Athevia's training/safety engine uses them.

create or replace function public.sanitize_athevia_backup_snapshot(input_snapshot jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  sanitized jsonb := input_snapshot;
  sanitized_plans jsonb := '[]'::jsonb;
  sanitized_workouts jsonb;
  plan_item jsonb;
  workout_item jsonb;
  feedback_item jsonb;
  imported_item jsonb;
  metrics_item jsonb;
begin
  if jsonb_typeof(input_snapshot -> 'plans') <> 'array' then
    return input_snapshot;
  end if;

  for plan_item in
    select value from jsonb_array_elements(input_snapshot -> 'plans')
  loop
    sanitized_workouts := '[]'::jsonb;

    if jsonb_typeof(plan_item -> 'workouts') = 'array' then
      for workout_item in
        select value from jsonb_array_elements(plan_item -> 'workouts')
      loop
        -- Free-text workout notes are not required to rebuild/adapt training.
        if jsonb_typeof(workout_item -> 'feedback') = 'object' then
          feedback_item := (workout_item -> 'feedback') - 'notes';
          workout_item := jsonb_set(
            workout_item,
            '{feedback}',
            feedback_item,
            false
          );
        end if;

        -- Exact GPS routes remain local/HealthKit data. Keep aggregate metrics.
        if jsonb_typeof(workout_item -> 'importedSummary') = 'object' then
          imported_item := workout_item -> 'importedSummary';

          if jsonb_typeof(imported_item -> 'metrics') = 'object' then
            metrics_item := (imported_item -> 'metrics') - 'route';
            imported_item := jsonb_set(
              imported_item,
              '{metrics}',
              metrics_item,
              false
            );
            workout_item := jsonb_set(
              workout_item,
              '{importedSummary}',
              imported_item,
              false
            );
          end if;
        end if;

        sanitized_workouts := sanitized_workouts || jsonb_build_array(workout_item);
      end loop;

      plan_item := jsonb_set(plan_item, '{workouts}', sanitized_workouts, false);
    end if;

    sanitized_plans := sanitized_plans || jsonb_build_array(plan_item);
  end loop;

  sanitized := jsonb_set(sanitized, '{plans}', sanitized_plans, false);
  return sanitized;
end;
$$;

revoke all on function public.sanitize_athevia_backup_snapshot(jsonb)
  from public, anon, authenticated;

-- Scrub all retained historical snapshots immediately.
update public.backup_revisions
set snapshot = public.sanitize_athevia_backup_snapshot(snapshot);

create or replace function public.sanitize_athevia_backup_revision_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.snapshot := public.sanitize_athevia_backup_snapshot(new.snapshot);
  return new;
end;
$$;

revoke all on function public.sanitize_athevia_backup_revision_before_insert()
  from public, anon, authenticated;

drop trigger if exists sanitize_athevia_backup_revision_before_insert
  on public.backup_revisions;

create trigger sanitize_athevia_backup_revision_before_insert
before insert on public.backup_revisions
for each row
execute function public.sanitize_athevia_backup_revision_before_insert();

comment on function public.sanitize_athevia_backup_snapshot(jsonb) is
  'Removes exact GPS routes and free-text workout notes from Athevia cloud backup snapshots.';
