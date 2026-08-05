
-- Profiles table
create table profiles (
  id text primary key,
  name text not null default '',
  active_pack_id text not null default 'psalms',
  question_count int not null default 3,
  snooze_tax bool not null default true,
  sabbath_mode bool not null default true,
  appearance text not null default 'system',
  updated_at timestamptz not null default now()
);

-- Streak entries table
create table streak_entries (
  user_id text not null,
  date date not null,
  questions_answered int not null default 0,
  questions_correct int not null default 0,
  snooze_count int not null default 0,
  dismissed_at timestamptz,
  primary key (user_id, date)
);

-- Row Level Security
alter table profiles enable row level security;
alter table streak_entries enable row level security;

-- Policies: users can only read/write their own rows
create policy "Users manage own profile"
  on profiles for all
  using (auth.uid()::text = id)
  with check (auth.uid()::text = id);

create policy "Users manage own streaks"
  on streak_entries for all
  using (auth.uid()::text = user_id)
  with check (auth.uid()::text = user_id);
