-- Distinguish "answered every question" from "made the noise stop".
--
-- dismissed_at was set whenever the alarm screen closed, including when the user
-- bailed without answering. get_friends_leaderboard counts
-- `dismissed_at is not null` as a completed session, so abandoning an alarm
-- credited the streak and the leaderboard identically to finishing it — which
-- removes any cost from simply sliding the alarm off.
--
-- From now on: dismissed_at means completed. abandoned_at means the alarm was
-- silenced with questions outstanding. Attempt counts are still recorded either
-- way, so accuracy stays honest.

alter table public.streak_entries
  add column if not exists abandoned_at timestamptz;

comment on column public.streak_entries.dismissed_at is
  'Set only when every question for the session was answered correctly.';
comment on column public.streak_entries.abandoned_at is
  'Set when the alarm was silenced with questions still outstanding.';
