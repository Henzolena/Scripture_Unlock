
-- Allow anon/unauthenticated reads on verse_of_the_day (for API fallback)
CREATE POLICY "public can read votd" ON verse_of_the_day
  FOR SELECT USING (true);

-- Allow any authenticated user to read any profile (needed for friend lookup)
CREATE POLICY "authenticated users can read profiles" ON profiles
  FOR SELECT USING (auth.role() = 'authenticated');

-- Leaderboard RPC — returns user + friends stats via SECURITY DEFINER
CREATE OR REPLACE FUNCTION get_friends_leaderboard(requesting_user_id UUID)
RETURNS TABLE (
  user_id     UUID,
  name        TEXT,
  avatar_path TEXT,
  friend_code TEXT,
  total_correct  BIGINT,
  total_sessions BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH friend_ids AS (
    SELECT friend_id AS fid FROM friendships WHERE user_id = requesting_user_id
    UNION
    SELECT requesting_user_id AS fid
  ),
  agg AS (
    SELECT
      se.user_id,
      COUNT(DISTINCT se.date) FILTER (WHERE se.dismissed_at IS NOT NULL) AS total_sessions,
      COALESCE(SUM(se.questions_correct), 0)                              AS total_correct
    FROM streak_entries se
    WHERE se.user_id IN (SELECT fid FROM friend_ids)
    GROUP BY se.user_id
  )
  SELECT
    p.id,
    p.name,
    p.avatar_path,
    p.friend_code,
    COALESCE(a.total_correct,  0),
    COALESCE(a.total_sessions, 0)
  FROM profiles p
  LEFT JOIN agg a ON a.user_id = p.id
  WHERE p.id IN (SELECT fid FROM friend_ids)
  ORDER BY COALESCE(a.total_correct, 0) DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_friends_leaderboard(UUID) TO authenticated;
