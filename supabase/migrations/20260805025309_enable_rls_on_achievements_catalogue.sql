-- public.achievements was the only table in the exposed schema with RLS off,
-- so the anon key (which ships inside the app binary) could read *and write*
-- every row of the achievements catalogue.
--
-- No policy is added deliberately. Nothing reads this table over PostgREST:
-- AchievementService.swift hardcodes the achievement ids client-side and only
-- queries user_achievements. The service_role key used by the backend bypasses
-- RLS, so server-side access is unaffected.
--
-- If achievements ever become server-driven, open it up with:
--   create policy "Signed-in users can read achievements"
--     on public.achievements for select to authenticated using (true);

alter table public.achievements enable row level security;
