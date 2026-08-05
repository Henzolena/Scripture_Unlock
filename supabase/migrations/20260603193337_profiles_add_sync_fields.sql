
-- Add parallel_language and accountability_partner_email to profiles so they
-- survive device changes (previously silently dropped from cloud sync).
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS parallel_language            TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS accountability_partner_email TEXT NOT NULL DEFAULT '';
