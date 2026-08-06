-- The previous policy was `USING (auth.role() = 'authenticated')`, so any signed-in
-- user could read every profile row — name, friend_code and avatar_path for the
-- entire user base — by hitting /rest/v1/profiles directly with the anon key that
-- ships inside the app binary. It was justified as "needed for friend lookup",
-- but nothing actually needs it:
--
--   * every direct read in the client is scoped to the caller's own row
--     (SupabaseService selects/updates with .eq("id", uid))
--   * friends' names and avatars arrive through community_dashboard(),
--     study_session_snapshot(), study_room_members_snapshot() and
--     get_friends_leaderboard()
--   * friend-code lookup happens inside send_friend_request_by_code()
--
-- All nine functions in public that touch profiles are SECURITY DEFINER, so they
-- bypass RLS and keep working unchanged. Verified by pg_proc.prosecdef.

drop policy if exists "authenticated users can read profiles" on public.profiles;

create policy "Users can read their own profile"
  on public.profiles
  for select
  to authenticated
  using (id = auth.uid());
