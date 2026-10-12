create table if not exists public.analytics_admin_credentials (
  user_id uuid primary key references auth.users(id) on delete cascade,
  password_salt text not null,
  password_hash text not null,
  password_iterations integer not null check (password_iterations >= 100000),
  updated_at timestamptz not null default now()
);

create table if not exists public.analytics_admin_sessions (
  token_hash text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  last_used_at timestamptz not null default now()
);

create index if not exists analytics_admin_sessions_expiry_idx
  on public.analytics_admin_sessions (expires_at);

create table if not exists public.analytics_admin_login_attempts (
  attempt_key text primary key,
  window_started_at timestamptz not null default now(),
  failures integer not null default 0 check (failures >= 0),
  updated_at timestamptz not null default now()
);

alter table public.analytics_admin_credentials enable row level security;
alter table public.analytics_admin_sessions enable row level security;
alter table public.analytics_admin_login_attempts enable row level security;

revoke all privileges on table public.analytics_admin_credentials from anon, authenticated;
revoke all privileges on table public.analytics_admin_sessions from anon, authenticated;
revoke all privileges on table public.analytics_admin_login_attempts from anon, authenticated;

grant select, insert, update, delete on table public.analytics_admin_credentials to service_role;
grant select, insert, update, delete on table public.analytics_admin_sessions to service_role;
grant select, insert, update, delete on table public.analytics_admin_login_attempts to service_role;

create policy "No direct analytics admin credential access"
on public.analytics_admin_credentials
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create policy "No direct analytics admin session access"
on public.analytics_admin_sessions
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create policy "No direct analytics admin login attempt access"
on public.analytics_admin_login_attempts
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

insert into public.analytics_admin_credentials (
  user_id, password_salt, password_hash, password_iterations
)
values (
  '5c16784f-2ab8-4b55-96fc-1740191a53d8'::uuid,
  '784777c6397b7c82f170bb1e2a81f1ac',
  '8d0dc1f648470e2a2d60312e1021c6e7af53d4886742068b9820a8e56ceb2c10',
  310000
)
on conflict (user_id) do update set
  password_salt = excluded.password_salt,
  password_hash = excluded.password_hash,
  password_iterations = excluded.password_iterations,
  updated_at = now();
