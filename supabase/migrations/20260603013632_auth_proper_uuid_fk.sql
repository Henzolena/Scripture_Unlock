
-- Drop policies first, then alter types, then recreate

-- profiles
DROP POLICY IF EXISTS "Users manage own profile" ON public.profiles;
ALTER TABLE public.profiles ALTER COLUMN id TYPE uuid USING id::uuid;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_id_fkey
  FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
CREATE POLICY "Users manage own profile"
  ON public.profiles FOR ALL
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- streak_entries
DROP POLICY IF EXISTS "Users manage own streaks" ON public.streak_entries;
ALTER TABLE public.streak_entries ALTER COLUMN user_id TYPE uuid USING user_id::uuid;
ALTER TABLE public.streak_entries
  ADD CONSTRAINT streak_entries_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
CREATE POLICY "Users manage own streaks"
  ON public.streak_entries FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
