
-- 1. Bookmarks
CREATE TABLE IF NOT EXISTS bookmarks (
  id           UUID        PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  user_id      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  book         TEXT        NOT NULL DEFAULT '',
  chapter      INT         NOT NULL DEFAULT 1,
  verse        INT         NOT NULL DEFAULT 1,
  verse_ref    TEXT        NOT NULL DEFAULT '',
  verse_text   TEXT        NOT NULL DEFAULT '',
  translation  TEXT        NOT NULL DEFAULT 'KJV',
  note         TEXT        NOT NULL DEFAULT '',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE bookmarks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users manage own bookmarks" ON bookmarks
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE INDEX IF NOT EXISTS bookmarks_user_id_idx ON bookmarks(user_id);

-- 2. Personal verse notes
CREATE TABLE IF NOT EXISTS verse_notes (
  id         UUID        PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  verse_ref  TEXT        NOT NULL,
  book       TEXT        NOT NULL DEFAULT '',
  chapter    INT         NOT NULL DEFAULT 1,
  verse      INT         NOT NULL DEFAULT 1,
  body       TEXT        NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, verse_ref)
);
ALTER TABLE verse_notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users manage own verse notes" ON verse_notes
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE INDEX IF NOT EXISTS verse_notes_user_id_idx ON verse_notes(user_id);

-- 3. Achievements catalog
CREATE TABLE IF NOT EXISTS achievements (
  id          TEXT PRIMARY KEY,
  title       TEXT NOT NULL,
  description TEXT NOT NULL,
  icon        TEXT NOT NULL DEFAULT 'star.fill',
  category    TEXT NOT NULL DEFAULT 'streak'
    CHECK (category = ANY (ARRAY['streak','mastery','community','dedication','pack'])),
  threshold   INT  NOT NULL DEFAULT 1
);

-- Seed achievement definitions
INSERT INTO achievements (id, title, description, icon, category, threshold) VALUES
  ('first_alarm',       'First Alarm',         'Completed your very first morning session',          'alarm.fill',              'dedication', 1),
  ('streak_3',          '3-Day Streak',        'Answered Scripture three days in a row',             'flame.fill',              'streak',     3),
  ('streak_7',          'Week of the Word',    'Kept the Word alive for 7 straight days',            'flame.fill',              'streak',     7),
  ('streak_14',         'Fortnight Faithful',  'Two weeks without missing a morning session',        'sparkles',                'streak',     14),
  ('streak_30',         'Month of Devotion',   'Thirty consecutive days in the Word',                'crown.fill',              'streak',     30),
  ('streak_90',         'Quarter Champion',    '90 days of unbroken morning devotion',               'medal.fill',              'streak',     90),
  ('streak_365',        'Year of the Word',    'A full year of daily Scripture devotion',            'trophy.fill',             'streak',     365),
  ('verses_50',         '50 Verses',           'Answered 50 Scripture questions correctly',          'book.fill',               'mastery',    50),
  ('verses_200',        '200 Verses',          'Mastered 200 Scripture answers',                     'books.vertical.fill',     'mastery',    200),
  ('verses_500',        '500 Verses',          'Half a thousand correct answers',                    'text.book.closed.fill',   'mastery',    500),
  ('pack_complete',     'Pack Graduate',       'Mastered every verse in a single pack',              'graduationcap.fill',      'pack',       1),
  ('first_friend',      'First Friend',        'Connected with your first friend on Scripture Unlock','person.2.fill',           'community',  1),
  ('first_room',        'Study Host',          'Created your first community study room',            'house.fill',              'community',  1),
  ('early_bird',        'Early Bird',          'Completed a session before 6 AM',                   'sunrise.fill',            'dedication', 1),
  ('perfect_session',   'Perfect Session',     'Answered every question correctly in one session',   'checkmark.seal.fill',     'dedication', 1),
  ('bookmark_10',       'Avid Reader',         'Bookmarked 10 verses',                              'bookmark.fill',           'mastery',    10)
ON CONFLICT (id) DO NOTHING;

-- 4. User achievements (earned)
CREATE TABLE IF NOT EXISTS user_achievements (
  user_id        UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  achievement_id TEXT        NOT NULL REFERENCES achievements(id),
  earned_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, achievement_id)
);
ALTER TABLE user_achievements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users view own achievements" ON user_achievements
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE INDEX IF NOT EXISTS user_achievements_user_id_idx ON user_achievements(user_id);

-- 5. Device push tokens
CREATE TABLE IF NOT EXISTS device_tokens (
  id         UUID        PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token      TEXT        NOT NULL UNIQUE,
  platform   TEXT        NOT NULL DEFAULT 'ios',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users manage own tokens" ON device_tokens
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE INDEX IF NOT EXISTS device_tokens_user_id_idx ON device_tokens(user_id);
