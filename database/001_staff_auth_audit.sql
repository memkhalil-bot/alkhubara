-- Experts Center: initial identity and audit schema (NOT APPLIED)
-- Provision users through a trusted server endpoint using Supabase Auth Admin API.
-- Set role in auth.users.app_metadata, never user_metadata.
create extension if not exists pgcrypto;

create table if not exists public.staff_profiles (
  user_id uuid primary key references auth.users(id) on delete restrict,
  full_name text not null,
  email text not null,
  role text not null check (role in ('secretary','accountant','admin','super_admin')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  before_data jsonb,
  after_data jsonb,
  occurred_at timestamptz not null default now()
);

create table if not exists public.login_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  event_type text not null check (event_type in ('login','logout','login_failed','session_expired')),
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists audit_logs_actor_time_idx on public.audit_logs(actor_id, occurred_at desc);
create index if not exists login_events_user_time_idx on public.login_events(user_id, occurred_at desc);

alter table public.staff_profiles enable row level security;
alter table public.audit_logs enable row level security;
alter table public.login_events enable row level security;

-- A user's own profile is visible, and managers can view all staff.
create policy "staff profiles readable by self or management"
on public.staff_profiles for select to authenticated
using (
  user_id = (select auth.uid())
  or (select auth.jwt() -> 'app_metadata' ->> 'role') in ('admin','super_admin')
);

-- Only Super Admin may manage staff profiles through authenticated API.
-- A separate trusted server must atomically update Auth app_metadata and staff_profiles.
create policy "super admin may insert staff profiles"
on public.staff_profiles for insert to authenticated
with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin');
create policy "super admin may update staff profiles"
on public.staff_profiles for update to authenticated
using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin')
with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'super_admin');

-- Immutable audit/login events: only trusted backend/service role inserts.
-- Management can read; no client-side UPDATE or DELETE policies.
create policy "management reads audit"
on public.audit_logs for select to authenticated
using ((select auth.jwt() -> 'app_metadata' ->> 'role') in ('admin','super_admin'));
create policy "management reads login events"
on public.login_events for select to authenticated
using ((select auth.jwt() -> 'app_metadata' ->> 'role') in ('admin','super_admin'));

revoke all on public.staff_profiles, public.audit_logs, public.login_events from anon;
grant select on public.staff_profiles, public.audit_logs, public.login_events to authenticated;
grant insert, update on public.staff_profiles to authenticated;

-- NOTE: privileged writes to audit_logs/login_events must happen server-side.
-- Do not put a service-role key in client JavaScript.
-- Do not deploy this migration until a dedicated Experts Center Supabase project exists.
