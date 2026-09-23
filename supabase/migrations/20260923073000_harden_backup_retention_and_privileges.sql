-- Harden Athevia cloud backups:
-- 1. Keep only the latest 10 immutable backup revisions per user.
-- 2. Restrict the authenticated client to the operations it actually uses.
--
-- Account deletion still removes all revisions through the existing
-- auth.users(user_id) ON DELETE CASCADE relationship.

-- Remove historical revisions before enabling ongoing retention.
with ranked_revisions as (
  select
    id,
    row_number() over (
      partition by user_id
      order by created_at desc, id desc
    ) as revision_rank
  from public.backup_revisions
)
delete from public.backup_revisions
where id in (
  select id
  from ranked_revisions
  where revision_rank > 10
);

-- Client code only uploads a new immutable revision and reads the latest one.
-- Retention deletion is server-owned, so authenticated users do not need
-- DELETE, UPDATE, TRUNCATE, REFERENCES, or TRIGGER privileges.
revoke all privileges on table public.backup_revisions from authenticated;
revoke all privileges on table public.backup_revisions from anon;

grant select, insert on table public.backup_revisions to authenticated;

-- Remove the now-unused client DELETE policy. Account deletion is handled by
-- the auth.users foreign-key cascade, not by direct client table deletion.
drop policy if exists "Athletes can delete own backups"
  on public.backup_revisions;

-- Run retention as the table owner so clients do not need DELETE permission.
-- The empty search_path prevents object-shadowing inside this SECURITY DEFINER
-- function; all database objects are schema-qualified.
create or replace function public.prune_athevia_backup_revisions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.backup_revisions
  where id in (
    select id
    from public.backup_revisions
    where user_id = new.user_id
    order by created_at desc, id desc
    offset 10
  );

  return new;
end;
$$;

revoke all on function public.prune_athevia_backup_revisions()
  from public, anon, authenticated;

drop trigger if exists prune_athevia_backup_revisions_after_insert
  on public.backup_revisions;

create trigger prune_athevia_backup_revisions_after_insert
after insert on public.backup_revisions
for each row
execute function public.prune_athevia_backup_revisions();

comment on function public.prune_athevia_backup_revisions() is
  'Keeps only the 10 newest Athevia backup revisions for the user whose backup was inserted.';
