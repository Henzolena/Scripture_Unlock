
-- Public storage bucket for Gemini-generated devotional audio files.
-- Files are named {date}.mp3  (e.g. 2026-06-03.mp3)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'verse-audio',
  'verse-audio',
  true,
  10485760,   -- 10 MB max per file
  ARRAY['audio/mpeg', 'audio/mp4', 'audio/wav', 'audio/ogg']
)
ON CONFLICT (id) DO NOTHING;

-- Allow anonymous reads (iOS fetches without auth)
CREATE POLICY "Public read verse audio"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'verse-audio');

-- Allow service role to upload / overwrite
CREATE POLICY "Service role write verse audio"
  ON storage.objects FOR INSERT
  TO service_role
  WITH CHECK (bucket_id = 'verse-audio');

CREATE POLICY "Service role update verse audio"
  ON storage.objects FOR UPDATE
  TO service_role
  USING (bucket_id = 'verse-audio');
