
-- Tracks how well each user knows each verse in each pack.
-- Drives real progress bars, spaced-repetition ordering, and mastery badges.
CREATE TABLE public.verse_mastery (
  user_id        uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  pack_id        text        NOT NULL,           -- "psalms", "gospels" …
  verse_ref      text        NOT NULL,           -- "Psalm 23:1"
  correct_count  integer     NOT NULL DEFAULT 0, -- total correct practice answers
  attempt_count  integer     NOT NULL DEFAULT 0, -- total practice attempts
  last_practiced date        NOT NULL DEFAULT CURRENT_DATE,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, pack_id, verse_ref)
);

-- Mastery level helper (0–5) — computed in Swift but stored for fast queries:
-- 0 = not started  1 = trying (1-2)  2 = familiar (3-5)
-- 3 = learning (6-9)  4 = strong (10-14)  5 = mastered (15+)

ALTER TABLE public.verse_mastery ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own verse mastery"
  ON public.verse_mastery FOR ALL
  USING  (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Fast lookup for a user's full pack stats
CREATE INDEX verse_mastery_user_pack_idx
  ON public.verse_mastery (user_id, pack_id);

-- Auto-refresh updated_at
CREATE TRIGGER trg_verse_mastery_updated_at
  BEFORE UPDATE ON public.verse_mastery
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
