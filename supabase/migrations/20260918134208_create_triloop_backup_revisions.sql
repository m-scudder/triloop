create table public.backup_revisions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  schema_version integer not null check (schema_version > 0),
  snapshot jsonb not null,
  created_at timestamptz not null default now()
);

comment on table public.backup_revisions is
  'Immutable, versioned TriLoop cloud backups. SwiftData remains the operational source of truth.';

create index backup_revisions_user_created_idx
  on public.backup_revisions (user_id, created_at desc);

alter table public.backup_revisions enable row level security;

revoke all on table public.backup_revisions from anon;
grant select, insert, delete on table public.backup_revisions to authenticated;

create policy "Athletes can read own backups"
  on public.backup_revisions
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Athletes can create own backups"
  on public.backup_revisions
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Athletes can delete own backups"
  on public.backup_revisions
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);
