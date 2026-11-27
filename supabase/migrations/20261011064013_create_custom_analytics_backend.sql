create table if not exists public.analytics_events (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null,
  occurred_at timestamptz not null,
  name text not null,
  properties jsonb not null default '{}'::jsonb,
  app_version text not null,
  app_build text not null,
  environment text not null,
  created_at timestamptz not null default now(),
  constraint analytics_events_name_length check (char_length(name) between 1 and 80),
  constraint analytics_events_properties_object check (jsonb_typeof(properties) = 'object'),
  constraint analytics_events_environment check (environment in ('development', 'testflight', 'production'))
);

create index if not exists analytics_events_user_occurred_idx
  on public.analytics_events (user_id, occurred_at desc);

create index if not exists analytics_events_name_occurred_idx
  on public.analytics_events (name, occurred_at desc);

create index if not exists analytics_events_session_idx
  on public.analytics_events (session_id, occurred_at);

alter table public.analytics_events enable row level security;
revoke all privileges on table public.analytics_events from anon, authenticated;
grant select, insert, update, delete on table public.analytics_events to service_role;

comment on table public.analytics_events is
  'Owner-controlled semantic product analytics. Health samples, GPS routes and free-form athlete text are prohibited.';

create table if not exists public.analytics_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.analytics_admins enable row level security;
revoke all privileges on table public.analytics_admins from anon, authenticated;
grant select, insert, update, delete on table public.analytics_admins to service_role;

comment on table public.analytics_admins is
  'Explicit allowlist for users permitted to access the private Athevia analytics dashboard.';
