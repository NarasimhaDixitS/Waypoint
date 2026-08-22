-- Waypoint initial schema
-- Mirrors the existing Core Data model (CommitmentEntity, GoalEntity, TaskEntity)
-- plus the UserDefaults-backed settings (ThemeManager, SleepSettings, Pomodoro).
--
-- Every table is scoped to auth.uid() via RLS -- a user can only ever see/write their own rows.
-- Run this whole file once in Supabase: Dashboard -> SQL Editor -> New query -> paste -> Run.

-- 1. profiles: one row per user, singleton settings that used to live in UserDefaults.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  appearance_mode text not null default 'system',
  accent_swatch text not null default 'blue',
  completion_mode text not null default 'tap',
  notifications_enabled boolean not null default true,
  is_pro boolean not null default false,
  sleep_start_time time not null default '23:00',
  sleep_duration_minutes int not null default 420,
  sleep_confirmed boolean not null default false,
  pomodoro_minutes int not null default 25,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);
create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = id);
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- 2. goals
create table public.goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null default '',
  notes text,
  planning_mode text not null default 'manual',
  target_date date not null,
  created_at timestamptz not null default now()
);

alter table public.goals enable row level security;
create index goals_user_id_idx on public.goals (user_id);

create policy "goals_select_own" on public.goals
  for select using (auth.uid() = user_id);
create policy "goals_insert_own" on public.goals
  for insert with check (auth.uid() = user_id);
create policy "goals_update_own" on public.goals
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "goals_delete_own" on public.goals
  for delete using (auth.uid() = user_id);

-- 3. tasks
create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  goal_id uuid references public.goals (id) on delete set null,
  title text not null default '',
  notes text,
  date date not null,
  start_time timestamptz not null,
  duration_minutes int not null default 30,
  priority text not null default 'medium',
  is_done boolean not null default false,
  completed_at timestamptz,
  series_id uuid,
  sort_index int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.tasks enable row level security;
create index tasks_user_id_date_idx on public.tasks (user_id, date);
create index tasks_goal_id_idx on public.tasks (goal_id);
create index tasks_series_id_idx on public.tasks (series_id);

create policy "tasks_select_own" on public.tasks
  for select using (auth.uid() = user_id);
create policy "tasks_insert_own" on public.tasks
  for insert with check (auth.uid() = user_id);
create policy "tasks_update_own" on public.tasks
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "tasks_delete_own" on public.tasks
  for delete using (auth.uid() = user_id);

-- 4. commitments
create table public.commitments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null default '',
  icon text not null default 'calendar',
  days_of_week text not null default '',
  start_time time not null,
  end_time time not null,
  created_at timestamptz not null default now()
);

alter table public.commitments enable row level security;
create index commitments_user_id_idx on public.commitments (user_id);

create policy "commitments_select_own" on public.commitments
  for select using (auth.uid() = user_id);
create policy "commitments_insert_own" on public.commitments
  for insert with check (auth.uid() = user_id);
create policy "commitments_update_own" on public.commitments
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "commitments_delete_own" on public.commitments
  for delete using (auth.uid() = user_id);

-- Since "Automatically expose new tables" was left off at project creation, the Data API
-- needs explicit grants. Only `authenticated` gets access -- there's no `anon` grant since
-- every table requires a signed-in user (anonymous sign-in still counts as authenticated).
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.goals to authenticated;
grant select, insert, update, delete on public.tasks to authenticated;
grant select, insert, update, delete on public.commitments to authenticated;
