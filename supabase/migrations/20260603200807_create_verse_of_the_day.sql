
-- Verse of the Day table.
-- Verse text comes from the Railway API; this table owns audio metadata only
-- plus enough verse fields for the Railway audio generator to work standalone.
CREATE TABLE public.verse_of_the_day (
  date         date        NOT NULL PRIMARY KEY,
  verse_ref    text        NOT NULL,              -- "2 Kings 13:17"
  book         text        NOT NULL,              -- "2KI"
  chapter      integer     NOT NULL,
  verse        integer     NOT NULL,
  verse_text   text        NOT NULL,
  translation  text        NOT NULL DEFAULT 'KJV',
  audio_url    text,                              -- NULL until generated
  audio_status text        NOT NULL DEFAULT 'pending', -- pending|generating|ready|failed
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

-- Publicly readable — iOS fetches without auth
ALTER TABLE public.verse_of_the_day ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public read verse of the day"
  ON public.verse_of_the_day FOR SELECT
  USING (true);

-- Only service role can write (Railway backend uses service_role key)
CREATE POLICY "Service role write verse of the day"
  ON public.verse_of_the_day FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE TRIGGER trg_votd_updated_at
  BEFORE UPDATE ON public.verse_of_the_day
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Seed today's verse (2 Kings 13:17 — as returned by Railway /votd today)
INSERT INTO public.verse_of_the_day (date, verse_ref, book, chapter, verse, verse_text, translation, audio_status)
VALUES (
  CURRENT_DATE,
  '2 Kings 13:17',
  '2KI',
  13,
  17,
  'And he said, Open the window eastward. And he opened it. Then Elisha said, Shoot. And he shot. And he said, The arrow of the LORD''S deliverance, and the arrow of deliverance from Syria: for thou shalt smite the Syrians in Aphek, till thou have consumed them.',
  'KJV',
  'pending'
)
ON CONFLICT (date) DO NOTHING;
