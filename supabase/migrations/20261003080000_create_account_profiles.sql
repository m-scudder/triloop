create table public.account_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 120),
  birth_date date not null,
  updated_at timestamptz not null default now()
);

comment on table public.account_profiles is
  'Durable account-level Athevia profile details kept separately from training backups.';

alter table public.account_profiles enable row level security;

revoke all on table public.account_profiles from anon;
grant select, insert, update, delete on table public.account_profiles to authenticated;

create policy "Athletes can read own account profile"
  on public.account_profiles
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Athletes can create own account profile"
  on public.account_profiles
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Athletes can update own account profile"
  on public.account_profiles
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Athletes can delete own account profile"
  on public.account_profiles
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);
