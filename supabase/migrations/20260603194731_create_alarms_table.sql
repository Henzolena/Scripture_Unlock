
CREATE TABLE public.alarms (
  id               uuid        NOT NULL PRIMARY KEY,
  user_id          uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  label            text        NOT NULL DEFAULT 'Morning devotions',
  hour             integer     NOT NULL DEFAULT 6,
  minute           integer     NOT NULL DEFAULT 0,
  is_am            boolean     NOT NULL DEFAULT true,
  is_enabled       boolean     NOT NULL DEFAULT true,
  repeat_days      integer[]   NOT NULL DEFAULT '{1,2,3,4,5}',
  pack_id          text        NOT NULL DEFAULT 'psalms',
  translation_raw  text        NOT NULL DEFAULT 'ESV',
  difficulty_raw   text        NOT NULL DEFAULT 'Regular',
  question_count   integer     NOT NULL DEFAULT 3,
  tone_identifier  text        NOT NULL DEFAULT 'alarm_digital_pure',
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.alarms ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own alarms"
  ON public.alarms FOR ALL
  USING  (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Fast per-user lookup
CREATE INDEX alarms_user_id_idx ON public.alarms (user_id);

-- Re-use the set_updated_at() function created in profiles_updated_at_trigger
CREATE TRIGGER trg_alarms_updated_at
  BEFORE UPDATE ON public.alarms
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
