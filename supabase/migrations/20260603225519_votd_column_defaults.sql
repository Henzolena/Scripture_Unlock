
-- Allow inserting a row with just {date, audio_status} while verse selection
-- runs in the background. The full pipeline overwrites these defaults.
ALTER TABLE public.verse_of_the_day
  ALTER COLUMN verse_ref   SET DEFAULT '',
  ALTER COLUMN book        SET DEFAULT '',
  ALTER COLUMN verse_text  SET DEFAULT '',
  ALTER COLUMN chapter     SET DEFAULT 0,
  ALTER COLUMN verse       SET DEFAULT 0;
